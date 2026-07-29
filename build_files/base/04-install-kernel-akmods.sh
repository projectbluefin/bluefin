#!/usr/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "${SCRIPT_DIR}/04-install-kernel-akmods.py"
