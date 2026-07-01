repo_organization := "projectbluefin"
base_image_org := "quay.io/fedora-ostree-desktops"
base_image_name := "silverblue"
# common_image and brew_image refs are read from image-versions.yml at build time
images := '(
    [bluefin]=bluefin
)'
flavors := '(
    [main]=main
    [nvidia]=nvidia
)'
tags := '(
    [testing]=testing
)'
export SUDOIF := if `id -u` == "0" { "" } else { "sudo" }
export PODMAN := if path_exists("/usr/bin/podman") == "true" { env("PODMAN", "/usr/bin/podman") } else if path_exists("/usr/bin/docker") == "true" { env("PODMAN", "docker") } else { env("PODMAN", "exit 1 ; ") }
export PULL_POLICY := if PODMAN =~ "docker" { "missing" } else { "newer" }
just := just_executable()

[private]
default:
    @{{ just }} --list

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	{{ just }} --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile"
    {{ just }} --unstable --fmt --check -f Justfile

# Run unit tests for shared build scripts
[group('Just')]
test-unit:
    #!/usr/bin/bash
    set -euo pipefail
    if ! command -v bats &>/dev/null; then
        echo "bats not found — install with: sudo apt-get install bats  OR  npm install -g bats"
        exit 1
    fi
    echo "Running unit tests..."
    bats tests/unit/

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/bash
    find . -type f -name "*.just" | while read -r file; do
    	echo "Checking syntax: $file"
    	{{ just }} --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile"
    {{ just }} --unstable --fmt -f Justfile || { exit 1; }

# Clean Repo
[group('Utility')]
clean:
    #!/usr/bin/bash
    set -eoux pipefail
    touch _build
    find *_build* -exec rm -rf {} \;
    rm -f previous.manifest.json
    rm -f changelog.md
    rm -f output.env

# Check if valid combo
[group('Utility')]
[private]
validate $image $tag $flavor:
    #!/usr/bin/bash
    set -eou pipefail
    declare -A images={{ images }}
    declare -A tags={{ tags }}
    declare -A flavors={{ flavors }}

    checkimage="${images[${image}]-}"
    checktag="${tags[${tag}]-}"
    checkflavor="${flavors[${flavor}]-}"

    # Validity Checks
    if [[ -z "$checkimage" ]]; then
        echo "Invalid Image..."
        exit 1
    fi
    if [[ -z "$checktag" ]]; then
        echo "Invalid tag..."
        exit 1
    fi
    if [[ -z "$checkflavor" ]]; then
        echo "Invalid flavor..."
        exit 1
    fi

