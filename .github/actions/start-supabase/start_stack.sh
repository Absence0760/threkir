#!/usr/bin/env bash
#
# Boot the local Supabase stack (migrations + seed.sql on the pinned CLI)
# with a port-clean retry, and leave the evidence behind when it never comes
# up.
#
# This is shell a composite action runs, so nothing but start_stack.test.mjs
# reads it. It lives in a file rather than inline in action.yml for the same
# reason wait_for_sidecars.sh does: the retry ladder below is five incidents
# deep and every rung of it was written after a red job, so it is worth
# being able to drive with stubs.
#
# Five failure modes are handled:
#
#   1. Slow ghcr.io image pulls. A single 353MB image once trickled at
#      ~50KB/s and hung edge-functions for the full 20-min budget (CI run
#      26490131303). Normal cold boot is ~2 min, so the 480s per-attempt
#      timeout is ~4x headroom; the second attempt resumes from layer cache.
#
#   2. Port not freed on a partial start. When `supabase start` partly comes
#      up and rolls back ("Starting database... / Stopping containers..."),
#      it can orphan the db container or its docker-proxy still holding host
#      port 54322 — and `supabase stop` does NOT free it (supabase/cli#3265).
#      The previous retry ran only `supabase stop` between attempts, so
#      attempt 2 re-hit the IDENTICAL "failed to bind host port for
#      0.0.0.0:54322: address already in use" and the job died (CI run
#      26860851075, e2e shard 7). The fix: the retry force-removes any
#      container still publishing our host ports, then GATES on the ports
#      actually being free before re-running.
#
#      2b. The container force-remove is not enough on its own: a partial
#      start can also strand the stack's docker NETWORK with a dangling
#      endpoint that still reserves host port 54322 at the docker layer even
#      though NO container publishes it and NO socket is in LISTEN (CI run
#      27567813578, e2e shard 10). Cleanup also removes any leftover
#      `supabase_network_*` network, and the gate treats a stranded stack
#      network as a holder the `ss` probe cannot see.
#
#   3. An outbound connection's ephemeral source port. CI run 28864778110
#      (e2e shard 7) hit the identical 54322 bind error on BOTH attempts of a
#      FRESH runner: no stack container, no stack network, nothing in LISTEN.
#      The stack's host ports sit inside Linux's default ephemeral range
#      (net.ipv4.ip_local_port_range = 32768-60999), and `supabase start`
#      runs exactly when the job is busiest with outbound sockets, so a pull
#      connection can land on source port 54322 and docker-proxy's bind
#      fails. The fix is preventive: reserve the stack ports via
#      net.ipv4.ip_local_reserved_ports before the first start, so the kernel
#      never hands them out as ephemeral source ports (explicit binds are
#      unaffected; the sysctl also covers IPv6).
#
#   4. An evanescent holder no probe can see. CI run 29523121481 (e2e shard
#      2) hit the 54322 bind error on both attempts WITH the reservation
#      active, and the post-failure dump — taken ~100ms after the second bind
#      failure — showed nothing on any 5432x socket in any state. Whatever
#      held the port had already evaporated; the retry just ran too soon
#      (~200ms after cleanup). So each retry now WAITS for holders to clear
#      and then settles, a third attempt is preceded by a docker-daemon
#      restart, and forensics are captured immediately after each failed
#      attempt.
#
#   5. A holder the reservation was too late to prevent, which the gate then
#      could not see. CI run 35626531071 (e2e shard 7) failed all three
#      attempts on "failed to bind host port for 0.0.0.0:54324: address
#      already in use" while the forensics showed exactly one thing on a
#      stack port: `ESTAB 10.1.0.221:54324 -> 140.82.114.21:443`, an
#      outbound HTTPS connection to github.com holding 54324 as its source
#      port. That is incident 3's holder, and the reservation cannot evict
#      one that was established BEFORE it was set — every step ahead of this
#      one (checkout, the pnpm cache restore, the CLI download) opens
#      sockets, and the sysctl only governs allocations made after it.
#
#      What made it fatal rather than transient is that `busy_ports` probed
#      `ss -ltn` — LISTEN only. An ESTABLISHED socket is invisible to that,
#      so `stack_holders` answered "nothing", the pre-attempt gate never
#      fired, `settle_ports` fell straight through its wait loop, and all
#      three attempts re-ran into a live holder none of them named. The same
#      shape burned CI run 29711236891 (schema-codegen-drift) when 54325 and
#      54326 were missing from PORTS. So the probe now reads every socket
#      state except TIME-WAIT, and a holder that outlives the settle wait is
#      destroyed with `ss -K` rather than merely reported.
set -uo pipefail

