#!/usr/bin/env bash
#
# Run the store capture suite against a booted device and a local Supabase
# stack that has assets/store/demo/store_demo_seed.sql loaded. Called by
# .github/workflows/store-screenshots.yml; runnable by hand the same way.
#
#   SUPABASE_ANON_KEY=<local stack anon key> \
#     bash assets/store/capture.sh <device-id> <output dir>
#
# Optional: STORE_APP=mobile_ios to capture the App Store set on a booted iOS
# simulator (default mobile_android, the Play set on an emulator);
# MAPTILER_KEY (without it the map falls back to OSM tiles); SUPABASE_URL
# (default: the device's route to the host stack, 10.0.2.2 from the Android
# emulator, localhost from the iOS simulator, as apps/mobile_ios/local_testing.md runs it).
#
# It writes the captures, bounds.json and numbers.json to the output dir
# (assets/store/README.md), and fails if any of them is missing.
#
set -euo pipefail

DEVICE="${1:?usage: capture.sh <device-id> <output dir>}"
OUT="${2:?usage: capture.sh <device-id> <output dir>}"
: "${SUPABASE_ANON_KEY:?set SUPABASE_ANON_KEY to the local stack anon key}"
STORE_APP="${STORE_APP:-mobile_android}"
case "$STORE_APP" in
  # An iOS simulator cannot run a profile build, so iOS captures in debug.
  # The captures are the screen's own layer either way (store_capture_kit.dart).
  mobile_android) HOST=10.0.2.2; MODE=--profile ;;
  mobile_ios) HOST=localhost; MODE=--debug ;;
  *) echo "error: STORE_APP is mobile_android or mobile_ios, not $STORE_APP" >&2; exit 1 ;;
esac
SUPABASE_URL="${SUPABASE_URL:-http://$HOST:24321}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

cd "$REPO_ROOT/apps/$STORE_APP"
# WEB_BASE_URL points at a loopback port where nothing listens, so the coach's
# capability read fails closed instead of reaching production. The account is
# the local demo one from store_demo_seed.sql, signed in by the app's own
# loopback-only dev auto-login.
STORE_SCREENSHOTS_DIR="$OUT" flutter drive "$MODE" -d "$DEVICE" \
  --driver integration_test/store/store_screenshots_driver.dart \
  --target integration_test/store/store_screenshots_capture.dart \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=MAPTILER_KEY="${MAPTILER_KEY:-}" \
  --dart-define=WEB_BASE_URL="http://$HOST:7777" \
  --dart-define=DEV_USER_EMAIL=store-demo@threkir.test \
  --dart-define=DEV_USER_PASSWORD=storedemo

for name in run-zones.png run-splits.png run-pacing.png progress.png plan.png coach.png bounds.json numbers.json; do
  [ -s "$OUT/$name" ] || { echo "error: the capture wrote no $name" >&2; exit 1; }
done
echo "captures in $OUT"
