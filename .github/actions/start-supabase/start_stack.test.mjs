import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const SCRIPT = fileURLToPath(new URL('./start_stack.sh', import.meta.url));
const CONFIG = fileURLToPath(new URL('../../../apps/backend/supabase/config.toml', import.meta.url));
const CI = fileURLToPath(new URL('../../workflows/ci.yml', import.meta.url));

// Linux's default net.ipv4.ip_local_port_range is 32768-60999. A host port
// the stack publishes inside it can be taken as an outbound socket's source
// port before the reservation runs, which is incidents 3 and 5.
const EPHEMERAL_FLOOR = 32768;

// Every section whose port the CLI publishes on the host, and the CLI
// default each one falls back to when config.toml leaves it out. Every
// default sits inside the ephemeral range, so an unpinned key is the bug.
const PUBLISHED = [
	['api', 'port'],
	['db', 'port'],
	['db', 'shadow_port'],
	['db.pooler', 'port'],
	['studio', 'port'],
	['inbucket', 'port'],
	['inbucket', 'smtp_port'],
	['inbucket', 'pop3_port'],
	['analytics', 'port'],
];

function configPorts(text = readFileSync(CONFIG, 'utf8')) {
	/** @type {Map<string, number>} */
	const found = new Map();
	let section = '';
	for (const line of text.split('\n')) {
		const header = line.match(/^\[([^\]]+)\]/);
		if (header) {
			section = header[1];
			continue;
		}
		const kv = line.match(/^(\w*port)\s*=\s*(\d+)/);
		if (kv) found.set(`${section}.${kv[1]}`, Number(kv[2]));
	}
	return found;
}

function scriptVar(/** @type {string} */ name) {
	const m = readFileSync(SCRIPT, 'utf8').match(new RegExp(`^${name}="?([^"\\n]+)"?$`, 'm'));
	assert.ok(m, `${name} not found in start_stack.sh`);
	return m[1];
}

const PORTS = scriptVar('PORTS').split(' ').map(Number);
const RESERVED_RANGE = scriptVar('RESERVED_RANGE');
const EDGE_RUNTIME_VERSION = scriptVar('EDGE_RUNTIME_VERSION');

// The first Supabase CLI whose bundled edge runtime carries the SIGBUS fix
// (v1.77.1, supabase/edge-runtime#746) — read off the FROM line of
// apps/cli-go/pkg/config/templates/Dockerfile at each release tag. From this
// CLI on, the script's runtime override is redundant or a downgrade.
const FIRST_CLI_WITH_FIX = '2.119.0';

function expandRange(/** @type {string} */ spec) {
	return spec.split(',').flatMap((part) => {
		const [lo, hi = lo] = part.split('-').map(Number);
		return Array.from({ length: hi - lo + 1 }, (_, i) => lo + i);
	});
}

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
  ps) case "$*" in *supabase_edge_runtime*Image*) [ -n "$EDGE_IMAGE" ] && printf '%s\\n' "$EDGE_IMAGE";; esac
      exit 0;;
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
 * @param {{ rows: string[], startExit?: number, reserved?: string, edgePinFile?: string, edgeImage?: string }} knobs
 */