# Host ports config.toml publishes: api 54321, db 54322, studio 54323,
# inbucket web 54324 / SMTP 54325 / POP3 54326; the CLI also publishes
# analytics on 54327. 54322 is the one that collides most often, but a
# partial start can strand any of them, so clear them all. This list MUST
# cover every port the sysctl below reserves — when 54325/54326 were missing
# from it, an inbucket bind failure on 54326 was invisible to every probe.
PORTS="54321 54322 54323 54324 54325 54326 54327"
RESERVED_RANGE=54321-54327

ATTEMPTS=${STACK_START_ATTEMPTS:-3}
START_TIMEOUT_S=${STACK_START_TIMEOUT_S:-480}
SETTLE_TRIES=${STACK_SETTLE_TRIES:-15}
SETTLE_INTERVAL_S=${STACK_SETTLE_INTERVAL_S:-2}
SETTLE_GRACE_S=${STACK_SETTLE_GRACE_S:-5}
RESERVED_PORTS_FILE=${STACK_RESERVED_PORTS_FILE:-/proc/sys/net/ipv4/ip_local_reserved_ports}

# Keep the kernel from handing any stack port out as an outbound connection's
# ephemeral source port (incident 3) — they all sit inside the default
# 32768-60999 ephemeral range. Gate on the reservation actually taking so a
# runner-image change (no sudo, read-only /proc) fails here with a pointed
# message, not later as the cryptic bind error. It is preventive only: a
# socket that already holds a stack port keeps it, which is incident 5 and is
# what the probe below has to be able to see.
sudo sysctl -qw "net.ipv4.ip_local_reserved_ports=$RESERVED_RANGE" || true
if ! grep -q "$RESERVED_RANGE" "$RESERVED_PORTS_FILE" 2>/dev/null; then
  echo "::error::could not reserve stack ports $RESERVED_RANGE from the ephemeral range (net.ipv4.ip_local_reserved_ports=$(cat "$RESERVED_PORTS_FILE" 2>/dev/null)) — an outbound socket may steal 54322 and fail the db bind"
  exit 1
fi

busy_ports() {
  # Column 1 of `ss -tanH` is the state and column 4 the LOCAL address
  # (0.0.0.0:54322, [::]:54322, 10.1.0.221:54324). Anchor on a leading : or
  # . so 54322 never matches a substring of some unrelated high port.
  #
  # LISTEN is NOT the only state that blocks a bind, and probing for it alone
  # is what made incident 5 unrecoverable: an ESTABLISHED outbound connection
  # that took a stack port as its ephemeral source port holds it just as
  # hard, and no amount of container or network cleanup can free one.
  # TIME-WAIT is excluded on purpose — docker-proxy binds with SO_REUSEADDR,
  # which is permitted over TIME-WAIT, so counting it would fail the gate on
  # a harmless remnant of our own previous attempt.
  local locals busy=""
  locals=$(ss -tanH 2>/dev/null | awk '$1 != "TIME-WAIT" { print $4 }')
  for p in $PORTS; do
    if printf '%s\n' "$locals" | grep -qE "[:.]${p}\$"; then
      busy="$busy $p"
    fi
  done
  printf '%s' "$busy"
}

stack_networks() {
  # A stranded `supabase_network_*` network keeps a dangling endpoint that
  # reserves host port 54322 at the docker layer even with no container +
  # nothing on a socket, so busy_ports can't see it. See incident 2b.
  docker network ls --filter "name=supabase_network_" -q 2>/dev/null || true
}

# All holders busy_ports can't see on its own, as a single token the gate can
# test + print: socket-visible ports plus "stack-network" when a leftover
# supabase network is reserving a port.
stack_holders() {
  local b n
  b=$(busy_ports)
  n=$(stack_networks)
  printf '%s' "$b${n:+ stack-network}"
}

free_ports() {
  # supabase stop is project-aware but does not reliably release the host
  # port a partial start orphaned (supabase/cli#3265), so follow it with a
  # force-remove of any supabase container or anything still publishing one
  # of our ports.
  supabase stop --no-backup >/dev/null 2>&1 || true
  local cids
  cids=$(docker ps -aq --filter "name=supabase_" 2>/dev/null || true)
  for p in $PORTS; do
    cids="$cids $(docker ps -aq --filter "publish=$p" 2>/dev/null || true)"
  done
  cids=$(printf '%s' "$cids" | tr ' ' '\n' | grep -v '^$' | sort -u || true)
  if [ -n "$cids" ]; then
    echo "force-removing leftover container(s) holding stack ports:"
    docker rm -f $cids >/dev/null 2>&1 || true
  fi
  # Then drop any leftover stack network. With the containers gone it has no
  # active endpoints, so `network rm` succeeds and frees the docker-layer
  # port reservation the socket probe is blind to (incident 2b).
  local nets
  nets=$(stack_networks)
  if [ -n "$nets" ]; then
    echo "removing leftover supabase network(s) reserving stack ports:"
    docker network rm $nets >/dev/null 2>&1 || true
  fi
}

