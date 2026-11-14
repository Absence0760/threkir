#!/usr/bin/env bash
#
# Compose the captioned Play and App Store screenshots from the raw captures
# the store-screenshots workflow uploads (see README.md beside this file).
#
#   bash assets/store/gen-store-screenshots.sh --captures DIR --out DIR [--locale en]
#
# Requires: inkscape, python3, and the Manrope TTFs in packages/ui_kit/fonts.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
# shellcheck source=assets/fonts/manrope-fontconfig.sh
source "$REPO_ROOT/assets/fonts/manrope-fontconfig.sh"

python3 "$SCRIPT_DIR/render_panels.py" "$@"