# Build Image
[group('Image')]
build $image="bluefin" $tag="testing" $flavor="main" rechunk="0" ghcr="0" pipeline="0" $kernel_pin="":
    #!/usr/bin/bash

    echo "::group:: Build Prep"
    set -eoux pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    # Read image refs and digests from image-versions.yml (single source of truth)
    common_image=$(yq -r '.images[] | select(.name == "common") | .image + ":" + .tag' image-versions.yml)
    common_image_sha=$(yq -r '.images[] | select(.name == "common") | .digest' image-versions.yml)
    brew_image=$(yq -r '.images[] | select(.name == "brew") | .image + ":" + .tag' image-versions.yml)
    brew_image_sha=$(yq -r '.images[] | select(.name == "brew") | .digest' image-versions.yml)

    # AKMODS Flavor and Kernel Version
    if [[ "${flavor}" =~ hwe ]]; then
        akmods_flavor="bazzite"
    elif [[ "${tag}" =~ beta ]]; then
        akmods_flavor="main"
    else
        akmods_flavor="main"
    fi

    # Fedora Version
    if [[ {{ ghcr }} == "0" ]]; then
        rm -f /tmp/manifest.json
    fi
    fedora_version=$({{ just }} fedora_version '{{ image }}' '{{ tag }}' '{{ flavor }}' '{{ kernel_pin }}')

    # Resolve and pin the base image digest first (TOCTOU fix)
    BASE_IMAGE_MAX_RETRIES=5
    BASE_IMAGE_RETRY_DELAY=10
    last_digest_error=""
    for attempt in $(seq 1 ${BASE_IMAGE_MAX_RETRIES}); do
        if inspect_output=$(skopeo inspect --retry-times 3 docker://quay.io/fedora-ostree-desktops/silverblue:"${fedora_version}" 2>&1); then
            base_image_digest=$(jq -r '.Digest // empty' <<<"${inspect_output}")
            if [[ -n "${base_image_digest:-}" ]]; then
                break
            fi
            last_digest_error="skopeo inspect returned no digest"
        else
            last_digest_error="${inspect_output}"
        fi

        if [[ "${attempt}" -eq "${BASE_IMAGE_MAX_RETRIES}" ]]; then
            echo "ERROR: Could not resolve silverblue digest after ${BASE_IMAGE_MAX_RETRIES} attempts. Refusing to build without a pinned, verified base image."
            echo "Last error: ${last_digest_error}"
            exit 1
        fi

        echo "NOTICE: Digest resolution attempt ${attempt}/${BASE_IMAGE_MAX_RETRIES} failed, retrying in ${BASE_IMAGE_RETRY_DELAY}s..."
        sleep "${BASE_IMAGE_RETRY_DELAY}"
    done
    base_image_ref="quay.io/fedora-ostree-desktops/silverblue:${fedora_version}@${base_image_digest}"

    # Verify Base Image with cosign — FATAL in CI, skippable locally for dev convenience.
    # A verification failure means the base image cannot be trusted; continuing would launder
    # a potentially compromised image through the Bluefin signing pipeline.
    if [[ "${SKIP_BASE_VERIFY:-}" == "1" && "${CI:-}" != "true" ]]; then
        echo "WARNING: Skipping base image verification (SKIP_BASE_VERIFY=1, local dev only)"
    else
        {{ just }} verify-container "silverblue:${fedora_version}@${base_image_digest}" quay.io/fedora-ostree-desktops "{{ justfile_directory() }}/keys/fedora-ostree.pub" || {
            echo "ERROR: Base image cosign verification FAILED for ${base_image_ref}"
            echo "This may indicate a key rotation, registry compromise, or transient network issue."
            echo "If this is a known key rotation, update keys/fedora-ostree.pub and retry."
            echo "If this is a transient network issue, retry the build."
            exit 1
        }
    fi

    # Kernel Release/Pin
    if [[ -z "${kernel_pin:-}" ]]; then
        kernel_release=$(skopeo inspect --retry-times 3 docker://ghcr.io/ublue-os/akmods:"${akmods_flavor}"-"${fedora_version}" | jq -r '.Labels["ostree.linux"]')
    else
        kernel_release="${kernel_pin}"
    fi

    # Verify Containers with Cosign
    {{ just }} verify-container "akmods:${akmods_flavor}-${fedora_version}-${kernel_release}"
    if [[ "${akmods_flavor}" =~ coreos ]]; then
        {{ just }} verify-container "akmods-zfs:${akmods_flavor}-${fedora_version}-${kernel_release}"
    fi
    if [[ "${flavor}" =~ nvidia ]]; then
        {{ just }} verify-container "akmods-nvidia-open:${akmods_flavor}-${fedora_version}-${kernel_release}"
    fi

    # Get Version
    if [[ "${tag}" =~ stable ]]; then
        ver="${fedora_version}.$(date +%Y%m%d)"
    else
        ver="${tag}-${fedora_version}.$(date +%Y%m%d)"
    fi
    skopeo list-tags docker://ghcr.io/{{ repo_organization }}/${image_name} > /tmp/repotags.json 2>/dev/null \
        || echo '{"Tags":[]}' > /tmp/repotags.json
    if [[ $(jq "any(.Tags[]; contains(\"$ver\"))" < /tmp/repotags.json) == "true" ]]; then
        POINT="1"
        while $(jq -e "any(.Tags[]; contains(\"$ver.$POINT\"))" < /tmp/repotags.json)
        do
            (( POINT++ ))
        done
    fi
    if [[ -n "${POINT:-}" ]]; then
        ver="${ver}.$POINT"
    fi

    # Build Arguments
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "AKMODS_FLAVOR=${akmods_flavor}")
    BUILD_ARGS+=("--build-arg" "BASE_IMAGE_REF=${base_image_ref}")
    BUILD_ARGS+=("--build-arg" "COMMON_IMAGE=${common_image}")
    BUILD_ARGS+=("--build-arg" "COMMON_IMAGE_SHA=${common_image_sha}")
    BUILD_ARGS+=("--build-arg" "BREW_IMAGE=${brew_image}")
    BUILD_ARGS+=("--build-arg" "BREW_IMAGE_SHA=${brew_image_sha}")
    BUILD_ARGS+=("--build-arg" "FEDORA_MAJOR_VERSION=${fedora_version}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${image_name}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR={{ repo_organization }}")
    BUILD_ARGS+=("--build-arg" "KERNEL=${kernel_release}")
    BUILD_ARGS+=("--build-arg" "VERSION=${ver}")
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi
    BUILD_ARGS+=("--build-arg" "UBLUE_IMAGE_TAG=${tag}")
    if [[ "${PODMAN}" =~ docker && "${TERM}" == "dumb" ]]; then
        BUILD_ARGS+=("--progress" "plain")
    fi

    # Labels
    LABELS=()
    LABELS+=("--label" "org.opencontainers.image.title=${image_name}")
    LABELS+=("--label" "org.opencontainers.image.version=${ver}")
    LABELS+=("--label" "ostree.linux=${kernel_release}")
    LABELS+=("--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/projectbluefin/bluefin/refs/heads/main/README.md")
    LABELS+=("--label" "io.artifacthub.package.logo-url=https://avatars.githubusercontent.com/u/120078124?s=200&v=4")
    LABELS+=("--label" "org.opencontainers.image.description=The next generation Linux workstation, designed for reliability, performance, and sustainability.")
    LABELS+=("--label" "containers.bootc=1")
    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    LABELS+=("--label" "org.opencontainers.image.source=https://raw.githubusercontent.com/projectbluefin/bluefin/refs/heads/main/Containerfile")
    LABELS+=("--label" "org.opencontainers.image.url=https://projectbluefin.io")
    LABELS+=("--label" "org.opencontainers.image.vendor={{ repo_organization }}")
    LABELS+=("--label" "io.artifacthub.package.deprecated=false")
    LABELS+=("--label" "io.artifacthub.package.keywords=bootc,bluefin,ublue,universal-blue")
    LABELS+=("--label" "io.artifacthub.package.maintainers=[{\"name\": \"castrojo\", \"email\": \"jorge.castro@gmail.com\"}]")

    echo "::endgroup::"
    echo "::group:: Build Container"

    # Build Image
    PODMAN_BUILD_ARGS=("${BUILD_ARGS[@]}" "${LABELS[@]}" --tag localhost/"${image_name}:${tag}" --file Containerfile)

    # Add GitHub token secret if available (for CI/CD)
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "Adding GitHub token as build secret"
        PODMAN_BUILD_ARGS+=(--secret "id=GITHUB_TOKEN,env=GITHUB_TOKEN")
    else
        echo "No GitHub token found - build may hit rate limit"
    fi

    # Registry layer cache — reduces build time by reusing unchanged layers from GHCR.
    # Cache write (REGISTRY_CACHE_WRITE=1) is set by CI for non-PR builds only.
    # PR builds and local builds are read-only to prevent cache poisoning.
    # Note: Podman 5.x+ requires untagged refs for --cache-from/--cache-to.
    #
    # We use the image's own GHCR package (e.g. ghcr.io/projectbluefin/bluefin) as the
    # cache repository. This avoids needing a separate bluefin-cache package and ensures
    # GITHUB_TOKEN already has write access (it pushes the final image to this same ref).
    # Buildah stores cache entries as SHA-keyed blobs that coexist safely with named tags.
    cache_ref="ghcr.io/{{ repo_organization }}/${image_name}"
    # Probe: use skopeo list-tags — succeeds on any accessible (public) repo, including
    # ones with only SHA-keyed blobs. Fails on 403 (private) or 404 (not yet pushed).
    cache_readable=false
    if skopeo list-tags "docker://${cache_ref}" >/dev/null 2>&1; then
        cache_readable=true
        PODMAN_BUILD_ARGS+=(--cache-from "${cache_ref}")
    fi
    if [[ "${REGISTRY_CACHE_WRITE:-0}" == "1" ]]; then
        PODMAN_BUILD_ARGS+=(--cache-to "${cache_ref}")
        echo "Registry layer cache: read=${cache_readable}+write (${cache_ref})"
    elif [[ "${cache_readable}" == "true" ]]; then
        echo "Registry layer cache: read-only (${cache_ref})"
    else
        echo "Registry layer cache: disabled (${cache_ref} not yet accessible)"
    fi

    ${PODMAN} build "${PODMAN_BUILD_ARGS[@]}" .
    echo "::endgroup::"

    # Rechunk
    if [[ "{{ rechunk }}" == "1" && "{{ ghcr }}" == "1" && "{{ pipeline }}" == "1" ]]; then
        ${SUDOIF} {{ just }} rechunk "${image}" "${tag}" "${flavor}" 1 1
    elif [[ "{{ rechunk }}" == "1" && "{{ ghcr }}" == "1" ]]; then
        ${SUDOIF} {{ just }} rechunk "${image}" "${tag}" "${flavor}" 1
    elif [[ "{{ rechunk }}" == "1" ]]; then
        ${SUDOIF} {{ just }} rechunk "${image}" "${tag}" "${flavor}"
    fi

# Build Image and Rechunk
[group('Image')]
build-rechunk image="bluefin" tag="testing" flavor="main" kernel_pin="":
    @{{ just }} build {{ image }} {{ tag }} {{ flavor }} 1 0 0 {{ kernel_pin }}

# Build Image with GHCR Flag
[group('Image')]
build-ghcr image="bluefin" tag="testing" flavor="main" kernel_pin="":
    #!/usr/bin/bash
    if [[ "${UID}" -gt "0" ]]; then
        echo "Must Run with sudo or as root..."
        exit 1
    fi
    {{ just }} build {{ image }} {{ tag }} {{ flavor }} 0 1 0 {{ kernel_pin }}

# Build Image for Pipeline:
[group('Image')]
build-pipeline image="bluefin" tag="testing" flavor="main" kernel_pin="":
    #!/usr/bin/bash
    ${SUDOIF} {{ just }} build {{ image }} {{ tag }} {{ flavor }} 1 1 1 {{ kernel_pin }}

# Rechunk Image
[group('Image')]
[private]
rechunk $image="bluefin" $tag="testing" $flavor="main" ghcr="0" pipeline="0" previous_build="0":
    #!/usr/bin/bash
    set -eoux pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    # Check if image is already built
    ID=$(${PODMAN} images --filter reference=localhost/"${image_name}":"${tag}" --format "'{{ '{{.ID}}' }}'")
    if [[ -z "$ID" ]]; then
        {{ just }} build "${image}" "${tag}" "${flavor}"
    fi

    if [[ "{{ ghcr }}" == "0" ]]; then
        {{ just }} load-rootful "${image}" "${tag}" "${flavor}"
    fi

    IMAGE_REF=localhost/"${image_name}":"${tag}"
    fedora_version=$(${SUDOIF} ${PODMAN} inspect "${IMAGE_REF}" | jq -r '.[].Config.Labels["ostree.linux"]' | grep -oP 'fc\K[0-9]+')

    # TODO: Switch fully to --previous-build once rpm-ostree 2026.1+ lands everywhere.
    if [[ "{{ previous_build }}" == "1" ]]; then
        PREVIOUS_IMAGE=ghcr.io/{{ repo_organization }}/"${image_name}":"${tag}"

        if skopeo inspect "docker://${PREVIOUS_IMAGE}" | jq -e '.LayersData[1:] | all(.Annotations?["ostree.components"]?)' >/dev/null; then
            ${SUDOIF} ${PODMAN} pull "${PREVIOUS_IMAGE}"
        else
            echo "${PREVIOUS_IMAGE} is not chunked yet. Building a fresh layer plan instead."
            PREVIOUS_IMAGE=""
        fi
    fi

    if [[ "{{ ghcr }}" == "1" ]]; then
        CHUNKED_IMAGE=localhost/"${image_name}":"${tag}"
        if [[ -n "${PREVIOUS_IMAGE:-}" ]]; then
            CHUNKED_IMAGE="${PREVIOUS_IMAGE}"
        fi
    else
        # Keep the original unrechunked image around for local builds.
        CHUNKED_IMAGE=localhost/"${image_name}":"${tag}"-chunked
    fi

    ${SUDOIF} ${PODMAN} run --rm \
        --pull=${PULL_POLICY} \
        --privileged \
        -v "/var/lib/containers:/var/lib/containers" \
        --entrypoint /usr/bin/rpm-ostree \
        "{{ base_image_org }}/{{ base_image_name }}:${fedora_version}" \
        compose build-chunked-oci \
        --max-layers 127 \
        --format-version=2 \
        --bootc \
        --from "${IMAGE_REF}" \
        --output containers-storage:${CHUNKED_IMAGE}

    if [[ "{{ ghcr }}" == "1" && -n "${PREVIOUS_IMAGE:-}" ]]; then
        ${SUDOIF} ${PODMAN} tag "${CHUNKED_IMAGE}" "${IMAGE_REF}"
        ${SUDOIF} ${PODMAN} image rm -f "${CHUNKED_IMAGE}"
    fi

    # Pipeline Checks
    if [[ {{ pipeline }} == "1" && -n "${SUDO_USER:-}" ]]; then
        sudo -u "${SUDO_USER}" {{ just }} secureboot "${image}" "${tag}" "${flavor}"
    fi

# Load an image into rootful Podman for rechunking
[group('Image')]
load-rootful $image="bluefin" $tag="testing" $flavor="main":
    #!/usr/bin/bash
    set -oux pipefail

    # Validate
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    if [[ ! "$(id -u)" == 0 && ! ${PODMAN} =~ docker ]]; then
        ID=$(${PODMAN} images --filter reference=localhost/"${image_name}":"${tag}" --format "'{{ '{{.ID}}' }}'")
        if [[ -z "$ID" ]]; then
            {{ just }} build "${image}" "${tag}" "${flavor}"
        fi
        ${PODMAN} image scp localhost/"${image_name}":"${tag}" root@localhost::
    fi

# Retag rechunked images for downstream steps
[group('Image')]
load-rechunk image="bluefin" tag="testing" flavor="main":
    #!/usr/bin/bash
    set -eou pipefail

    # Validate
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    source_tag="{{ tag }}"

    source_ref=localhost/"${image_name}":"${source_tag}"
    source_chunked_ref=${source_ref}-chunked
    target_ref=localhost/"${image_name}":"{{ tag }}"

    SOURCE_ID=$(${PODMAN} images --filter reference="${source_chunked_ref}" --format "'{{ '{{.ID}}' }}'")
    if [[ -n "${SOURCE_ID}" ]]; then
        source_ref="${source_chunked_ref}"
    fi

    if [[ "${source_ref}" == "${target_ref}" ]]; then
        exit 0
    fi

    IMAGE=$(${PODMAN} inspect "${source_ref}" | jq -r '.[].Id')
    TARGET_ID=$(${PODMAN} images --filter reference="${target_ref}" --format "'{{ '{{.ID}}' }}'")
    if [[ -n "${TARGET_ID}" ]]; then
        ${PODMAN} rmi "${target_ref}" || true
    fi
    ${PODMAN} tag "${IMAGE}" "${target_ref}"

# Run Container
[group('Image')]
run $image="bluefin" $tag="testing" $flavor="main":
    #!/usr/bin/bash
    set -eoux pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})

    # Check if image exists
    ID=$(${PODMAN} images --filter reference=localhost/"${image_name}":"${tag}" --format "'{{ '{{.ID}}' }}'")
    if [[ -z "$ID" ]]; then
        {{ just }} build "$image" "$tag" "$flavor"
    fi

    # Run Container
    ${PODMAN} run -it --rm localhost/"${image_name}":"${tag}" bash

