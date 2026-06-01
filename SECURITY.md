# Security Policy

## Supported Versions

| Branch | Supported |
|---|---|
| `testing` (main) | ✅ Active development |
| `stable` | ✅ Security fixes |
| `latest` | ✅ Security fixes |
| `gts` | ✅ Security fixes |
| Older releases | ❌ |

## Reporting a Vulnerability

**Please use [GitHub Private Vulnerability Reporting](https://github.com/projectbluefin/bluefin/security/advisories/new) to report security issues.**

This ensures your report is handled confidentially before public disclosure.

> Do **not** open a public GitHub issue for security vulnerabilities.

### What to include

- Description of the vulnerability and its potential impact
- Steps to reproduce or proof-of-concept
- Affected versions/streams
- Any suggested mitigations (optional)

## Response Timeline

| Stage | Target |
|---|---|
| Initial acknowledgment | 48 hours |
| Assessment complete | 7 days |
| Fix/mitigation delivered | 30 days (critical), 90 days (high/medium) |
| Public disclosure | After fix ships to stable/latest |

## Disclosure Policy

We follow coordinated disclosure. Reporters are credited in the release notes unless they request anonymity. We will not take legal action against researchers who follow this policy.

## Scope

This policy covers the `projectbluefin/bluefin` OCI image build pipeline, including:

- `Containerfile` and build scripts in `build_files/`
- GitHub Actions workflows in `.github/workflows/`
- Supply chain: base image pinning, COPR repos, binary downloads
- cosign signing and image integrity

**Out of scope:** Third-party packages bundled in the image (report upstream), Flatpaks (report to Flathub), Homebrew packages (report to upstream tap).
