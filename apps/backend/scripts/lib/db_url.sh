# Sourced, not run. Shared by apply-pending-migrations.sh and
# sync-production-state.sh, so both reach the release's database the same way.
#
# resolve_db_url: reads SUPABASE_DB_URL (required) and SUPABASE_DB_PASSWORD
# (optional), sets DB_URL, and exports PGPASSWORD when a password is given.
#
# Authenticate via PGPASSWORD and drop whatever password is embedded in the URL.
# Supabase DB passwords routinely contain %, !, ^ (which psql's URI parser tries
# to percent-decode -> "invalid percent-encoded token"), and a hand-set
# SUPABASE_DB_URL may even keep the `[...]` placeholder brackets around the
# password. Rather than trust the URL's password, we rebuild the URL from just
# its user + host and let PGPASSWORD (SUPABASE_DB_PASSWORD) carry auth — so no
# amount of password weirdness can break the connection.
#
# Never echo DB_URL: without a SUPABASE_DB_PASSWORD it still carries the URL's
# own password.
resolve_db_url() {
  DB_URL="${SUPABASE_DB_URL:?SUPABASE_DB_URL must be set to the target database connection string}"
  if [[ -n "${SUPABASE_DB_PASSWORD:-}" && "$DB_URL" == *"://"*"@"* ]]; then
    export PGPASSWORD="${SUPABASE_DB_PASSWORD}"
    local scheme rest userinfo hostpart user
    scheme="${DB_URL%%://*}"      # postgresql
    rest="${DB_URL#*://}"         # userinfo@host:port/db[?params]
    userinfo="${rest%@*}"         # user[:password]  (before the LAST @)
    hostpart="${rest##*@}"        # host:port/db[?params]  (after the LAST @)
    user="${userinfo%%:*}"        # user  (before the first :)
    DB_URL="${scheme}://${user}@${hostpart}"
  fi
}
