#!/usr/bin/env bash
#
# Run the store capture suite against a booted device and a local Supabase
# stack that has assets/store/demo/store_demo_seed.sql loaded. Called by
# .github/workflows/store-screenshots.yml; runnable by hand the same way.
#
#   SUPABASE_ANON_KEY=<local stack anon key> \
#     bash assets/store/capture.sh <device-id> <output dir>
#
# Optional: MAPTILER_KEY (without it the map falls back to OSM tiles),
# SUPABASE_URL (default: the Android emulator's route to the host stack).
#
set -euo pipefail

DEVICE="${1:?usage: capture.sh <device-id> <output dir>}"
OUT="${2:?usage: capture.sh <device-id> <output dir>}"
: "${SUPABASE_ANON_KEY:?set SUPABASE_ANON_KEY to the local stack anon key}"
SUPABASE_URL="${SUPABASE_URL:-http://10.0.2.2:24321}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

cd "$REPO_ROOT/apps/mobile_android"
# WEB_BASE_URL points at a loopback port where nothing listens, so the coach's
# capability read fails closed instead of reaching production. The account is
# the local demo one from store_demo_seed.sql, signed in by the app's own
# loopback-only dev auto-login.
STORE_SCREENSHOTS_DIR="$OUT" flutter drive --profile -d "$DEVICE" \
  --driver integration_test/store/store_screenshots_driver.dart \
  --target integration_test/store/store_screenshots_capture.dart \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=MAPTILER_KEY="${MAPTILER_KEY:-}" \
  --dart-define=WEB_BASE_URL=http://10.0.2.2:7777 \
  --dart-define=DEV_USER_EMAIL=store-demo@threkir.test \
  --dart-define=DEV_USER_PASSWORD=storedemo

for name in today record train coach; do
  [ -s "$OUT/$name.png" ] || { echo "error: the capture wrote no $name.png" >&2; exit 1; }
done
echo "captures in $OUT"
