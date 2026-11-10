#!/usr/bin/env bash
#
# Sync production state (issue #1349, decisions § 2429): the release step that
# brings committed, reviewed state into the database after the migrations,
# so nobody runs SQL in production by hand. Its stages live in
# scripts/prod_sync/run.mjs; the park catalogue is the first.
#
# Usage (from apps/backend, like apply-pending-migrations.sh):
#   SUPABASE_DB_URL='postgresql://…' SUPABASE_DB_PASSWORD='…' \
#     ./scripts/sync-production-state.sh [--dry-run]
#
# Reaches the database exactly as apply-pending-migrations.sh does
# (lib/db_url.sh): the URL without its password, PGPASSWORD for auth. The URL
# goes to the runner in SYNC_DB_URL and is never printed.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/db_url.sh
source "${here}/lib/db_url.sh"
resolve_db_url

SYNC_DB_URL="$DB_URL" exec node "${here}/../../../scripts/prod_sync/run.mjs" "$@"
