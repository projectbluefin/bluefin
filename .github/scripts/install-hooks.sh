#!/usr/bin/env bash
# Install git hooks for the bluefin repo.
# Run this once after cloning: bash .github/scripts/install-hooks.sh

set -euo pipefail

HOOKS_DIR="$(git rev-parse --git-dir)/hooks"

cat > "$HOOKS_DIR/pre-push" << 'EOF'
#!/usr/bin/env bash
# Block accidental pushes to origin (ublue-os/bluefin).
# The correct remote for projectbluefin contributors is: git push projectbluefin <branch>
remote="$1"
if [[ "$remote" == "origin" ]]; then
  echo "ERROR: Pushing to 'origin' (ublue-os/bluefin) is not allowed." >&2
  echo "Use: git push projectbluefin <branch>" >&2
  echo "See docs/build.md for remote setup instructions." >&2
  exit 1
fi
EOF

chmod +x "$HOOKS_DIR/pre-push"
echo "Installed pre-push hook: blocks accidental pushes to origin (ublue-os/bluefin)."
