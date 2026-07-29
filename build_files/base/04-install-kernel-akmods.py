#!/usr/bin/env python3
"""Install kernel and akmods artifacts for Bluefin image builds."""

from __future__ import annotations

import asyncio
import glob
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class PullSpec:
    name: str
    image: str
    target_dir: Path


def run(cmd: list[str], env: dict[str, str] | None = None, capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=True, env=env, capture_output=capture_output, text=True)


def run_allow_failure(cmd: list[str]) -> None:
    subprocess.run(cmd, check=False)


def fedora_version() -> str:
    result = run(["rpm", "-E", "%fedora"], capture_output=True)
    return result.stdout.strip()


async def pull_spec(spec: PullSpec, retries: int, delay_seconds: int) -> None:
    cmd = [
        "skopeo",
        "copy",
        "--retry-times",
        "3",
        f"docker://{spec.image}",
        f"dir:{spec.target_dir}",
    ]
    spec.target_dir.mkdir(parents=True, exist_ok=True)

    for attempt in range(1, retries + 1):
        proc = await asyncio.create_subprocess_exec(*cmd)
        code = await proc.wait()
        if code == 0:
            return
        if attempt < retries:
            await asyncio.sleep(delay_seconds)

    raise RuntimeError(f"Failed to pull {spec.name} image after {retries} attempts")


async def pull_all(specs: list[PullSpec], retries: int, delay_seconds: int) -> None:
    await asyncio.gather(*(pull_spec(spec, retries, delay_seconds) for spec in specs))


def resolve_glob(pattern: str) -> list[str]:
    matches = sorted(glob.glob(pattern))
    if not matches:
        raise FileNotFoundError(f"No matches for required pattern: {pattern}")
    return matches


def resolve_pattern_or_literal(value: str) -> list[str]:
    if any(char in value for char in "*?[]"):
        return resolve_glob(value)
    return [value]


