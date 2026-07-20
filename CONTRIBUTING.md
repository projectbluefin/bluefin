# Contributing

This file is the contributor entry point. The canonical procedures live in
[`docs/contributing.md`](docs/contributing.md).

Start with [`AGENTS.md`](AGENTS.md), then load the matching skill from
[`docs/skills/index.md`](docs/skills/index.md).

Default checks:

```bash
just check
pre-commit run --all-files
```

For shell-library or setup-hook changes:

```bash
bats tests/unit/
```

Use the repository's configured development branch, keep changes focused, use
Conventional Commits, and report exactly what you tested.
