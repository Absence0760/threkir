#!/usr/bin/env bash
# Parity check for the iPhone's consent-prompt String Catalog,
# `ios/Runner/InfoPlist.xcstrings`, held to Info.plist (every
# NS*UsageDescription key, both directions, English identical), the project's
# knownRegions, and the Runner target's Resources phase. Runs WITHOUT Xcode — a
# bare python3 — so it runs on a Linux runner.
#
# The phone has no UI catalog: its UI strings are the ARB catalogues under
# lib/l10n, which architecture_guards_test.dart holds to CFBundleLocalizations.
# The consent prompts are the one thing iOS reads out of the bundle instead, so
# until #964 all eleven of them rendered English in all seven locales.
#
# The claims live in scripts/xcstrings_parity.py, shared with the wrist's
# apps/watch_ios/scripts/check_xcstrings_parity.sh; this wrapper only names the
# phone's files. The engine's docstring is the list of what is checked and why.
#
# CI: the `ios-native-declarations` job in .github/workflows/ci.yml.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 "$DIR/../../scripts/xcstrings_parity.py" \
  --root "$DIR/ios" \
  --plist Runner/Info.plist \
  --pbxproj Runner.xcodeproj/project.pbxproj \
  --target Runner \
  --plist-catalog Runner/InfoPlist.xcstrings \
  --device iPhone