def extract_payload(image_dir: Path, destination_dir: Path) -> None:
    manifest_path = image_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing manifest: {manifest_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    layers = manifest.get("layers")
    if not isinstance(layers, list) or not layers:
        raise ValueError(f"Invalid manifest layers in {manifest_path}")

    digest = layers[0].get("digest")
    if not isinstance(digest, str) or ":" not in digest:
        raise ValueError(f"Invalid digest in {manifest_path}: {digest!r}")

    tarball_name = digest.split(":", 1)[1]
    tarball_path = image_dir / tarball_name
    if not tarball_path.exists():
        raise FileNotFoundError(f"Missing payload tarball: {tarball_path}")

    run(["tar", "-xvzf", str(tarball_path), "-C", "/tmp"])

    rpms_dir = Path("/tmp/rpms")
    if rpms_dir.exists():
        destination_dir.mkdir(parents=True, exist_ok=True)
        for entry in rpms_dir.iterdir():
            shutil.move(str(entry), destination_dir / entry.name)


def write_rpmfusion_repos() -> tuple[Path, Path]:
    free_repo = Path("/etc/yum.repos.d/rpmfusion-free-build.repo")
    nonfree_repo = Path("/etc/yum.repos.d/rpmfusion-nonfree-build.repo")

    free_repo.write_text(
        """[rpmfusion-free]
name=RPM Fusion for Fedora $releasever - Free
baseurl=https://download1.rpmfusion.org/free/fedora/releases/$releasever/Everything/$basearch/os/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1

[rpmfusion-free-updates]
name=RPM Fusion for Fedora $releasever - Free - Updates
baseurl=https://download1.rpmfusion.org/free/fedora/updates/$releasever/$basearch/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1
""",
        encoding="utf-8",
    )
    nonfree_repo.write_text(
        """[rpmfusion-nonfree]
name=RPM Fusion for Fedora $releasever - Nonfree
baseurl=https://download1.rpmfusion.org/nonfree/fedora/releases/$releasever/Everything/$basearch/os/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1

[rpmfusion-nonfree-updates]
name=RPM Fusion for Fedora $releasever - Nonfree - Updates
baseurl=https://download1.rpmfusion.org/nonfree/fedora/updates/$releasever/$basearch/
enabled=1
metadata_expire=3d
gpgcheck=0
skip_if_unavailable=1
""",
        encoding="utf-8",
    )
    return free_repo, nonfree_repo


def install_v4l2loopback(beta: bool) -> None:
    rpms = resolve_glob("/tmp/akmods/kmods/*v4l2loopback*.rpm")
    cmd = ["dnf5", "-y", "install", "v4l2loopback", *rpms]
    if beta:
        run_allow_failure(cmd)
    else:
        run(cmd)


def configure_nvidia(beta: bool, base_image_name: str, kernel: str) -> None:
    extract_payload(Path("/tmp/akmods-rpms"), Path("/tmp/akmods-rpms"))

    if not beta:
        run(["dnf5", "config-manager", "setopt", "excludepkgs=golang-github-nvidia-container-toolkit"])
    else:
        mesa_info = run(["rpm", "-qi", "mesa-dri-drivers"], capture_output=True).stdout
        if "negativo17" not in mesa_info:
            run(["dnf5", "-y", "swap", "--repo=updates-testing", "mesa-dri-drivers", "mesa-dri-drivers"])

    run(["rpm", "--import", "https://download.copr.fedorainfracloud.org/results/ublue-os/staging/pubkey.gpg"])
    env = os.environ.copy()
    env["IMAGE_NAME"] = base_image_name
    env["AKMODNV_PATH"] = "/tmp/akmods-rpms"
    env["MULTILIB"] = "0"
    run(["/tmp/akmods-rpms/ublue-os/nvidia-install.sh"], env=env)

    for path in glob.glob("/usr/share/vulkan/icd.d/nouveau_icd.*.json"):
        Path(path).unlink(missing_ok=True)
    run(["ln", "-sf", "libnvidia-ml.so.1", "/usr/lib64/libnvidia-ml.so"])

    Path("/usr/lib/bootc/kargs.d/00-nvidia.toml").write_text(
        'kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]\n',
        encoding="utf-8",
    )

    repo_url = "https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo"
    repo_contents = run(["curl", "-fsSL", repo_url], capture_output=True).stdout
    repo_file = Path("/etc/yum.repos.d/nvidia-container-toolkit.repo")
    repo_file.write_text(repo_contents, encoding="utf-8")
    run(["dnf5", "-y", "install", "nvidia-container-toolkit-base"])
    run(["nvidia-ctk", "config", "--set", "nvidia-container-cli.no-cgroups", "--in-place"])
    repo_file.unlink(missing_ok=True)


def configure_zfs(kernel: str) -> None:
    extract_payload(Path("/tmp/akmods-zfs"), Path("/tmp/akmods-zfs"))

    zfs_inputs = [
        f"/tmp/akmods-zfs/kmods/zfs/kmod-zfs-{kernel}-*.rpm",
        "/tmp/akmods-zfs/kmods/zfs/libnvpair[0-9]-*.rpm",
        "/tmp/akmods-zfs/kmods/zfs/libuutil[0-9]-*.rpm",
        "/tmp/akmods-zfs/kmods/zfs/libzfs[0-9]-*.rpm",
        "/tmp/akmods-zfs/kmods/zfs/libzpool[0-9]-*.rpm",
        "/tmp/akmods-zfs/kmods/zfs/python3-pyzfs-*.rpm",
        "/tmp/akmods-zfs/kmods/zfs/zfs-*.rpm",
        "pv",
    ]
    zfs_rpms: list[str] = []
    for item in zfs_inputs:
        zfs_rpms.extend(resolve_pattern_or_literal(item))

    run(["dnf5", "-y", "install", *zfs_rpms])
    run(["depmod", "-a", "-v", kernel])
    Path("/usr/lib/modules-load.d/zfs.conf").write_text("zfs\n", encoding="utf-8")


def install_kernel(kernel: str) -> None:
    kernel_rpms = [
        *resolve_glob("/tmp/kernel-rpms/kernel-[0-9]*.rpm"),
        *resolve_glob("/tmp/kernel-rpms/kernel-core-*.rpm"),
        *resolve_glob("/tmp/kernel-rpms/kernel-modules-*.rpm"),
    ]
    run(["dnf5", "-y", "install", *kernel_rpms])
    run(["dnf5", "-y", "install", *resolve_glob("/tmp/kernel-rpms/kernel-devel-*.rpm")])


def generate_initramfs(kernel: str) -> None:
    print(f"Generating initramfs for {kernel}")
    os.environ["DRACUT_NO_XATTR"] = "1"
    run(
        [
            "dracut",
            "--no-hostonly",
            "--kver",
            kernel,
            "--reproducible",
            "--tmpdir",
            "/boot",
            "-v",
            "--add",
            "ostree dmsquash-live dmsquash-live-autooverlay",
            "-f",
            f"/lib/modules/{kernel}/initramfs.img",
        ]
    )
    initramfs = Path(f"/lib/modules/{kernel}/initramfs.img")
    initramfs.chmod(0o600)
    Path(f"/lib/modules/{kernel}/.bluefin-initramfs-done").touch()


def main() -> int:
    script_name = Path(__file__).name
    print(f"::group:: ==={script_name}===")

    ublue_image_tag = os.environ["UBLUE_IMAGE_TAG"]
    akmods_flavor = os.environ["AKMODS_FLAVOR"]
    image_name = os.environ["IMAGE_NAME"]
    base_image_name = os.environ["BASE_IMAGE_NAME"]
    kernel = os.environ["KERNEL"]

    beta = ublue_image_tag == "beta"
    if beta:
        run(["dnf5", "config-manager", "setopt", "updates-testing.enabled=1"])

    for package in ["kernel", "kernel-core", "kernel-modules", "kernel-modules-core", "kernel-modules-extra"]:
        run(["rpm", "--erase", package, "--nodeps"])

    fedora = fedora_version()
    tag = f"{akmods_flavor}-{fedora}-{kernel}"
    pull_specs = [PullSpec("akmods", f"ghcr.io/ublue-os/akmods:{tag}", Path("/tmp/akmods"))]
    if "nvidia" in image_name:
        pull_specs.append(PullSpec("nvidia", f"ghcr.io/ublue-os/akmods-nvidia-open:{tag}", Path("/tmp/akmods-rpms")))
    if "coreos" in akmods_flavor:
        pull_specs.append(PullSpec("zfs", f"ghcr.io/ublue-os/akmods-zfs:{tag}", Path("/tmp/akmods-zfs")))

    retries = int(os.environ.get("AKMODS_PULL_RETRIES", "2"))
    delay_seconds = int(os.environ.get("AKMODS_PULL_RETRY_DELAY_SECONDS", "2"))
    asyncio.run(pull_all(pull_specs, retries=retries, delay_seconds=delay_seconds))
    print("All image pulls completed successfully")

    extract_payload(Path("/tmp/akmods"), Path("/tmp/akmods"))
    install_kernel(kernel)
    run(
        [
            "dnf5",
            "versionlock",
            "add",
            "kernel",
            "kernel-devel",
            "kernel-devel-matched",
            "kernel-core",
            "kernel-modules",
            "kernel-modules-core",
            "kernel-modules-extra",
        ]
    )
    run(["dnf5", "copr", "enable", "-y", "ublue-os/akmods"])

    cert_dir = Path("/etc/pki/akmods/certs")
    cert_dir.mkdir(parents=True, exist_ok=True)
    cert_path = cert_dir / "akmods-ublue.der"
    run(
        [
            "ghcurl",
            "https://github.com/ublue-os/akmods/raw/refs/heads/main/certs/public_key.der",
            "--retry",
            "3",
            "-Lo",
            str(cert_path),
        ]
    )
    run(["grep", "-F", "-e", "Universal Blue", str(cert_path)])

    rpmfusion_free_repo, rpmfusion_nonfree_repo = write_rpmfusion_repos()
    install_v4l2loopback(beta=beta)
    rpmfusion_free_repo.unlink(missing_ok=True)
    rpmfusion_nonfree_repo.unlink(missing_ok=True)

    if "nvidia" in image_name:
        configure_nvidia(beta=beta, base_image_name=base_image_name, kernel=kernel)
    if "coreos" in akmods_flavor:
        configure_zfs(kernel)

    run(["dnf5", "copr", "disable", "-y", "ublue-os/akmods"])
    generate_initramfs(kernel)

    print("::endgroup::")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