kill_socket_holders() {
  # The last rung, for the one holder class nothing else can reach: a socket
  # owned by some other process on the runner that took a stack port as its
  # ephemeral source port (incident 5). free_ports has nothing to remove —
  # there is no container and no network — and settle_ports has already
  # waited for it to close on its own. `ss -K` destroys it outright. Scoped
  # to `sport = :<stack port>`, so the only socket it can ever reach is one
  # squatting a port this stack is about to bind.
  local p
  for p in $(busy_ports); do
    echo "destroying socket(s) holding stack port $p:"
    ss -tanp "sport = :$p" 2>/dev/null || true
    sudo ss -K "sport = :$p" >/dev/null 2>&1 || true
  done
}

dump_forensics() {
  # Captured IMMEDIATELY after a failure — incident 4 showed the holder can
  # be gone ~100ms later, so an end-of-job dump reads as "nothing was wrong".
  # -tan (no -p) includes process-less states like TIME-WAIT that -tnp hides.
  docker ps -a --format '{{.Names}} {{.Status}} {{.Ports}}' || true
  ss -tan 2>/dev/null | grep -E '5432[0-9]' || true
  docker network ls --filter "name=supabase_network_" || true
}

settle_ports() {
  # Wait for any holder to clear rather than re-running start immediately
  # (incident 4: the retry fired ~200ms after cleanup and re-hit a holder
  # that was gone seconds later). Then give docker's port allocator a moment
  # to settle.
  local i
  for i in $(seq 1 "$SETTLE_TRIES"); do
    [ -z "$(stack_holders)" ] && break
    sleep "$SETTLE_INTERVAL_S"
  done
  sleep "$SETTLE_GRACE_S"
}

for attempt in $(seq 1 "$ATTEMPTS"); do
  # Gate on the real precondition — no leftover holder — before each attempt.
  # On attempt 1 of a fresh runner this is usually a no-op; on later attempts
  # it proves the post-failure cleanup actually worked (ports AND the docker
  # network it reserves through).
  busy=$(stack_holders)
  if [ -n "$busy" ]; then
    echo "::warning::stack ports/network in use before attempt $attempt:$busy"
    docker ps --format '{{.Names}} {{.Ports}}' || true
    free_ports
    settle_ports
    busy=$(stack_holders)
    if [ -n "$busy" ]; then
      # Nothing removable holds these, and they did not close on their own,
      # so what is left is a squatting socket. Destroy it (incident 5) rather
      # than spending three 480s attempts on a bind that cannot succeed.
      echo "::warning::stack ports/network still in use after cleanup:$busy — destroying the sockets holding them"
      kill_socket_holders
      settle_ports
      busy=$(stack_holders)
    fi
    if [ -n "$busy" ]; then
      echo "::error::stack ports/network still in use after cleanup:$busy"
      # All socket states, not just LISTEN — an outbound socket holding a
      # stack port as its source port shows up here.
      ss -tanp 2>/dev/null | grep -E '5432[0-9]' || true
      docker network ls --filter "name=supabase_network_" || true
      exit 1
    fi
  fi

  if timeout "$START_TIMEOUT_S" supabase start; then
    exit 0
  fi

  echo "::warning::supabase start attempt $attempt failed/timed out; forensics then cleanup"
  dump_forensics
  free_ports

  if [ "$attempt" = "$ATTEMPTS" ]; then
    echo "::error::supabase start failed $ATTEMPTS times"
    exit 1
  fi

  settle_ports
  if [ "$attempt" = "$(( ATTEMPTS - 1 ))" ]; then
    # Last resort before the final attempt: a daemon restart drops any leaked
    # daemon-internal port allocation that no container / network / socket
    # probe can see (incident 4).
    echo "restarting docker before the final attempt"
    sudo systemctl restart docker 2>/dev/null || true
    # The restart tears down supabase's compose state mid-flight; clear the
    # debris so the final attempt starts from a clean slate.
    free_ports
    settle_ports
  fi
done
