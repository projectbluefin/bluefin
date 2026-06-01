# Bluefin — Agent & Copilot Instructions

See [AGENTS.md](../AGENTS.md) for the full agent guide.

## Critical rules (apply immediately, no exceptions)

- **Only interact with repos inside the [`projectbluefin`](https://github.com/projectbluefin) org.**
  Never open, comment on, or touch issues, PRs, or code in any repo outside `projectbluefin` — including `ublue-os`, `coreos`, or any other org.
- All PRs target the `testing` branch — never `main`.
- Run `just check && pre-commit run --all-files` before every commit.
