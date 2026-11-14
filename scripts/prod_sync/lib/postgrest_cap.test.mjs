// Unit tests for the PostgREST row cap stage (decisions § 987, § 1936),
// driven with a fake reader: it parses the pin, refuses anything but one
// integer from the reader, passes a production cap at or above the pin and
// fails one below it or unread, and the release runs it from the committed
// config.toml.
// Run: node --test scripts/prod_sync/lib/postgrest_cap.test.mjs

import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import { STAGES, postgrestCapCheck } from '../run.mjs';
import { parseReadCap, pinnedMaxRows, postgrestCapStage } from './postgrest_cap.mjs';

const ENV = { SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst', SUPABASE_ACCESS_TOKEN: 'token' };

/** @param {{ ok: boolean, stdout: string, stderr: string }} reply @param {Record<string, string>} [env] */
function ctx(reply, env = ENV) {
	/** @type {string[][]} */
	const commands = [];
	return {
		commands,
		ctx: {
			dryRun: true,
			env,
			runSql: () => ({ ok: false, stdout: '', stderr: 'no sql' }),
			/** @param {string} cmd @param {string[]} args */
			exec: (cmd, args) => {
				commands.push([cmd, ...args]);
				return reply;
			},
		},
	};
}

test('the pin is read from [api] only, comments allowed', () => {
	assert.equal(pinnedMaxRows('[api]\nport = 1\n# note\nmax_rows = 1000\n\n[db]\nmax_rows = 5\n'), 1000);
	assert.equal(pinnedMaxRows('[api]\nmax_rows = 250 # pinned\n'), 250);
	assert.equal(pinnedMaxRows('[api]\nport = 1\n[db]\nmax_rows = 5\n'), null);
	assert.equal(pinnedMaxRows('[db]\nport = 1\n'), null);
});

test('the reader must print one integer and nothing else', () => {
	assert.equal(parseReadCap('1000\n'), 1000);
	assert.equal(parseReadCap('{"max_rows":1000,"jwt_secret":"x"}'), null);
	assert.equal(parseReadCap('-1'), null);
	assert.equal(parseReadCap(''), null);
});

test('a production cap at or above the pin passes, read-only', () => {
	for (const prod of ['1000', '5000']) {
		const { ctx: c, commands } = ctx({ ok: true, stdout: `${prod}\n`, stderr: '' });
		const result = postgrestCapStage(1000, '/r.mjs').run?.(c);
		assert.equal(result?.failed, undefined);
		assert.deepEqual(result?.table.rows, [['max_rows', '1000', prod, 'ok']]);
		assert.deepEqual(commands, [['node', '/r.mjs']]);
	}
});

test('a production cap below the pin fails the release and says what to raise', () => {
	const { ctx: c } = ctx({ ok: true, stdout: '500\n', stderr: '' });
	const result = postgrestCapStage(1000, '/r.mjs').run?.(c);
	assert.deepEqual(result?.table.rows, [['max_rows', '1000', '500', 'below the pin']]);
	assert.match(result?.failed ?? '', /caps a response at 500 rows.*at least 1000/);
});

test('an unread cap fails rather than passing', () => {
	const { ctx: c } = ctx({ ok: false, stdout: '', stderr: 'the Management API answered 401\n' });
	const result = postgrestCapStage(1000, '/r.mjs').run?.(c);
	assert.match(result?.failed ?? '', /could not be read: the Management API answered 401/);
});

test('no pin, no ref or no token stops before anything is read', () => {
	const { ctx: c, commands } = ctx({ ok: true, stdout: '1000', stderr: '' });
	assert.throws(() => postgrestCapStage(null, '/r.mjs').run?.(c), /pins no \[api\] max_rows/);
	assert.throws(() => postgrestCapStage(1000, '/r.mjs').run?.({ ...c, env: { SUPABASE_ACCESS_TOKEN: 't' } }), /SUPABASE_PROJECT_REF/);
	assert.throws(
		() => postgrestCapStage(1000, '/r.mjs').run?.({ ...c, env: { SUPABASE_PROJECT_REF: ENV.SUPABASE_PROJECT_REF } }),
		/SUPABASE_ACCESS_TOKEN/,
	);
	assert.deepEqual(commands, []);
});

test('the release runs the check from the committed pin, and its reader prints only max_rows', () => {
	assert.ok(STAGES.includes(postgrestCapCheck));
	const stage = postgrestCapCheck();
	const { ctx: c } = ctx({ ok: true, stdout: '999', stderr: '' });
	assert.match(stage.run?.(c)?.failed ?? '', /below the 1000/);
	const reader = fs.readFileSync(new URL('../postgrest_max_rows.mjs', import.meta.url), 'utf8');
	assert.equal((reader.match(/process\.stdout\.write/g) ?? []).length, 1);
	assert.match(reader, /process\.stdout\.write\(`\$\{maxRows\}\\n`\)/);
	assert.doesNotMatch(reader, /console\.log/);
});