# Test Changelogs
[group('Changelogs')]
changelogs branch="stable" handwritten="":
    #!/usr/bin/bash
    set -eou pipefail
    python3 ./.github/changelogs.py "{{ branch }}" ./output.env ./changelog.md --workdir . --handwritten "{{ handwritten }}"

# Verify Container with Cosign
[group('Utility')]
verify-container container="" registry="ghcr.io/ublue-os" key="":
    #!/usr/bin/bash
    set -eou pipefail

    # cosign v3+ is required to verify Sigstore Bundle v0.3 signatures (produced by cosign >=v3.0).
    # The CI runner may ship an older pre-installed cosign; install the pinned release when needed.
    COSIGN_VERSION="v3.1.1"
    COSIGN_MAJOR=0
    if command -v cosign >/dev/null 2>&1; then
        COSIGN_MAJOR=$(cosign version 2>/dev/null | awk '/GitVersion:/{gsub(/[^0-9.]/, "", $2); split($2, a, "."); print a[1]+0}')
    fi
    if [[ "${COSIGN_MAJOR}" -ge 3 ]]; then
        echo "cosign v${COSIGN_MAJOR} already available"
    else
        COSIGN_INSTALL_PATH="{{ justfile_directory() }}/.cosign-install"
        echo "Installing cosign ${COSIGN_VERSION} (installed major=${COSIGN_MAJOR} is pre-v3)..."
        trap 'rm -f "${COSIGN_INSTALL_PATH}"' EXIT
        curl -fsSL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" \
            -o "${COSIGN_INSTALL_PATH}"
        chmod +x "${COSIGN_INSTALL_PATH}"
        ${SUDOIF} install -m 0755 "${COSIGN_INSTALL_PATH}" /usr/local/bin/cosign
        echo "cosign installed: $(cosign version 2>/dev/null | awk '/GitVersion:/{print $2}')"
    fi

    # Verify Container using cosign (retry up to 5 times for transient registry errors)
    MAX_RETRIES=5
    RETRY_DELAY=10
    key={{ key }}

    # Keyless verification for images signed via Sigstore OIDC (e.g. projectbluefin/common)
    if [[ "${key}" == "keyless" ]]; then
        CERT_IDENTITY_REGEXP="https://github.com/projectbluefin/(common|actions)/.github/workflows/"
        CERT_OIDC_ISSUER="https://token.actions.githubusercontent.com"
        for attempt in $(seq 1 ${MAX_RETRIES}); do
            if cosign verify \
                --certificate-identity-regexp="${CERT_IDENTITY_REGEXP}" \
                --certificate-oidc-issuer="${CERT_OIDC_ISSUER}" \
                "{{ registry }}"/"{{ container }}" >/dev/null; then
                break
            fi
            if [[ "${attempt}" -eq "${MAX_RETRIES}" ]]; then
                echo "NOTICE: Keyless verification failed after ${MAX_RETRIES} attempts."
                exit 1
            fi
            echo "NOTICE: Verification attempt ${attempt}/${MAX_RETRIES} failed, retrying in ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        done
    else
        # Key-based verification
        # Keys are vendored in keys/ — update via PR with justification
        if [[ -z "${key:-}" ]]; then
            key="{{ justfile_directory() }}/keys/ublue-os-brew.pub"
        fi
        for attempt in $(seq 1 ${MAX_RETRIES}); do
            if cosign verify --key "${key}" "{{ registry }}"/"{{ container }}" >/dev/null; then
                break
            fi
            if [[ "${attempt}" -eq "${MAX_RETRIES}" ]]; then
                echo "NOTICE: Verification failed after ${MAX_RETRIES} attempts. Please ensure your public key is correct."
                exit 1
            fi
            echo "NOTICE: Verification attempt ${attempt}/${MAX_RETRIES} failed, retrying in ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        done
    fi

