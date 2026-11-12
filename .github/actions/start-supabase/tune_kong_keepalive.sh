#!/usr/bin/env bash
#
# Make kong the side that closes an idle upstream connection.
#
# CI run 35655765654 (e2e shard 11/14, PR #974, which touched no web code)
# failed roadbook.spec.ts twice: the first attempt and its retry both found
# the page saying "Add course markers to build a roadbook" for a route seeded
# with two. The retry's trace has the cause: `POST /rest/v1/rpc/
# route_markers_for_viewer` answered 502 from kong ("Via: kong/2.8.1",
# "X-Kong-Upstream-Latency: 0", a 75-byte body), between a GET of the same
# route and a GET of user_settings that both answered 200.
#
# That is a keep-alive race, and the stack ships with it. Kong 2.8.1 keeps an
# idle upstream connection for `upstream_keepalive_idle_timeout = 60` seconds.
# PostgREST's server sweeps idle connections shut after 30 to 60 seconds, a
# batch at a time. A request kong writes onto a connection in the instant
# PostgREST closes it is reset ("recv() failed (104: Connection reset by
# peer) while reading response header from upstream"). Kong retries that
# transparently for a GET or HEAD, and cannot for a POST, which is not
# idempotent, so the POST alone surfaces as a 502. A workstation's local
# kong log over a week of ordinary use held 26 of those upstream errors and
# 25 client-facing 502s, and every one of the 25 was a POST; one was
# `POST /rest/v1/rpc/get_my_profile`, 502, 75 bytes, reset in the same
# second as a GET and a HEAD that kong retried to 200.
#
# The fix is the standard one for a proxy in front of a keep-alive server:
# the proxy's idle timeout goes BELOW every upstream's, so no upstream ever
# closes a connection kong still holds. Measured from inside the kong
# container on 2026-09-21, the seconds each upstream keeps an idle
# connection open:
#
#   realtime   5.0  (cowboy's request_timeout: the floor)
#   rest      59.9  (swept between 30 and 60)
#   storage   62.0
#   pg_meta   73.0
#   auth, analytics  over 75
#
# The edge runtime was not running on that stack and is unmeasured. At the
# default 60 s, kong kept an idle PostgREST connection past 45 s. At 2 s it
# closed it between 8 and 14 s (the probe samples, not the timeout), so kong
# closes first.
#
# It is deliberately not a retry. Retrying a POST in the app would repeat
# requests that may be mutations, and adding `non_idempotent` to kong's
# proxy_next_upstream would do the same one layer down. Either would hide a
# race that this setting removes. The Supabase CLI exposes no kong setting,
# so the value goes in by hot reload, the same `kong reload` the image
# ships, with the CLI's own nginx template.
set -uo pipefail

IDLE_S=2
TEMPLATE=/home/kong/custom_nginx.template
KONG_ENV=/usr/local/kong/.kong_env

mapfile -t kongs < <(docker ps --filter 'name=^supabase_kong_' --format '{{.Names}}')
if [ "${#kongs[@]}" -ne 1 ]; then
  echo "::error::Expected exactly one running supabase_kong_* container, found ${#kongs[@]} (${kongs[*]:-none}). kong's upstream keep-alive was NOT shortened, so a POST through it can 502 on a reused connection."
  exit 1
fi
kong=${kongs[0]}

if ! docker exec "$kong" test -f "$TEMPLATE"; then
  echo "::error::$kong has no $TEMPLATE. That is the nginx template the pinned Supabase CLI starts kong with (--nginx-conf in internal/start/start.go), and a reload without it would drop the CLI's custom config. A CLI bump moved it: point TEMPLATE in .github/actions/start-supabase/tune_kong_keepalive.sh at the new path."
  exit 1
fi

if ! out=$(docker exec -e "KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT=$IDLE_S" "$kong" kong reload --nginx-conf "$TEMPLATE" 2>&1); then
  printf '%s\n' "$out"
  echo "::error::kong reload failed in $kong (output above), so its upstream keep-alive is still the default 60s and a POST through it can 502 on a reused connection."
  exit 1
fi

if ! docker exec "$kong" grep -qx "upstream_keepalive_idle_timeout = $IDLE_S" "$KONG_ENV"; then
  docker exec "$kong" grep upstream_keepalive "$KONG_ENV" || true
  echo "::error::kong reloaded in $kong, but $KONG_ENV does not carry upstream_keepalive_idle_timeout = $IDLE_S (what it does carry is above), so the reload did not apply the setting."
  exit 1
fi

echo "kong upstream keep-alive idle timeout: ${IDLE_S}s ($kong)"
