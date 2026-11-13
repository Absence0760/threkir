// Unit tests for the production sync plumbing (issue #1349, decisions § 2429),
// and the entry point driven end to end against a stub `psql` on PATH: what
// each stage's transaction sends, that a dry run rolls back, that the
// password never reaches the command line or the output, and the step
// summary it writes.
// Run: node --test scripts/prod_sync/lib/stages.test.mjs

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { actionCounts, markdownTable, parseCsv, runStages, stageScript, stageSummary } from './stages.mjs';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const ENTRY = path.join(REPO, 'apps', 'backend', 'scripts', 'sync-production-state.sh');

test('a stage commits, or rolls back on a dry run, inside one bounded transaction', () => {
	const real = stageScript('select 1;', { dryRun: false });
	assert.equal(
		real,
		"\\set ON_ERROR_STOP on\nbegin;\nset local lock_timeout = '5s';\nset local statement_timeout = '5min';\nselect 1;\ncommit;\n",
	);
	const dry = stageScript('select 1;\n', { dryRun: true });
	assert.ok(dry.endsWith('select 1;\nrollback;\n'));
	assert.ok(!dry.includes('commit'));
});

test('psql CSV parses, quoting and empty fields included', () => {
	assert.deepEqual(parseCsv('a,b,c\n1,,"x, ""y"""\n2,"multi\nline",z\n'), {
		header: ['a', 'b', 'c'],
		rows: [
			['1', '', 'x, "y"'],
			['2', 'multi\nline', 'z'],
		],
	});
	assert.deepEqual(parseCsv('a,b\r\n1,2\r\n'), { header: ['a', 'b'], rows: [['1', '2']] });
	assert.deepEqual(parseCsv(''), { header: [], rows: [] });
	assert.deepEqual(parseCsv('a,b\n'), { header: ['a', 'b'], rows: [] });
	assert.throws(() => parseCsv('a,b\n1\n'), /1 fields, the header 2/);
	assert.throws(() => parseCsv('a\n"open\n'), /unterminated/);
});

test('a table renders as markdown with its cells escaped', () => {
	assert.equal(
		markdownTable({ header: ['k', 'v'], rows: [['a|b', ''], ['c', 'd\ne']] }),
		'| k | v |\n| --- | --- |\n| a\\|b |   |\n| c | d e |\n',
	);
	assert.equal(markdownTable({ header: [], rows: [] }), '_No rows._\n');
});

test('actions are counted in first-seen order, and only when there is an action column', () => {
	assert.equal(
		actionCounts({ header: ['x', 'action'], rows: [['1', 'unchanged'], ['2', 'closed'], ['3', 'unchanged']] }),
		'2 unchanged, 1 closed',
	);
	assert.equal(actionCounts({ header: ['action'], rows: [] }), 'no rows');
	assert.equal(actionCounts({ header: ['x'], rows: [['1']] }), null);
});

test('a dry run says so in its summary', () => {
	const stage = { id: 's', title: 'Stage', sql: '', note: '1 thing' };
	const table = { header: ['action'], rows: [['created']] };
	assert.equal(
		stageSummary(stage, table, { dryRun: true }),
		'### Stage (dry run, rolled back)\n\n1 thing\n\n1 created.\n\n| action |\n| --- |\n| created |\n\n',
	);
	assert.ok(stageSummary(stage, table, { dryRun: false }).startsWith('### Stage\n'));
});

test('stages run in order and the first failure stops the rest', () => {
	/** @type {string[]} */
	const scripts = [];
	let out = '';
	const ok = runStages(
		[
			{ id: 'a', title: 'A', sql: 'select 1;' },
			{ id: 'b', title: 'B', sql: 'select 2;' },
			{ id: 'c', title: 'C', sql: 'select 3;' },
		],
		{
			dryRun: false,
			runSql: (script) => {
				scripts.push(script);
				return script.includes('select 2;')
					? { ok: false, stdout: '', stderr: 'psql:<stdin>:5: ERROR:  boom\n' }
					: { ok: true, stdout: 'action\nunchanged\n', stderr: '' };
			},
			write: (md) => {
				out += md;
			},
		},
	);
	assert.equal(ok, false);
	assert.equal(scripts.length, 2, 'stage C never runs');
	assert.ok(out.startsWith('## Sync production state\n'));
	assert.ok(out.includes('### A\n\n1 unchanged.'));
	assert.ok(out.includes('### B: failed, rolled back\n\n```\npsql:<stdin>:5: ERROR:  boom\n```'));
	assert.ok(!out.includes('### C'));
});

