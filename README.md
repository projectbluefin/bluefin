# Bluefin
*Deinonychus antirrhopus*

[![Stable Images](https://github.com/projectbluefin/bluefin/actions/workflows/build-image-stable.yml/badge.svg)](https://github.com/projectbluefin/bluefin/actions/workflows/build-image-stable.yml) [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/projectbluefin/bluefin/badge)](https://scorecard.dev/viewer/?uri=github.com/projectbluefin/bluefin) [![LFX Active Contributors](https://insights.linuxfoundation.org/api/badge/active-contributors?project=ublue-os-bluefin&repos=https://github.com/ublue-os/bluefin)](https://insights.linuxfoundation.org/project/ublue-os-bluefin/repository/ublue-os-bluefin/security) [![Installs](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/ublue-os/countme/main/badge-endpoints/bluefin.json&label=Installs)](https://github.com/projectbluefin/bluefin) [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/projectbluefin/bluefin)

**Bluefin** is a cloud-native desktop operating system built on Fedora Linux. For end users it provides a system as reliable as a Chromebook with near-zero maintenance. For developers, it offers a cloud-native workflow with integrated container tools, declarative system management, and seamless CI/CD integration.

🌐 **[Try Bluefin](https://projectbluefin.io/#scene-picker)**

![image](https://github.com/user-attachments/assets/e7d2a0af-b011-459a-8ab7-c26d3ba50ae5)

## Latest Release

<a href="https://docs.projectbluefin.io/changelogs/">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://docs.projectbluefin.io/img/cards/bluefin-dark.png">
    <img src="https://docs.projectbluefin.io/img/cards/bluefin-light.png" alt="Bluefin latest release" width="800">
  </picture>
</a>

## Images

Full catalog at [docs.projectbluefin.io/images →](https://docs.projectbluefin.io/images/)

### Bluefin

Primary Bluefin desktop image for most systems.

```bash
# Stable — recommended, weekly promotion
sudo bootc switch ghcr.io/projectbluefin/bluefin:stable --enforce-container-sigpolicy
# Stable — NVIDIA
sudo bootc switch ghcr.io/projectbluefin/bluefin-nvidia:stable --enforce-container-sigpolicy

# Testing — tracks Fedora latest, daily rebuilds
sudo bootc switch ghcr.io/projectbluefin/bluefin:testing --enforce-container-sigpolicy
# Testing — NVIDIA
sudo bootc switch ghcr.io/projectbluefin/bluefin-nvidia:testing --enforce-container-sigpolicy
```

## Getting Started

Visit **[projectbluefin.io](https://projectbluefin.io/#scene-picker)** to download and install Bluefin, or check the **[Documentation](https://docs.projectbluefin.io/)** for detailed guides.

### Developer Setup

If you want to contribute to Bluefin, start with [CONTRIBUTING.md](CONTRIBUTING.md) for branch workflow, validation steps, and commit conventions.

For local image build prerequisites and commands, see [docs/build.md](docs/build.md).

### Secure Boot

Secure Boot is supported by default. After the first installation you will be prompted to enroll the secure boot key in the BIOS. Enter the password `universalblue` when prompted.

To enroll manually:

```bash
ujust enroll-secure-boot-key
```

The public key is available in the [akmods repository](https://github.com/ublue-os/akmods/raw/main/certs/public_key.der). To enroll prior to installation or rebase:

```bash
sudo mokutil --timeout -1
sudo mokutil --import public_key.der
```

## Community

- 📰 **[Blog](https://blog.projectbluefin.io/)** — announcements and release posts
- 💬 **[Discussions](https://community.projectbluefin.io/)** — community forum
- 📋 **[Project Board](https://todo.projectbluefin.io/)** — what we're working on
- 📖 **[Documentation](https://docs.projectbluefin.io/)** — user guides and reference

## Contributing

See the **[Contributing Guide](https://docs.projectbluefin.io/contributing/)** for how to get involved. All participants are expected to follow the [Universal Blue Community Guidelines](https://docs.projectbluefin.io/contributing#community-guidelines).

Report security vulnerabilities via [SECURITY.md](SECURITY.md).

## License

Apache License 2.0 — see [LICENSE](LICENSE).

Bluefin incorporates [Fedora Linux](https://fedoraproject.org/), [GNOME](https://www.gnome.org/), [Universal Blue](https://universal-blue.org/), and various CNCF projects, each under their respective licenses.
