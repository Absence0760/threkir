import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const SCRIPT = fileURLToPath(new URL('./tune_kong_keepalive.sh', import.meta.url));
const SOURCE = readFileSync(SCRIPT, 'utf8');

// What each upstream behind kong measured as its own idle-close, in seconds,
// from the script's header. Realtime's 5 s is the floor the setting has to
// stay under; the rest are recorded so a new floor is a visible edit here.
const UPSTREAM_IDLE_CLOSE_S = { realtime: 5, rest: 30, storage: 62, pg_meta: 73 };

/**
 * A docker that answers `ps` with the given container names and runs each
 * `exec` through the knob for its command. Every call is logged, one line per
 * call with its arguments joined by spaces, so a case can assert what was
 * asked of kong and, as importantly, what never was.
 * @param {{ names: string[], template?: number, reload?: string, kongEnv?: string }} knobs
 */
const DOCKER_STUB = ({ names, template = 0, reload = 'echo "Kong reloaded"; exit 0', kongEnv = 'upstream_keepalive_idle_timeout = 2' }) =>
	`#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$DOCKER_LOG"
case "$1" in
  ps) ${names.length === 0 ? ':' : `printf '%s\\n' ${names.map((n) => JSON.stringify(n)).join(' ')}`};;
  exec)
    case "$*" in
      *" test -f "*) exit ${template};;
      *" kong reload "*) ${reload};;
      *" grep -qx "*)
        want=\${@: -2:1}
        [ "$want" = ${JSON.stringify(kongEnv)} ] && exit 0 || exit 1;;
      *" grep upstream_keepalive "*) echo ${JSON.stringify(kongEnv)};;
    esac;;
esac
`;

/** @param {Parameters<typeof DOCKER_STUB>[0]} knobs */
function run(knobs) {
	const dir = mkdtempSync(join(tmpdir(), 'tune-kong-'));
	const log = join(dir, 'docker.log');
	writeFileSync(log, '');
	const docker = join(dir, 'docker');
	writeFileSync(docker, DOCKER_STUB(knobs));
	chmodSync(docker, 0o755);
	const res = spawnSync('bash', [SCRIPT], {
		encoding: 'utf8',
		env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, DOCKER_LOG: log }
	});
	return {
		status: res.status,
		out: `${res.stdout}${res.stderr}`,
		calls: readFileSync(log, 'utf8').trim().split('\n').filter(Boolean)
	};
}

const KONG = 'supabase_kong_project-running';
/** @param {string[]} calls */
const reloads = (calls) => calls.filter((c) => c.includes(' kong reload '));

test('reloads the one kong container with the short idle timeout and the CLI template, then confirms it', () => {
	const r = run({ names: [KONG] });
	assert.equal(r.status, 0, r.out);
	assert.deepEqual(reloads(r.calls), [
		`exec -e KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT=2 ${KONG} kong reload --nginx-conf /home/kong/custom_nginx.template`
	]);
	assert.ok(
		r.calls.includes(`exec ${KONG} grep -qx upstream_keepalive_idle_timeout = 2 /usr/local/kong/.kong_env`),
		r.calls.join('\n')
	);
	assert.match(r.out, /kong upstream keep-alive idle timeout: 2s \(supabase_kong_project-running\)/);
	assert.doesNotMatch(r.out, /::error::/);
});

test('the idle timeout stays below the idle-close of every upstream kong fronts', () => {
	const idle = Number(/^IDLE_S=(\d+)$/m.exec(SOURCE)?.[1]);
	assert.ok(Number.isInteger(idle) && idle > 0, 'IDLE_S is a positive whole number of seconds');
	for (const [upstream, closeS] of Object.entries(UPSTREAM_IDLE_CLOSE_S)) {
		assert.ok(idle < closeS, `kong's ${idle}s must be under ${upstream}'s ${closeS}s, or ${upstream} can close a connection kong still holds`);
	}
	for (const upstream of Object.keys(UPSTREAM_IDLE_CLOSE_S)) {
		assert.match(SOURCE, new RegExp(`^#\\s+${upstream}\\b`, 'm'), `the header records ${upstream}'s measurement`);
	}
});

test('no kong container fails naming the count, and reloads nothing', () => {
	const r = run({ names: [] });
	assert.equal(r.status, 1);
	assert.match(r.out, /::error::Expected exactly one running supabase_kong_\* container, found 0 \(none\)/);
	assert.deepEqual(reloads(r.calls), []);
});

test('two kong containers fail naming both, and reload neither', () => {
	const r = run({ names: [KONG, 'supabase_kong_other'] });
	assert.equal(r.status, 1);
	assert.match(r.out, /found 2 \(supabase_kong_project-running supabase_kong_other\)/);
	assert.deepEqual(reloads(r.calls), []);
});

test('a missing CLI nginx template fails before a reload could drop the custom config', () => {
	const r = run({ names: [KONG], template: 1 });
	assert.equal(r.status, 1);
	assert.match(r.out, /::error::supabase_kong_project-running has no \/home\/kong\/custom_nginx\.template/);
	assert.deepEqual(reloads(r.calls), []);
});

test('a failed reload relays kong\'s own output and says the default still stands', () => {
	const r = run({ names: [KONG], reload: 'echo "Error: nginx: [emerg] bad directive"; exit 1' });
	assert.equal(r.status, 1);
	assert.match(r.out, /Error: nginx: \[emerg\] bad directive/);
	assert.match(r.out, /::error::kong reload failed in supabase_kong_project-running .*still the default 60s/);
	assert.equal(r.calls.filter((c) => c.includes(' grep -qx ')).length, 0, 'nothing is verified after a failed reload');
});

test('a reload that leaves the old value in place fails and shows what kong carries', () => {
	const r = run({ names: [KONG], kongEnv: 'upstream_keepalive_idle_timeout = 60' });
	assert.equal(r.status, 1);
	assert.match(r.out, /upstream_keepalive_idle_timeout = 60/);
	assert.match(r.out, /::error::kong reloaded in supabase_kong_project-running, but \/usr\/local\/kong\/\.kong_env does not carry upstream_keepalive_idle_timeout = 2/);
});