test('a run stage gets the context, reports its table, and stops the sync on a failure or a throw', () => {
	let out = '';
	/** @type {import('./stages.mjs').StageContext[]} */
	const seen = [];
	const write = (/** @type {string} */ md) => {
		out += md;
	};
	const exec = () => ({ ok: true, stdout: 'x', stderr: '' });
	const ok = runStages(
		[
			{ id: 'r', title: 'R', run: (ctx) => (seen.push(ctx), { table: { header: ['action'], rows: [['set']] } }) },
			{ id: 'f', title: 'F', run: () => ({ table: { header: ['action'], rows: [['created']] }, failed: 'answered 500' }) },
			{ id: 'never', title: 'Never', sql: 'select 1;' },
		],
		{ dryRun: true, runSql: () => assert.fail('no SQL stage runs after a failure'), write, exec, env: { A: '1' } },
	);
	assert.equal(ok, false);
	assert.equal(seen[0].dryRun, true);
	assert.equal(seen[0].exec, exec);
	assert.deepEqual(seen[0].env, { A: '1' });
	assert.ok(out.includes('### R (dry run, rolled back)\n\n1 set.'));
	assert.ok(out.includes('### F (dry run, rolled back)\n\n1 created.'), 'what a failed stage did is still reported');
	assert.ok(out.includes('### F: failed\n\n```\nanswered 500\n```'));

	out = '';
	const thrown = runStages([{ id: 't', title: 'T', run: () => { throw new Error('no project ref'); } }], {
		dryRun: false,
		runSql: () => ({ ok: true, stdout: '', stderr: '' }),
		write,
	});
	assert.equal(thrown, false);
	assert.equal(out, '## Sync production state\n\n### T: failed\n\n```\nno project ref\n```\n\n');
});

// A stub psql that records its arguments, its PGPASSWORD and every stdin it is
// sent (one per transaction, appended), and answers with the CSV in $STUB_CSV
// (or fails when it is unset).
const STUB = `#!/usr/bin/env bash
set -u
printf '%s\\n' "$@" > "$STUB_STATE/args"
printf '%s' "\${PGPASSWORD:-<unset>}" > "$STUB_STATE/pgpassword"
cat >> "$STUB_STATE/stdin"
if [[ -z "\${STUB_CSV:-}" ]]; then
  echo "psql:<stdin>:20: ERROR:  42501: not an official publisher" >&2
  exit 3
fi
printf '%b' "$STUB_CSV"
`;

/** Lists nothing deployed and no secret set, so a retirement reads `absent`. */
const SUPABASE_STUB = '#!/usr/bin/env bash\necho "$*" >> "$STUB_STATE/supabase"\necho "[]"\n';

/** @param {string[]} args @param {Record<string, string>} env */
function runEntry(args, env) {
	const root = fs.mkdtempSync(path.join(tmpdir(), 'prod-sync-'));
	const bin = path.join(root, 'bin');
	const state = path.join(root, 'state');
	fs.mkdirSync(bin);
	fs.mkdirSync(state);
	fs.writeFileSync(path.join(bin, 'psql'), STUB);
	fs.chmodSync(path.join(bin, 'psql'), 0o755);
	fs.writeFileSync(path.join(bin, 'supabase'), SUPABASE_STUB);
	fs.chmodSync(path.join(bin, 'supabase'), 0o755);
	const summary = path.join(root, 'summary.md');
	const r = spawnSync('bash', [ENTRY, ...args], {
		encoding: 'utf8',
		env: {
			PATH: `${bin}:${process.env.PATH}`,
			HOME: process.env.HOME ?? root,
			STUB_STATE: state,
			GITHUB_STEP_SUMMARY: summary,
			SUPABASE_PROJECT_REF: 'abcdefghijklmnopqrst',
			SUPABASE_ACCESS_TOKEN: 'token',
			...env,
		},
	});
	const read = (/** @type {string} */ f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : '');
	const result = {
		status: r.status,
		stdout: r.stdout,
		stderr: r.stderr,
		args: read(path.join(state, 'args')),
		pgpassword: read(path.join(state, 'pgpassword')),
		stdin: read(path.join(state, 'stdin')),
		supabase: read(path.join(state, 'supabase')),
		summary: read(summary),
	};
	fs.rmSync(root, { recursive: true, force: true });
	return result;
}

const SECRET = 'p%40ss!^word';
const URL_WITH_PASSWORD = `postgresql://postgres.ref:${SECRET}@aws-0.pooler.supabase.com:5432/postgres`;