function run({ rows, startExit = 0, reserved = RESERVED_RANGE, edgePinFile = join('temp', 'edge-runtime-version'), edgeImage = '' }) {
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
			STACK_EDGE_RUNTIME_VERSION_FILE: join(dir, edgePinFile),
			EDGE_IMAGE: edgeImage,
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
		edgePin: read(edgePinFile),
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
// on "failed to bind host port for 0.0.0.0:54324" (the inbucket web port
// before the move to 2432x) while the only thing on a stack port was an
// outbound HTTPS connection to github.com that took it as its ephemeral
// source port. Under the LISTEN-only probe the gate saw nothing, so it never
// warned, never waited and never killed.
test('an ESTABLISHED outbound socket on a stack port is seen as a holder', () => {
	const r = run({ rows: ['ESTAB 0 0 10.1.0.221:24324 140.82.114.21:443'] });
	assert.match(r.out, /stack ports\/network in use before attempt 1: 24324/);
	assert.deepEqual(r.kills, ['sport = :24324']);
	// Destroyed, so the attempt runs rather than burning three bind failures.
	assert.equal(r.status, 0);
	assert.equal(r.starts, 1);
});

test('a LISTEN socket on a stack port is still seen as a holder', () => {
	const r = run({ rows: ['LISTEN 0 4096 0.0.0.0:24322 0.0.0.0:*'] });
	assert.match(r.out, /stack ports\/network in use before attempt 1: 24322/);
	assert.deepEqual(r.kills, ['sport = :24322']);
	assert.equal(r.status, 0);
});

// docker-proxy binds with SO_REUSEADDR, which is permitted over TIME-WAIT, so
// counting one would fail the gate on a harmless remnant of our own previous
// attempt — and `ss -K` it, which is worse than useless.
test('a TIME-WAIT remnant on a stack port is not a holder', () => {
	const r = run({ rows: ['TIME-WAIT 0 0 127.0.0.1:24322 127.0.0.1:45976'] });
	assert.equal(r.status, 0);
	assert.equal(r.starts, 1);
	assert.doesNotMatch(r.out, /in use before attempt/);
	assert.deepEqual(r.kills, []);
});

// A connection TO the db leaves the stack port in the PEER column; only the
// local column can hold a port we are about to bind.
test('a client connected to a stack port is not a holder', () => {
	const r = run({ rows: ['ESTAB 0 0 127.0.0.1:45976 127.0.0.1:24322'] });
	assert.equal(r.status, 0);
	assert.doesNotMatch(r.out, /in use before attempt/);
});

test('an unrelated port that merely contains a stack port is not a holder', () => {
	const r = run({ rows: ['ESTAB 0 0 10.1.0.221:124322 140.82.114.21:443'] });
	assert.equal(r.status, 0);
	assert.doesNotMatch(r.out, /in use before attempt/);
});

test('every reserved port is probed, not just the one that collides most', () => {
	for (const port of PORTS) {
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
	assert.match(r.out, new RegExp(`could not reserve stack ports ${RESERVED_RANGE}`));
});

// Issue #916. The CLI reads this file at every config load and swaps the
// edge runtime's tag for its contents, so the pin has to be on disk before
// the first `supabase start`, not merely somewhere in the script.
test('the edge runtime is pinned before the first start attempt', () => {
	const r = run({ rows: [] });
	assert.equal(r.status, 0);
	assert.equal(r.starts, 1);
	assert.deepEqual(r.edgePin, [EDGE_RUNTIME_VERSION]);
});

test('a pin that cannot be written fails before any start attempt', () => {
	// `reserved` is a regular file, so nothing can be created beneath it.
	const r = run({ rows: [], edgePinFile: join('reserved', 'edge-runtime-version') });
	assert.equal(r.status, 1);
	assert.equal(r.starts, 0);
	assert.match(r.out, new RegExp(`could not pin the edge runtime to ${EDGE_RUNTIME_VERSION}`));
});

test('a started stack running the pinned runtime passes', () => {
	const image = `ghcr.io/supabase/edge-runtime:${EDGE_RUNTIME_VERSION}`;
	const r = run({ rows: [], edgeImage: image });
	assert.equal(r.status, 0);
	assert.ok(r.out.includes(`edge runtime image: ${image}`), r.out);
});

// The override is a file the CLI may or may not honour; what it started is
// the fact. v1.73.0 is the image every #916 occurrence ran.
test('a started stack running some other runtime fails', () => {
	const r = run({ rows: [], edgeImage: 'public.ecr.aws/supabase/edge-runtime:v1.73.0' });
	assert.equal(r.status, 1);
	assert.equal(r.starts, 1);
	assert.ok(r.out.includes('the edge runtime is running public.ecr.aws/supabase/edge-runtime:v1.73.0, not the pinned'), r.out);
});

function compareVersions(/** @type {string} */ a, /** @type {string} */ b) {
	const pa = a.split('.').map(Number);
	const pb = b.split('.').map(Number);
	for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
		const d = (pa[i] ?? 0) - (pb[i] ?? 0);
		if (d !== 0) return Math.sign(d);
	}
	return 0;
}

function cliPins(text = readFileSync(CI, 'utf8')) {
	return [...text.matchAll(/uses: \.\/\.github\/actions\/setup-supabase-cli\n\s+with:\n\s+version: ([\d.]+)/g)].map((m) => m[1]);
}

test('the edge runtime override is retired once the CLI pin ships the fix itself', () => {
	const pins = cliPins();
	assert.ok(pins.length > 0, 'no setup-supabase-cli version pin found in ci.yml');
	const stale = pins.filter((v) => compareVersions(v, FIRST_CLI_WITH_FIX) >= 0);
	assert.deepEqual(
		stale,
		[],
		`ci.yml pins Supabase CLI ${stale.join(', ')}, which already ships edge-runtime ${EDGE_RUNTIME_VERSION} or newer — delete EDGE_RUNTIME_VERSION and its override from start_stack.sh (decisions.md § 1795) rather than let it pin an older runtime than the CLI's own`,
	);
});

test('the retirement guard reads every pin and bites on one at the fixing CLI', () => {
	const text = readFileSync(CI, 'utf8');
	assert.equal(cliPins(text).length, (text.match(/uses: \.\/\.github\/actions\/setup-supabase-cli/g) ?? []).length);
	const bumped = text.replace(/(setup-supabase-cli\n\s+with:\n\s+version: )[\d.]+/, `$1${FIRST_CLI_WITH_FIX}`);
	assert.ok(cliPins(bumped).some((v) => compareVersions(v, FIRST_CLI_WITH_FIX) >= 0));
	assert.equal(compareVersions('2.84.2', FIRST_CLI_WITH_FIX), -1);
	assert.equal(compareVersions('2.120.0', FIRST_CLI_WITH_FIX), 1);
});

test('a start that keeps failing gives up after the attempt budget', () => {
	const r = run({ rows: [], startExit: 1 });
	assert.equal(r.status, 1);
	assert.equal(r.starts, 3);
	assert.match(r.out, /supabase start failed 3 times/);
	assert.match(r.out, /restarting docker before the final attempt/);
});

// The durable half of incidents 3 and 5 (issue #963): a port outside the
// ephemeral range cannot be handed out as a source port at all, so the race
// the reservation and `ss -K` fight is never started.
function portViolations(/** @type {Map<string, number>} */ found) {
	return PUBLISHED.flatMap(([section, key]) => {
		const port = found.get(`${section}.${key}`);
		if (port === undefined) return [`[${section}] ${key} is unpinned, so the CLI publishes its default inside the ephemeral range`];
		if (port >= EPHEMERAL_FLOOR) return [`[${section}] ${key} = ${port} is inside the ephemeral range (>= ${EPHEMERAL_FLOOR})`];
		return [];
	});
}

test('config.toml pins every published port, below the ephemeral range', () => {
	assert.deepEqual(portViolations(configPorts()), []);
});

test('PORTS is exactly the set of ports config.toml publishes', () => {
	const published = PUBLISHED.map(([section, key]) => configPorts().get(`${section}.${key}`));
	assert.deepEqual([...PORTS].sort(), [...published].sort());
});

test('RESERVED_RANGE reserves exactly PORTS', () => {
	assert.deepEqual(expandRange(RESERVED_RANGE).sort(), [...PORTS].sort());
});

test('the guard reports a port inside the ephemeral range and an unpinned one', () => {
	const text = readFileSync(CONFIG, 'utf8')
		.replace(/^(\[db\]\nport = )\d+/m, (_, head) => `${head}54322`)
		.replace(/^\[studio\]\nport = \d+\n/m, '[studio]\n');
	assert.deepEqual(portViolations(configPorts(text)), [
		`[db] port = 54322 is inside the ephemeral range (>= ${EPHEMERAL_FLOOR})`,
		'[studio] port is unpinned, so the CLI publishes its default inside the ephemeral range',
	]);
});

test('the sidecar probe defaults to the api port config.toml publishes', () => {
	const probe = readFileSync(fileURLToPath(new URL('./wait_for_sidecars.sh', import.meta.url)), 'utf8');
	const m = probe.match(/^API=\$\{PROBE_API_URL:-http:\/\/127\.0\.0\.1:(\d+)\}$/m);
	assert.ok(m, 'API default not found in wait_for_sidecars.sh');
	assert.equal(Number(m[1]), configPorts().get('api.port'));
});
