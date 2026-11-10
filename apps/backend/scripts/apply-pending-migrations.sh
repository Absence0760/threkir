#!/usr/bin/env bash
#
# Apply pending Supabase migrations to a target database the way this repo's
# mixed 8-digit/14-digit version history requires.
#
# `supabase db push` (and `migration up`) refuse against this project because
# the CLI sorts same-date 8-digit (`20260601`) and 14-digit (`20260601000001`)
# versions differently than the remote ledger recorded them, so its
# history-alignment pre-flight fails even though nothing is actually missing
# (see apps/backend/CLAUDE.md § the mixed-format note). This script is the
# automated form of the documented manual workaround: for every local
# migration whose version is not yet in the remote `schema_migrations` ledger,
# apply its SQL inside a transaction and record the ledger row in the same
# transaction — in version order.
#
# Usage:
#   SUPABASE_DB_URL='postgresql://…' ./scripts/apply-pending-migrations.sh
#
# Run from apps/backend (the migrations dir is resolved relative to CWD).
# Idempotent: already-applied versions are skipped; the ledger insert is
# guarded with ON CONFLICT. On any error the current migration's transaction
# rolls back and the script stops, leaving the ledger honest.
#
# Lock waits are bounded. Each file's transaction opens with
# `set local lock_timeout` (MIGRATION_LOCK_TIMEOUT, default 5s): an ACCESS
# EXCLUSIVE queued behind a long reader would otherwise make every later query
# on that table queue behind it, for as long as the reader runs. A file that
# hits the timeout (SQLSTATE 55P03) has rolled back whole, ledger row included,
# and is retried from the top up to MIGRATION_LOCK_ATTEMPTS times (default 5),
# sleeping MIGRATION_RETRY_BASE_S (default 5) seconds, doubled each time, in
# between. Any other error, or the last attempt timing out, stops the script.
# See docs/backend/migration_locks.md § Lock timeout on apply.

set -euo pipefail

DB_URL="${SUPABASE_DB_URL:?SUPABASE_DB_URL must be set to the target database connection string}"
MIG_DIR="${MIG_DIR:-supabase/migrations}"
LOCK_TIMEOUT="${MIGRATION_LOCK_TIMEOUT:-5s}"
LOCK_ATTEMPTS="${MIGRATION_LOCK_ATTEMPTS:-5}"
RETRY_BASE_S="${MIGRATION_RETRY_BASE_S:-5}"

if ! [[ "$LOCK_TIMEOUT" =~ ^[0-9]+(ms|s|min)?$ ]]; then
  echo "::error::MIGRATION_LOCK_TIMEOUT must be a Postgres duration like 5s or 500ms, got '${LOCK_TIMEOUT}'" >&2
  exit 1
fi
if ! [[ "$LOCK_ATTEMPTS" =~ ^[1-9][0-9]*$ && "$RETRY_BASE_S" =~ ^[0-9]+$ ]]; then
  echo "::error::MIGRATION_LOCK_ATTEMPTS must be a positive integer and MIGRATION_RETRY_BASE_S a whole number of seconds" >&2
  exit 1
fi

# Authenticate via PGPASSWORD and drop whatever password is embedded in the URL.
# Supabase DB passwords routinely contain %, !, ^ (which psql's URI parser tries
# to percent-decode -> "invalid percent-encoded token"), and a hand-set
# SUPABASE_DB_URL may even keep the `[...]` placeholder brackets around the
# password. Rather than trust the URL's password, we rebuild the URL from just
# its user + host and let PGPASSWORD (SUPABASE_DB_PASSWORD) carry auth — so no
# amount of password weirdness can break the connection.
if [[ -n "${SUPABASE_DB_PASSWORD:-}" && "$DB_URL" == *"://"*"@"* ]]; then
  export PGPASSWORD="${SUPABASE_DB_PASSWORD}"
  scheme="${DB_URL%%://*}"      # postgresql
  rest="${DB_URL#*://}"         # userinfo@host:port/db[?params]
  userinfo="${rest%@*}"        # user[:password]  (before the LAST @)
  hostpart="${rest##*@}"      # host:port/db[?params]  (after the LAST @)
  user="${userinfo%%:*}"      # user  (before the first :)
  DB_URL="${scheme}://${user}@${hostpart}"
