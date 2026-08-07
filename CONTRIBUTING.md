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

Do the work in an isolated worktree cut from `testing`:

```bash
bash .github/scripts/worktree.sh new <branch>
```

Open pull requests against `testing`, never against `main`. Check for an
existing pull request first, keep one logical change per pull request, use
Conventional Commits, squash merge, and report exactly what you tested.