# Secureboot Check
[group('Utility')]
secureboot $image="bluefin" $tag="testing" $flavor="main":
    #!/usr/bin/bash
    set -eou pipefail

    # Validate
    {{ just }} validate "${image}" "${tag}" "${flavor}"

    # Image Name
    image_name=$({{ just }} image_name ${image} ${tag} ${flavor})

    # Get the vmlinuz to check
    kernel_release=$(${PODMAN} inspect "${image_name}":"${tag}" | jq -r '.[].Config.Labels["ostree.linux"]')
    TMP=$(${PODMAN} create "${image_name}":"${tag}" bash)
    ${PODMAN} cp "$TMP":/usr/lib/modules/"${kernel_release}"/vmlinuz /tmp/vmlinuz
    ${PODMAN} rm "$TMP"

    # Get the Public Certificates
    curl --retry 3 -Lo /tmp/kernel-sign.der https://github.com/ublue-os/akmods/raw/main/certs/public_key.der
    curl --retry 3 -Lo /tmp/akmods.der https://github.com/ublue-os/akmods/raw/main/certs/public_key_2.der
    openssl x509 -in /tmp/kernel-sign.der -out /tmp/kernel-sign.crt
    openssl x509 -in /tmp/akmods.der -out /tmp/akmods.crt

    # Make sure we have sbverify
    CMD="$(command -v sbverify)"
    if [[ -z "${CMD:-}" ]]; then
        temp_name="sbverify-${RANDOM}"
        ${PODMAN} run -dt \
            --entrypoint /bin/sh \
            --volume /tmp/vmlinuz:/tmp/vmlinuz:z \
            --volume /tmp/kernel-sign.crt:/tmp/kernel-sign.crt:z \
            --volume /tmp/akmods.crt:/tmp/akmods.crt:z \
            --name ${temp_name} \
            alpine:edge
        ${PODMAN} exec ${temp_name} apk add sbsigntool
        CMD="${PODMAN} exec ${temp_name} /usr/bin/sbverify"
    fi

    # Confirm that Signatures Are Good
    $CMD --list /tmp/vmlinuz
    returncode=0
    if ! $CMD --cert /tmp/kernel-sign.crt /tmp/vmlinuz || ! $CMD --cert /tmp/akmods.crt /tmp/vmlinuz; then
        echo "Secureboot Signature Failed...."
        returncode=1
    fi
    if [[ -n "${temp_name:-}" ]]; then
        ${PODMAN} rm -f "${temp_name}"
    fi
    exit "$returncode"