fi

if [[ ! -d "$MIG_DIR" ]]; then
  echo "::error::migrations directory not found: $MIG_DIR (run from apps/backend)" >&2
  exit 1
fi

# Version key = leading digits before the first underscore; name = the rest of
# the basename. This is exactly how the Supabase CLI parses the ledger
# (verified: prod records `20260601_001_runs_metadata_…` as version=20260601,
# name=001_runs_metadata_…).
version_of() { local b; b="$(basename "$1" .sql)"; printf '%s' "${b%%_*}"; }
name_of()    { local b; b="$(basename "$1" .sql)"; printf '%s' "${b#*_}"; }

echo "Reading applied migration versions from the target ledger…"
applied="$(psql "$DB_URL" -tAc \
  "select version from supabase_migrations.schema_migrations")"

# Build a version-sorted work list. Sorting by the parsed VERSION (not the
# filename) is what keeps the mixed 8/14-digit siblings in the correct order —
# '20270402' sorts before '20270402000001' as strings, matching the ledger,
# whereas a filename sort would invert them ('0' < '_').
mapfile -t sorted < <(
  for f in "$MIG_DIR"/*.sql; do printf '%s\t%s\n' "$(version_of "$f")" "$f"; done \
    | sort -t$'\t' -k1,1
)

applied_count=0
skipped=0
for row in "${sorted[@]}"; do
  version="${row%%$'\t'*}"
  file="${row#*$'\t'}"
  name="$(name_of "$file")"

  if grep -qxF "$version" <<<"$applied"; then
    skipped=$((skipped + 1))
    continue
  fi

  # The migration SQL + its ledger row commit atomically. ON_ERROR_STOP makes
  # psql exit non-zero on the first failure, and VERBOSITY verbose puts the
  # SQLSTATE in the error line so a lock timeout can be told from a real fault.
  attempt=1
  while :; do
    echo "Applying ${version} (${name}), attempt ${attempt}/${LOCK_ATTEMPTS}…"
    log="$(mktemp)"
    set +e
    PGOPTIONS='' psql "$DB_URL" -v ON_ERROR_STOP=1 --quiet >"$log" 2>&1 <<SQL
\set VERBOSITY verbose
begin;
set local lock_timeout = '${LOCK_TIMEOUT}';
\i ${file}
insert into supabase_migrations.schema_migrations(version, name)
  values ('${version}', '${name}')
  on conflict (version) do nothing;
commit;
SQL
    rc=$?
    set -e
    cat "$log"
    if [[ $rc -eq 0 ]]; then
      rm -f "$log"
      break
    fi
    if grep -q 'ERROR:  55P03' "$log" && [[ $attempt -lt $LOCK_ATTEMPTS ]]; then
      rm -f "$log"
      wait_s=$((RETRY_BASE_S * (1 << (attempt - 1))))
      echo "::warning::${version} waited longer than lock_timeout=${LOCK_TIMEOUT} for a lock and rolled back whole; retrying in ${wait_s}s."
      sleep "$wait_s"
      attempt=$((attempt + 1))
      continue
    fi
    if grep -q 'ERROR:  55P03' "$log"; then
      echo "::error::${version} (${name}) could not take its locks within lock_timeout=${LOCK_TIMEOUT} on any of ${LOCK_ATTEMPTS} attempts, so it was not applied and the ledger has no row for it. A long transaction is holding a lock on a table it alters: find it in pg_stat_activity / pg_locks, let it finish or end it, then re-run this deploy." >&2
    else
      echo "::error::${version} (${name}) failed (psql exit ${rc}); its transaction rolled back and the ledger has no row for it. The error is above." >&2
    fi
    rm -f "$log"
    exit 1
  done
  applied_count=$((applied_count + 1))
done

echo "Done: applied ${applied_count} migration(s), ${skipped} already present."
