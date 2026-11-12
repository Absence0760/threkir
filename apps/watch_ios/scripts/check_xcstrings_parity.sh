#!/usr/bin/env bash
# Parity check for the watchOS String Catalogs: `Localizable.xcstrings` (the UI)
# and `InfoPlist.xcstrings` (the consent prompts), held to Info.plist, the
# project's knownRegions and the WatchApp target's Resources phase. Runs
# WITHOUT Xcode — a bare python3 — so it runs on a Linux runner.
#
# The claims live in scripts/xcstrings_parity.py, shared with the iPhone's
# apps/mobile_ios/scripts/check_xcstrings_parity.sh; this wrapper only names the
# wrist's files. The engine's docstring is the list of what is checked and why.
#
# CI: the `watch-ios-locale-parity` job in .github/workflows/ci.yml.
# Referenced from apps/watch_ios/CLAUDE.md.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec python3 "$DIR/../../scripts/xcstrings_parity.py" \
  --root "$DIR" \
  --plist WatchApp/Info.plist \
  --pbxproj WatchApp.xcodeproj/project.pbxproj \
  --target WatchApp \
  --ui-catalog WatchApp/Localizable.xcstrings \
  --plist-catalog WatchApp/InfoPlist.xcstrings \
  --device wrist