# Get Fedora Version of an image
[group('Utility')]
[private]
fedora_version image="bluefin" tag="testing" flavor="main" $kernel_pin="":
    #!/usr/bin/bash
    set -eou pipefail
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}
    if [[ ! -f /tmp/manifest.json ]]; then
        skopeo inspect --retry-times 3 docker://ghcr.io/ublue-os/base-main:latest > /tmp/manifest.json
    fi
    fedora_version=$(jq -r '.Labels["org.opencontainers.image.version"]' < /tmp/manifest.json | grep -oP '^[0-9]+')
    if [[ -n "${kernel_pin:-}" ]]; then
        fedora_version=$(echo "${kernel_pin}" | grep -oP 'fc\K[0-9]+')
    fi
    echo "${fedora_version}"

# Image Name
[group('Utility')]
[private]
image_name image="bluefin" tag="testing" flavor="main":
    #!/usr/bin/bash
    set -eou pipefail
    {{ just }} validate {{ image }} {{ tag }} {{ flavor }}
    if [[ "{{ flavor }}" =~ main ]]; then
        image_name={{ image }}
    else
        image_name="{{ image }}-{{ flavor }}"
    fi
    echo "${image_name}"

# Generate Tags
[group('Utility')]
generate-build-tags image="bluefin" tag="testing" flavor="main" kernel_pin="" ghcr="0" $version="" github_event="" github_number="":
    #!/usr/bin/bash
    set -eou pipefail

    if [[ {{ ghcr }} == "0" ]]; then
        rm -f /tmp/manifest.json
    fi
    FEDORA_VERSION="$({{ just }} fedora_version '{{ image }}' '{{ tag }}' '{{ flavor }}' '{{ kernel_pin }}')"
    DEFAULT_TAG=$({{ just }} generate-default-tag {{ tag }} {{ ghcr }})
    IMAGE_NAME=$({{ just }} image_name {{ image }} {{ tag }} {{ flavor }})
    # Use Build Version from Rechunk
    if [[ -z "${version:-}" ]]; then
        version="{{ tag }}-${FEDORA_VERSION}.$(date +%Y%m%d)"
    fi
    version=${version#{{ tag }}-}

    # Arrays for Tags
    BUILD_TAGS=()
    COMMIT_TAGS=()

    # Commit Tags
    github_number="{{ github_number }}"
    SHA_SHORT="$(git rev-parse --short HEAD)"
    if [[ "{{ ghcr }}" == "1" ]]; then
        COMMIT_TAGS+=(pr-${github_number:-}-{{ tag }}-${version})
        COMMIT_TAGS+=(${SHA_SHORT}-{{ tag }}-${version})
    fi

    # Convenience Tags
    BUILD_TAGS+=("{{ tag }}" "{{ tag }}-${version}" "{{ tag }}-${version:3}")

    github_event="{{ github_event }}"
    if [[ "${github_event}" == "pull_request" ]]; then
        alias_tags=("${COMMIT_TAGS[@]}")
    else
        alias_tags=("${BUILD_TAGS[@]}")
    fi

    echo "${alias_tags[*]}"

# Generate Default Tag
[group('Utility')]
generate-default-tag tag="testing" ghcr="0":
    #!/usr/bin/bash
    set -eou pipefail

    # Default Tag
    DEFAULT_TAG="{{ tag }}"

    echo "${DEFAULT_TAG}"

# Tag Images
[group('Utility')]
tag-images image_name="" default_tag="" tags="":
    #!/usr/bin/bash
    set -eou pipefail

    # Get Image, and untag
    IMAGE=$(${PODMAN} inspect localhost/{{ image_name }}:{{ default_tag }} | jq -r .[].Id)
    ${PODMAN} untag localhost/{{ image_name }}:{{ default_tag }}

    # Tag Image
    for tag in {{ tags }}; do
        ${PODMAN} tag $IMAGE {{ image_name }}:${tag}
    done

    # Re-apply the default tag so local operations (e.g. vulnerability scan) can still find it
    ${PODMAN} tag $IMAGE {{ image_name }}:{{ default_tag }}


    # Show Images
    ${PODMAN} images

# Extract Container and generate SBOM
[group('Utility')]
gen-sbom $image="bluefin" $tag="testing" $flavor="main" $syft_cmd="syft":
    #!/usr/bin/bash
    set -eoux pipefail

    image_name=$({{ just }} image_name '{{ image }}' '{{ tag }}' '{{ flavor }}')

    OUT_DIR="sbom_out/${image_name}"
    mkdir -p "${OUT_DIR}"

    SBOM="${OUT_DIR}/sbom.json"
    OCI_DIR="${OUT_DIR}/oci-dir"

    # Save image as OCI directory and scan directly — avoids the 4-8 GiB
    # filesystem extraction that the old podman-export approach required.
    # Syft reads layer tarballs sequentially so memory usage stays low.
    ${PODMAN} save --format oci-dir -o "${OCI_DIR}" "${image_name}:${tag}"

    ${syft_cmd} --source-name "${image_name}:${tag}" "oci-dir:${OCI_DIR}" --catalogers rpm --parallelism 1 -o spdx-json="${SBOM}"
    du -sh "${SBOM}"

    rm -rf "${OCI_DIR}"

# DNF CI package cache
[group('Utility')]
setup-cache $image="bluefin" $tag="testing" $ghcr="0" $github_event="0":
    #!/usr/bin/bash
    set -eou pipefail

    image_name=$({{ just }} image_name '{{ image }}')
    fedora_version=$({{ just }} fedora_version '{{ image }}' '{{ tag }}')

    ALLOW_CACHE_WRITE="false"

    # Allow cache write on trusted-branch builds (push, schedule, workflow_dispatch).
    # PR builds use the "pull_request" event and are excluded to prevent cache poisoning.
    if [[ "{{ ghcr }}" == "1" ]] && \
       [[ "${github_event}" == "push" || "${github_event}" == "workflow_dispatch" || "${github_event}" == "schedule" ]]; then
        ALLOW_CACHE_WRITE="true"
    fi

    CACHE_NAME="${image_name}-${fedora_version}"

    echo "${CACHE_NAME}" "${ALLOW_CACHE_WRITE}"

# Examples:
#   > just retag-nvidia-on-ghcr stable stable-41.20250126.3 0
#   > just retag-nvidia-on-ghcr testing testing-41.20250228.1 0
#
# working_tag: The tag of the most recent known good image (e.g., stable-41.20250126.3)
# stream:      One of testing or stable
# dry_run:     Only print the skopeo commands instead of running them
#
# First generate a PAT with package write access (https://github.com/settings/tokens)
# and set $GITHUB_USERNAME and $GITHUB_PAT environment variables

# Retag images on GHCR
[group('Admin')]
retag-nvidia-on-ghcr working_tag="" stream="" dry_run="1":
    #!/bin/bash
    set -euxo pipefail
    skopeo="echo === skopeo"
    if [[ "{{ dry_run }}" -ne 1 ]]; then
        echo "$GITHUB_PAT" | podman login -u $GITHUB_USERNAME --password-stdin ghcr.io
        skopeo="skopeo"
    fi
    for image in bluefin-nvidia; do
      $skopeo copy docker://ghcr.io/projectbluefin/${image}:{{ working_tag }} docker://ghcr.io/projectbluefin/${image}:{{ stream }}
    done
