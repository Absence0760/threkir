import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const SCRIPT = fileURLToPath(new URL('./start_stack.sh', import.meta.url));

// `ss` is the knob every case turns, because WHICH SOCKET STATES the probe
// counts is the property this script exists for: the LISTEN-only probe it
// replaced was blind to the outbound ESTABLISHED socket that failed all three
// attempts of CI run 35626531071, and a stub that only ever emits LISTEN rows
// would never ask the question. Each line is one `ss -tanH` row: state,
// recv-q, send-q, local address, peer address.
const SS_STUB = (/** @type {string[]} */ rows) => `#!/usr/bin/env bash
# A faithful-enough ss: it honours -l (listening only), -a (every state) and
# -K (destroy the matching sockets). The flag handling is the point — a stub
# that emitted every row whatever was asked would let the ESTABLISHED case
# pass against the very LISTEN-only probe that caused the incident.
listen_only=0
all_states=0
kill_filter=''
while [ $# -gt 0 ]; do
  case "$1" in
    -K) kill_filter=1;;
    -*) case "$1" in *l*) listen_only=1;; esac
        case "$1" in *a*) all_states=1;; esac;;
    *) [ -n "$kill_filter" ] && kill_filter="$kill_filter\${kill_filter:+}";;
  esac
  shift
done
if [ -n "$kill_filter" ]; then exit 0; fi
cat <<'ROWS' | while read -r state rq sq local peer; do
${rows.join('\n')}
ROWS
  [ -z "$state" ] && continue
  if [ "$all_states" = 0 ]; then
    if [ "$listen_only" = 1 ]; then
      [ "$state" = LISTEN ] || continue
    else
      [ "$state" = LISTEN ] && continue
    fi
  fi
  port=\${local##*:}
  if [ -f "$SS_KILLED_PORTS" ] && grep -qx "$port" "$SS_KILLED_PORTS" 2>/dev/null; then continue; fi
  printf '%-10s %s %s %s %s\\n' "$state" "$rq" "$sq" "$local" "$peer"
done
`;

// \`sudo ss -K <filter>\` is the only destructive call the script makes. The
// stub records the filter and retires the port, so a case can assert both
// that the right socket was destroyed and that the retry then proceeds.
const SUDO_STUB = `#!/usr/bin/env bash
if [ "$1" = ss ]; then
  shift
  if [ "$1" = -K ]; then
    shift
    printf '%s\\n' "$*" >> "$SS_KILL_LOG"
    printf '%s\\n' "\${*##*:}" >> "$SS_KILLED_PORTS"
    exit 0
  fi
fi
exec "$@"
`;

// docker + supabase are inert here: no container, no stack network. That is
// deliberately the shape of every incident this script's port gate is for —
// the holder is never something `docker ps` can show.
const DOCKER_STUB = `#!/usr/bin/env bash
case "$1" in
  network) [ "$2" = ls ] && exit 0;;
  ps) exit 0;;
  rm) exit 0;;
esac
exit 0
`;

const SUPABASE_STUB = (/** @type {number} */ startExit) => `#!/usr/bin/env bash
case "$1" in
  start) printf 'start\\n' >> "$START_LOG"; exit ${startExit};;
esac
exit 0
`;

const PASSTHRU = (/** @type {string} */ name) => `#!/usr/bin/env bash
printf '%s %s\\n' "${name}" "$*" >> "$CALL_LOG"
exit 0
`;

/**
 * @param {{ rows: string[], startExit?: number, reserved?: string }} knobs
 */
function run({ rows, startExit = 0, reserved = '54321-54327' }) {
	const dir = mkdtempSync(join(tmpdir(), 'start-stack-'));
	const bin = join(dir, 'bin');
	spawnSync('mkdir', ['-p', bin]);
	const reservedFile = join(dir, 'reserved');
	writeFileSync(reservedFile, `${reserved}\n`);

	const stubs = {
		ss: SS_STUB(rows),
		docker: DOCKER_STUB,
		supabase: SUPABASE_STUB(startExit),
		sudo: SUDO_STUB,
		sysctl: PASSTHRU('sysctl'),
		systemctl: PASSTHRU('systemctl'),
		// GNU coreutils' timeout is absent on macOS, and what it wraps is not
		// what any case here is about.
		timeout: `#!/usr/bin/env bash\nshift\nexec "$@"\n`,
	};
	for (const [name, body] of Object.entries(stubs)) {
		const p = join(bin, name);
		writeFileSync(p, body);
		chmodSync(p, 0o755);
	}

	const started = Date.now();
	const res = spawnSync('bash', [SCRIPT], {
		encoding: 'utf8',
		env: {
			...process.env,
			PATH: `${bin}:${process.env.PATH}`,
			CALL_LOG: join(dir, 'calls'),
			START_LOG: join(dir, 'starts'),
			SS_KILL_LOG: join(dir, 'kills'),
			SS_KILLED_PORTS: join(dir, 'killed-ports'),
			STACK_RESERVED_PORTS_FILE: reservedFile,
			STACK_START_ATTEMPTS: '3',
			STACK_START_TIMEOUT_S: '5',
			STACK_SETTLE_TRIES: '2',
			STACK_SETTLE_INTERVAL_S: '0',
			STACK_SETTLE_GRACE_S: '0',
		},
	});
	const read = (/** @type {string} */ f) => {
		try {
			return readFileSync(join(dir, f), 'utf8').trim().split('\n').filter(Boolean);
		} catch {
			return [];
		}
	};
	return {
		status: res.status,
		out: `${res.stdout}${res.stderr}`,
		starts: read('starts').length,
		kills: read('kills'),
		wallMs: Date.now() - started,
	};
}

