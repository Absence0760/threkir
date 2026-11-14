#!/usr/bin/env bash
#
# seed-demo.sh — load the opt-in demo dataset into a LOCAL Supabase stack.
#
# Applies apps/backend/supabase/seed_demo.sql on top of seed.sql: more
# runners, 34 Virginia parks with ~170 park courses and their boards, 36 races,
# 58 routes, six months of the seed runner's activities, a busy feed, clubs,
# events, challenges, messages, a past training plan, gym, food and body
# metrics. See decisions § 2521 for why this is not part of seed.sql.
#
# Usage:
#   bin/seed-demo.sh                       # the default local stack (port 24322)
#   bin/seed-demo.sh --db-url <url>        # another local stack, e.g. a lane's
#
# Run it after `supabase db reset` (or a fresh `supabase start`). It is
# idempotent: a second run inserts nothing. To move the dates forward, reset
# and run it again.
#
# Local only, fail-closed: the URL must be a postgres:// or postgresql:// URI
# whose one host is localhost, 127.0.0.1 or ::1, with no host override in
# its query string. Every PG* environment variable is cleared first so none can
# redirect the connection. The SQL also refuses any database seed.sql did not
# build.

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

DB_URL="postgresql://postgres:postgres@127.0.0.1:24322/postgres"
SQL_FILE="${REPO_ROOT}/apps/backend/supabase/seed_demo.sql"

usage() {
	sed -n '2,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
}

while (($#)); do
	case "$1" in
	--db-url)
		[[ $# -ge 2 ]] || fatal "--db-url needs a value"
		DB_URL="$2"
		shift 2
		;;
	--db-url=*)
		DB_URL="${1#--db-url=}"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		fatal "unknown argument: $1 (see --help)"
		;;
	esac
done

# Echo the host of a postgres URI, or nothing when it has none we accept.
url_host() {
	local url="$1" rest authority host
	case "$url" in
	postgres://* | postgresql://*) ;;
	*) return 0 ;;
	esac
	rest="${url#*://}"
	authority="${rest%%[/?]*}"
	host="${authority##*@}"
	# libpq tries every host of a comma-separated list in turn, so a list
	# could reach a remote host after a local one: accept exactly one.
	if [[ "$host" == *,* ]]; then
		printf '%s\n' "$host"
		return 0
	fi
	if [[ "$host" == \[* ]]; then
		host="${host%%]*}"
		host="${host#[}"
	else
		host="${host%%:*}"
	fi
	printf '%s\n' "$host"
}

step "Checking the target is a local stack"
host="$(url_host "$DB_URL")"
case "${host,,}" in
localhost | 127.0.0.1 | ::1) ;;
"") fatal "refusing: --db-url must be a postgres:// or postgresql:// URI with an explicit host" ;;
*) fatal "refusing: host '${host}' is not localhost, 127.0.0.1 or ::1 — demo data is for local stacks only" ;;
esac
query="${DB_URL#*\?}"
if [[ "$query" != "$DB_URL" && "${query,,}" =~ (^|&)(host|hostaddr|service)= ]]; then
	fatal "refusing: the URL's query string overrides the host"
fi
for var in $(compgen -e | grep '^PG' || true); do
	unset "$var"
done
ok "host ${host}"

need_cmd psql
[[ -f "$SQL_FILE" ]] || fatal "missing $SQL_FILE"

step "Applying seed_demo.sql"
psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -f "$SQL_FILE"
ok "applied"

step "Demo rows now in the database"
psql "$DB_URL" -X -q -At -F ' ' <<'SQL'
select rpad(t, 26), n from (values
  ('parks', (select count(*) from parks)),
  ('park courses', (select count(*) from park_courses)),
  ('park course efforts', (select count(*) from global_segment_efforts e join park_courses c on c.global_segment_id = e.global_segment_id)),
  ('race listings', (select count(*) from race_listings)),
  ('runner routes', (select count(*) from routes where user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890')),
  ('runner activities', (select count(*) from runs where user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890')),
  ('runs, all users', (select count(*) from runs)),
  ('runner notifications', (select count(*) from notifications where user_id = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'))
) v(t, n);
SQL
dim "Sign in as runner@test.com / testtest (every demo friend uses the same password)."
