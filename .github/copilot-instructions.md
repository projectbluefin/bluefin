# Bluefin — Agent & Copilot Instructions

See [AGENTS.md](../AGENTS.md) for the full agent guide.

## Critical rules (apply immediately, no exceptions)

- **Issues belong in [`projectbluefin/bluefin`](https://github.com/projectbluefin/bluefin/issues) only.**
  Never open, comment on, or touch issues in `ublue-os/bluefin` or any `ublue-os` repo.
- All PRs target the `testing` branch — never `main`.
- Run `just check && pre-commit run --all-files` before every commit.