test('the entry point connects without the password on the command line and summarises each course', () => {
	const r = runEntry([], {
		SUPABASE_DB_URL: URL_WITH_PASSWORD,
		SUPABASE_DB_PASSWORD: SECRET,
		STUB_CSV: 'park,course_slug,action,backfill_job_id,park_course_id\\npocahontas,swift-creek-5k,unchanged,,u1\\n',
	});
	assert.equal(r.status, 0, r.stderr);
	assert.equal(r.args.split('\n')[0], 'postgresql://postgres.ref@aws-0.pooler.supabase.com:5432/postgres');
	assert.equal(r.pgpassword, SECRET);
	for (const text of [r.args, r.stdout, r.stderr, r.summary]) assert.ok(!text.includes(SECRET));
	assert.ok(r.stdin.includes('from private.load_park_catalogue('));
	assert.ok(r.stdin.endsWith('commit;\n'));
	assert.ok(r.summary.includes('### Park catalogue\n'));
	assert.ok(r.summary.includes('1 unchanged.'));
	assert.ok(r.summary.includes('| pocahontas | swift-creek-5k | unchanged |   | u1 |'));
	assert.equal(r.stdout, r.summary);
	for (const title of ['Feature flags', 'Edge Function env toggles', 'Retired Edge Functions and secrets', 'Web build flags', 'Cron URL entries', 'One-off ops tasks']) {
		assert.ok(r.summary.includes(`### ${title}\n`), title);
	}
	// The committed retirements only list: nothing is deployed in the stub, so
	// each reads absent and no delete or unset is sent.
	assert.ok(r.summary.includes('| function | parkrun-import | absent |'));
	assert.ok(!/functions delete|secrets unset/.test(r.supabase), r.supabase);
	// A flag or cron URL is sent exactly when the committed config declares
	// one: a flag declared off (the health backlog purge, pending counsel) is
	// still applied, so prod is pinned to the declared state.
	const committed = JSON.parse(fs.readFileSync(path.join(REPO, 'apps', 'backend', 'ops', 'prod_config.json'), 'utf8'));
	const flags = Object.keys(committed.feature_flags);
	assert.equal(r.stdin.includes('private.apply_feature_flag('), flags.length > 0, 'a flag is applied only when one is declared');
	for (const flag of flags) assert.ok(r.stdin.includes(`'${flag}'`), `the declared flag ${flag} is sent`);
	assert.equal(r.stdin.includes('private.arm_cron_url('), committed.cron_urls.length > 0, 'a cron URL is armed only when one is declared');
	// The committed one-off tasks are not a toggle: each one the stub's ledger
	// has not recorded is begun exactly once, and none is begun when none is
	// committed.
	const tasks = fs
		.readdirSync(path.join(REPO, 'apps', 'backend', 'ops', 'tasks'))
		.filter((f) => f.endsWith('.sql'))
		.map((f) => f.replace(/\.sql$/, ''));
	assert.equal(r.stdin.split('private.begin_ops_task(').length - 1, tasks.length, r.stdin);
	assert.equal(tasks.length > 0, r.stdin.includes('private.ops_task_runs'), 'the ledger is read only when a task is committed');
	for (const name of tasks) {
		assert.equal(r.stdin.split(`private.begin_ops_task('${name}'`).length - 1, 1, name);
		assert.match(r.summary, new RegExp(`\\| ${name} \\| [0-9a-f]{12} \\| ran \\|`), name);
	}
});

test('a dry run rolls the stage back', () => {
	const r = runEntry(['--dry-run'], {
		SUPABASE_DB_URL: URL_WITH_PASSWORD,
		SUPABASE_DB_PASSWORD: SECRET,
		STUB_CSV: 'park,course_slug,action\\npocahontas,beaver-lake-trail,created\\n',
	});
	assert.equal(r.status, 0, r.stderr);
	assert.ok(r.stdin.endsWith('rollback;\n'));
	assert.ok(!r.stdin.includes('commit;'));
	assert.ok(r.summary.startsWith('## Sync production state (dry run)\n'));
	assert.ok(r.summary.includes('### Park catalogue (dry run, rolled back)'));
});

test('a failed stage fails the step and puts the database error in the summary', () => {
	const r = runEntry([], { SUPABASE_DB_URL: URL_WITH_PASSWORD, SUPABASE_DB_PASSWORD: SECRET });
	assert.equal(r.status, 1);
	assert.ok(r.summary.includes('### Park catalogue: failed, rolled back'));
	assert.ok(r.summary.includes('not an official publisher'));
	assert.match(r.stderr, /::error::a production sync stage failed/);
	assert.ok(!r.stderr.includes(SECRET) && !r.summary.includes(SECRET));
});

test('an unknown argument or a missing database URL stops before connecting', () => {
	const bad = runEntry(['--force'], { SUPABASE_DB_URL: URL_WITH_PASSWORD, STUB_CSV: 'a\\n' });
	assert.equal(bad.status, 2);
	assert.equal(bad.args, '');
	const unset = runEntry([], { STUB_CSV: 'a\\n' });
	assert.notEqual(unset.status, 0);
	assert.match(unset.stderr, /SUPABASE_DB_URL must be set/);
	assert.equal(unset.args, '');
});