test('a clean runner starts the stack on the first attempt', () => {
	const r = run({ rows: ['LISTEN 0 4096 127.0.0.1:22 0.0.0.0:*'] });
	assert.equal(r.status, 0);
	assert.equal(r.starts, 1);
	assert.deepEqual(r.kills, []);
});

// The regression. CI run 35626531071 (e2e shard 7) spent all three attempts
// on "failed to bind host port for 0.0.0.0:54324" while the only thing on a
// stack port was this row — an outbound HTTPS connection to github.com that
// took 54324 as its ephemeral source port. Under the LISTEN-only probe the
// gate saw nothing, so it never warned, never waited and never killed.
test('an ESTABLISHED outbound socket on a stack port is seen as a holder', () => {
	const r = run({ rows: ['ESTAB 0 0 10.1.0.221:54324 140.82.114.21:443'] });
	assert.match(r.out, /stack ports\/network in use before attempt 1: 54324/);
	assert.deepEqual(r.kills, ['sport = :54324']);
	// Destroyed, so the attempt runs rather than burning three bind failures.
	assert.equal(r.status, 0);
	assert.equal(r.starts, 1);
});

test('a LISTEN socket on a stack port is still seen as a holder', () => {
	const r = run({ rows: ['LISTEN 0 4096 0.0.0.0:54322 0.0.0.0:*'] });
	assert.match(r.out, /stack ports\/network in use before attempt 1: 54322/);
	assert.deepEqual(r.kills, ['sport = :54322']);
	assert.equal(r.status, 0);
});

// docker-proxy binds with SO_REUSEADDR, which is permitted over TIME-WAIT, so
// counting one would fail the gate on a harmless remnant of our own previous
// attempt — and `ss -K` it, which is worse than useless.
test('a TIME-WAIT remnant on a stack port is not a holder', () => {
	const r = run({ rows: ['TIME-WAIT 0 0 127.0.0.1:54322 127.0.0.1:45976'] });
	assert.equal(r.status, 0);
	assert.equal(r.starts, 1);
	assert.doesNotMatch(r.out, /in use before attempt/);
	assert.deepEqual(r.kills, []);
});

// A connection TO the db leaves the stack port in the PEER column; only the
// local column can hold a port we are about to bind.
test('a client connected to a stack port is not a holder', () => {
	const r = run({ rows: ['ESTAB 0 0 127.0.0.1:45976 127.0.0.1:54322'] });
	assert.equal(r.status, 0);
	assert.doesNotMatch(r.out, /in use before attempt/);
});

test('an unrelated port that merely contains a stack port is not a holder', () => {
	const r = run({ rows: ['ESTAB 0 0 10.1.0.221:154322 140.82.114.21:443'] });
	assert.equal(r.status, 0);
	assert.doesNotMatch(r.out, /in use before attempt/);
});

test('every reserved port is probed, not just the one that collides most', () => {
	for (const port of [54321, 54322, 54323, 54324, 54325, 54326, 54327]) {
		const r = run({ rows: [`ESTAB 0 0 10.1.0.221:${port} 140.82.114.21:443`] });
		assert.deepEqual(r.kills, [`sport = :${port}`], `port ${port}`);
	}
});

// The reservation is the preventive half (incident 3) and it has to fail
// loudly: a runner image that drops sudo or mounts /proc read-only would
// otherwise surface as the cryptic bind error a job later.
test('a reservation that does not take fails before any start attempt', () => {
	const r = run({ rows: [], reserved: '' });
	assert.equal(r.status, 1);
	assert.equal(r.starts, 0);
	assert.match(r.out, /could not reserve stack ports 54321-54327/);
});

test('a start that keeps failing gives up after the attempt budget', () => {
	const r = run({ rows: [], startExit: 1 });
	assert.equal(r.status, 1);
	assert.equal(r.starts, 3);
	assert.match(r.out, /supabase start failed 3 times/);
	assert.match(r.out, /restarting docker before the final attempt/);
});
