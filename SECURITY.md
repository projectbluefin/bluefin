# Security policy

## Reporting

Report security vulnerabilities through [GitHub Private Vulnerability Reporting](https://github.com/projectbluefin/bluefin/security/advisories/new). Do not disclose an unpatched vulnerability in a public issue.

Include:

- vulnerability description and impact
- reproduction steps or proof of concept
- affected image, stream, or release
- suggested mitigation, if available

## Response

The maintainers acknowledge reports within 48 hours and aim to assess them
within 7 days. Fix and disclosure timing depends on severity and coordination
with affected upstreams.

## Scope

This policy covers image assembly, build scripts, workflow automation, package
sources, signing, and image-integrity verification in this repository.

Report vulnerabilities in third-party packages, Flatpaks, or Homebrew inputs to
their respective upstream projects unless the issue is introduced by this
repository's integration.

## Safe handling

Do not commit credentials, private keys, tokens, or exploit payloads. Preserve
package-source isolation, signature verification, and release gates when
investigating or fixing a security issue.
