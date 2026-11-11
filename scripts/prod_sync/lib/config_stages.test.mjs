// Unit tests for the prod config stages (issue #1350, decisions § 2430),
// driven with a fake psql and a fake Supabase CLI: what each stage sends, that
// an absent entry is never touched, that a dry run writes nothing, that the
// function env stage reads only digests and prints only booleans, that a cron
// entry is invoked once when armed and its status checked, and that an ops
// task runs once and refuses a changed file. The SQL itself is pinned against
// a database by apps/backend/supabase/tests/prod_config_sync_test.sql.
// Run: node --test scripts/prod_sync/lib/config_stages.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import {
	allowListedDigests,
	cronArmSql,
	cronUrlsStage,
	featureFlagsStage,
	functionEnvStage,
	listedNames,
	opsTasksStage,
	retiredStage,
	sha256,
	taskSql,
	webEnvStage,
} from './config_stages.mjs';

const EMPTY = { feature_flags: {}, function_env: {}, web_env: {}, cron_urls: [], retired_functions: [], retired_function_env: [] };
const REF = 'abcdefghijklmnopqrst';
const ISSUE = 'https://github.com/Absence0760/threkir/issues/1097#issuecomment-1';

/**
 * @param {{ sql?: (script: string) => { ok: boolean, stdout: string, stderr: string },
 *   exec?: (cmd: string, args: string[]) => { ok: boolean, stdout: string, stderr: string },
 *   dryRun?: boolean, env?: Record<string, string> }} [o]
 */
function ctx(o = {}) {
	/** @type {string[]} */
	const scripts = [];
	/** @type {string[][]} */
	const commands = [];
	return {
		scripts,
		commands,
		ctx: {
			dryRun: o.dryRun ?? false,
			env: o.env ?? { SUPABASE_PROJECT_REF: REF, SUPABASE_ACCESS_TOKEN: 'set' },
			runSql: (/** @type {string} */ s) => {
				scripts.push(s);
				return o.sql ? o.sql(s) : { ok: true, stdout: '', stderr: '' };
			},
			exec: (/** @type {string} */ cmd, /** @type {string[]} */ args) => {
				commands.push([cmd, ...args]);
				return o.exec ? o.exec(cmd, args) : { ok: true, stdout: '[]', stderr: '' };
			},
		},
	};
}

const ALLOW = ['EXAMPLE_TOGGLE_ENABLED'];

test('feature flags: an empty file selects nothing and calls nothing', () => {
	const stage = featureFlagsStage(EMPTY);
	assert.ok(stage.sql?.includes('where false'));
	assert.ok(!stage.sql?.includes('apply_feature_flag'));
	assert.match(stage.note ?? '', /0 declared; a flag absent from prod_config\.json is left untouched/);
});

test('feature flags: each declared flag goes through the definer function as service_role', () => {
	const stage = featureFlagsStage({
		...EMPTY,
		feature_flags: {
			signup_source: { enabled: false, signoff: null },
			live_overlay: { enabled: true, signoff: "https://github.com/Absence0760/threkir/issues/1#it's" },
		},
	});
	const sql = stage.sql ?? '';
	assert.ok(sql.startsWith('set local role service_role;\n'));
	assert.ok(sql.includes("('live_overlay', true, 'https://github.com/Absence0760/threkir/issues/1#it''s'),\n  ('signup_source', false, null)"));
	assert.ok(sql.includes('private.apply_feature_flag(f.name, f.enabled) as action'));
	assert.ok(sql.trimEnd().endsWith('order by flag;'));
});

test('function env: only allow-listed digests are kept from the listing', () => {
	const digest = sha256('true');
	const listing = JSON.stringify([
		{ name: 'EXAMPLE_TOGGLE_ENABLED', value: digest },
		{ name: 'STRIPE_SECRET_KEY', value: 'f'.repeat(64) },
	]);
	assert.deepEqual([...allowListedDigests(listing, ALLOW)], [['EXAMPLE_TOGGLE_ENABLED', digest]]);
	assert.deepEqual([...allowListedDigests('[{"name":"EXAMPLE_TOGGLE_ENABLED","value":"true"}]', ALLOW)], [], 'a non-digest is never compared');
	assert.deepEqual([...allowListedDigests('not json', ALLOW)], []);
});

test('function env: nothing declared touches no CLI', () => {
	const { ctx: c, commands } = ctx({ env: {} });
	const r = functionEnvStage(EMPTY).run?.(c);
	assert.deepEqual(r, { table: { header: ['name', 'enabled', 'action', 'signoff'], rows: [] } });
	assert.deepEqual(commands, []);
});

const TOGGLE_ON = { ...EMPTY, function_env: { EXAMPLE_TOGGLE_ENABLED: { enabled: true, signoff: ISSUE } } };

test('function env: an unchanged digest sets nothing', () => {
	const { ctx: c, commands } = ctx({
		exec: () => ({ ok: true, stdout: JSON.stringify([{ name: 'EXAMPLE_TOGGLE_ENABLED', value: sha256('true') }]), stderr: '' }),
	});
	const r = functionEnvStage(TOGGLE_ON, ALLOW).run?.(c);
	assert.deepEqual(r?.table.rows, [['EXAMPLE_TOGGLE_ENABLED', 'true', 'unchanged', ISSUE]]);
	assert.deepEqual(commands, [['supabase', 'secrets', 'list', '--project-ref', REF, '-o', 'json']]);
});

test('function env: a different or missing digest sets the boolean, or only says so on a dry run', () => {
	const { ctx: c, commands } = ctx({
		exec: (_cmd, args) =>
			args[1] === 'list'
				? { ok: true, stdout: JSON.stringify([{ name: 'EXAMPLE_TOGGLE_ENABLED', value: sha256('false') }]), stderr: '' }
				: { ok: true, stdout: 'Finished supabase secrets set.', stderr: '' },
	});
	const r = functionEnvStage(TOGGLE_ON, ALLOW).run?.(c);
	assert.deepEqual(r?.table.rows, [['EXAMPLE_TOGGLE_ENABLED', 'true', 'set', ISSUE]]);
	assert.deepEqual(commands[1], ['supabase', 'secrets', 'set', 'EXAMPLE_TOGGLE_ENABLED=true', '--project-ref', REF]);

	const dry = ctx({ dryRun: true, exec: () => ({ ok: false, stdout: '', stderr: 'unauthorized' }) });
	const d = functionEnvStage(TOGGLE_ON, ALLOW).run?.(dry.ctx);
	assert.deepEqual(d?.table.rows, [['EXAMPLE_TOGGLE_ENABLED', 'true', 'would set', ISSUE]]);
	assert.equal(dry.commands.length, 1, 'a dry run never sets');
});

test('function env: a failed set fails the stage, and a missing ref or token stops it first', () => {
	const { ctx: c } = ctx({
		exec: (_cmd, args) => (args[1] === 'list' ? { ok: true, stdout: '[]', stderr: '' } : { ok: false, stdout: '', stderr: 'Error: 403\nmore' }),
	});
	assert.match(functionEnvStage(TOGGLE_ON, ALLOW).run?.(c).failed ?? '', /supabase secrets set exited non-zero: Error: 403$/);
	assert.throws(() => functionEnvStage(TOGGLE_ON, ALLOW).run?.(ctx({ env: { SUPABASE_ACCESS_TOKEN: 'x' } }).ctx), /SUPABASE_PROJECT_REF/);
	assert.throws(() => functionEnvStage(TOGGLE_ON, ALLOW).run?.(ctx({ env: { SUPABASE_PROJECT_REF: REF } }).ctx), /SUPABASE_ACCESS_TOKEN/);
	assert.throws(
		() => functionEnvStage({ ...EMPTY, function_env: { STRIPE_SECRET_KEY: { enabled: false, signoff: null } } }).run?.(ctx().ctx),
		/not on the allow-list/,
	);
});

test('web env: reported for the web release, never applied here', () => {
	const { ctx: c, scripts, commands } = ctx();
	const r = webEnvStage({ ...EMPTY, web_env: { PUBLIC_COACH_ENABLED: { enabled: true, signoff: ISSUE } } }).run?.(c);
	assert.deepEqual(r?.table.rows, [['PUBLIC_COACH_ENABLED', 'true', 'applied by release-web', ISSUE]]);
	assert.deepEqual([scripts, commands], [[], []]);
});

test('cron URLs: the ref comes from the environment, not the script', () => {
	const sql = cronArmSql(['race_listings_sweep']);
	assert.ok(sql.startsWith('\\getenv project_ref SUPABASE_PROJECT_REF\nset local role service_role;\n'));
	assert.ok(sql.includes("private.arm_cron_url('race_listings_sweep', format('https://%s.supabase.co/functions/v1/%s', :'project_ref', 'race-listings-sweep'))"));
	assert.ok(sql.includes("set request_id = public.invoke_race_listings_sweep() where fn = 'race_listings_sweep' and action <> 'unchanged'"));
	assert.ok(!sql.includes(REF));
});

test('cron URLs: nothing declared runs nothing', () => {
	const { ctx: c, scripts } = ctx({ env: {} });
	assert.deepEqual(cronUrlsStage(EMPTY).run?.(c).table.rows, []);
	assert.deepEqual(scripts, []);
});

const CRON = { ...EMPTY, cron_urls: ['race_listings_sweep', 'club_verification_recheck'] };

test('cron URLs: an armed entry is invoked once and its first run must answer 2xx', () => {
	const { ctx: c, scripts } = ctx({
		sql: (s) =>
			s.includes('arm_cron_url')
				? { ok: true, stdout: 'fn,action,request_id\nrace_listings_sweep,created,41\nclub_verification_recheck,unchanged,\n', stderr: '' }
				: { ok: true, stdout: 'fn,status\nrace_listings_sweep,200\n', stderr: '' },
	});
	const r = cronUrlsStage(CRON).run?.(c);
	assert.equal(r?.failed, undefined);
	assert.deepEqual(r?.table.rows, [
		['race_listings_sweep', 'race_listings_sweep_url', 'created', '200'],
		['club_verification_recheck', 'club_verification_recheck_url', 'unchanged', 'not invoked'],
	]);
	assert.equal(scripts.length, 2);
	assert.ok(scripts[0].endsWith('commit;\n'), 'the invocation is committed before its outcome is read');
	assert.ok(scripts[1].includes("from (values ('race_listings_sweep', 41::bigint))"));
	assert.ok(scripts[1].includes('private.cron_invoke_outcome(v.id, 30)'));
});

test('cron URLs: a first run that is not 2xx fails the stage, with the status only', () => {
	const { ctx: c } = ctx({
		sql: (s) =>
			s.includes('arm_cron_url')
				? { ok: true, stdout: 'fn,action,request_id\nrace_listings_sweep,updated,7\n', stderr: '' }
				: { ok: true, stdout: 'fn,status\nrace_listings_sweep,401\n', stderr: '' },
	});
	const r = cronUrlsStage({ ...EMPTY, cron_urls: ['race_listings_sweep'] }).run?.(c);
	assert.deepEqual(r?.table.rows, [['race_listings_sweep', 'race_listings_sweep_url', 'updated', '401']]);
	assert.match(r?.failed ?? '', /race_listings_sweep answered 401/);
});

test('cron URLs: an invoker with no work sends nothing, which is not a failed first run', () => {
	const { ctx: c, scripts } = ctx({
		sql: () => ({ ok: true, stdout: 'fn,action,request_id\nevent_refund_sweep,created,\n', stderr: '' }),
	});
	const r = cronUrlsStage({ ...EMPTY, cron_urls: ['event_refund_sweep'] }).run?.(c);
	assert.equal(r?.failed, undefined);
	assert.deepEqual(r?.table.rows, [['event_refund_sweep', 'event_refund_sweep_url', 'created', 'invoker sent nothing']]);
	assert.equal(scripts.length, 1, 'nothing to wait for');
});

test('cron URLs: a dry run rolls back, sends nothing and waits for nothing', () => {
	const { ctx: c, scripts } = ctx({
		dryRun: true,
		sql: () => ({ ok: true, stdout: 'fn,action,request_id\nrace_listings_sweep,created,41\n', stderr: '' }),
	});
	const r = cronUrlsStage({ ...EMPTY, cron_urls: ['race_listings_sweep'] }).run?.(c);
	assert.deepEqual(r?.table.rows, [['race_listings_sweep', 'race_listings_sweep_url', 'would be created', 'not sent (dry run)']]);
	assert.equal(scripts.length, 1);
	assert.ok(scripts[0].endsWith('rollback;\n'));
	assert.throws(() => cronUrlsStage(CRON).run?.(ctx({ env: {} }).ctx), /SUPABASE_PROJECT_REF/);
});

test('ops tasks: one task, ledger first, output discarded, ledger row selected', () => {
	const sql = taskSql({ file: '20271201000001_a.sql', body: 'select 1;' });
	assert.equal(
		sql,
		`select private.begin_ops_task('20271201000001_a', '${sha256('select 1;')}') = 'run' as ops_task_run \\gset\n` +
			'\\if :ops_task_run\n\\o /dev/null\nselect 1;\n\\o\n\\endif\n' +
			"select name, result::text as result from private.ops_task_runs where name = '20271201000001_a';\n",
	);
});

const TASKS = [
	{ file: 'README.md', body: '# x' },
	{ file: '20271201000002_b.sql', body: 'select 2;\n' },
	{ file: '20271201000001_a.sql', body: 'select 1;\n' },
];

test('ops tasks: an already-run task is skipped and a new one runs in its own transaction, oldest first', () => {
	const { ctx: c, scripts } = ctx({
		sql: (s) =>
			s.includes('where name in')
				? { ok: true, stdout: `name,sha256\n20271201000001_a,${sha256('select 1;\n')}\n`, stderr: '' }
				: { ok: true, stdout: 'name,result\n20271201000002_b,"{""n"": 2}"\n', stderr: '' },
	});
	const r = opsTasksStage(TASKS).run?.(c);
	assert.equal(r?.failed, undefined);
	assert.deepEqual(r?.table.rows, [
		['20271201000001_a', sha256('select 1;\n').slice(0, 12), 'already ran', ''],
		['20271201000002_b', sha256('select 2;\n').slice(0, 12), 'ran', '{"n": 2}'],
	]);
	assert.equal(scripts.length, 2);
	assert.ok(scripts[0].endsWith('rollback;\n'), 'reading the ledger writes nothing');
	assert.ok(scripts[1].includes("begin_ops_task('20271201000002_b'") && scripts[1].endsWith('commit;\n'));
});

test('ops tasks: a changed file fails before any task runs', () => {
	const { ctx: c, scripts } = ctx({
		sql: () => ({ ok: true, stdout: `name,sha256\n20271201000002_b,${'0'.repeat(64)}\n`, stderr: '' }),
	});
	const r = opsTasksStage(TASKS).run?.(c);
	assert.match(r?.failed ?? '', /20271201000002_b ran as 000000000000 .* never edited after it runs/);
	assert.equal(scripts.length, 1, 'not even the unchanged older task runs');
});

test('ops tasks: a dry run runs pending tasks and rolls them back; a failure stops the rest', () => {
	const dry = ctx({
		dryRun: true,
		sql: (s) => (s.includes('where name in') ? { ok: true, stdout: 'name,sha256\n', stderr: '' } : { ok: true, stdout: 'name,result\nx,{}\n', stderr: '' }),
	});
	const d = opsTasksStage(TASKS).run?.(dry.ctx);
	assert.deepEqual(d?.table.rows.map((row) => row[2]), ['would run', 'would run']);
	assert.ok(dry.scripts.slice(1).every((s) => s.endsWith('rollback;\n')));

	const failing = ctx({
		sql: (s) =>
			s.includes('where name in')
				? { ok: true, stdout: 'name,sha256\n', stderr: '' }
				: { ok: false, stdout: '', stderr: 'ERROR: boom' },
	});
	const f = opsTasksStage(TASKS).run?.(failing.ctx);
	assert.equal(f?.failed, 'ERROR: boom');
	assert.deepEqual(f?.table.rows.map((row) => row[2]), ['failed, rolled back']);
	assert.equal(failing.scripts.length, 2);
});

test('ops tasks: none committed reads no ledger', () => {
	const { ctx: c, scripts } = ctx();
	assert.deepEqual(opsTasksStage([{ file: 'README.md', body: '' }]).run?.(c).table.rows, []);
	assert.deepEqual(scripts, []);
});

const RETIRED = {
	...EMPTY,
	retired_functions: ['old-import'],
	retired_function_env: ['OLD_IMPORT_ENABLED', 'OLD_IMPORT_UA'],
};

test('retired: the listings are read by slug or name, and anything else is dropped', () => {
	assert.deepEqual([...listedNames('[{"slug":"old-import","name":"Old"},{"name":"OLD_IMPORT_UA"},{"id":1}]')], ['old-import', 'OLD_IMPORT_UA']);
	assert.deepEqual([...listedNames('not json')], []);
	assert.deepEqual([...listedNames('{"slug":"x"}')], []);
});

test('retired: nothing declared touches no CLI', () => {
	const { ctx: c, commands } = ctx();
	assert.deepEqual(retiredStage(EMPTY).run?.(c), { table: { header: ['kind', 'name', 'action'], rows: [] } });
	assert.deepEqual(commands, []);
});

test('retired: a deployed function is deleted and a set secret unset, the rest reported absent', () => {
	const { ctx: c, commands } = ctx({
		exec: (_cmd, args) =>
			args[0] === 'functions' && args[1] === 'list'
				? { ok: true, stdout: JSON.stringify([{ slug: 'old-import' }, { slug: 'kept' }]), stderr: '' }
				: args[0] === 'secrets' && args[1] === 'list'
					? { ok: true, stdout: JSON.stringify([{ name: 'OLD_IMPORT_UA', value: 'f'.repeat(64) }]), stderr: '' }
					: { ok: true, stdout: '', stderr: '' },
	});
	const r = retiredStage(RETIRED).run?.(c);
	assert.equal(r?.failed, undefined);
	assert.deepEqual(r?.table.rows, [
		['function', 'old-import', 'deleted'],
		['secret', 'OLD_IMPORT_ENABLED', 'absent'],
		['secret', 'OLD_IMPORT_UA', 'unset'],
	]);
	assert.deepEqual(commands, [
		['supabase', 'functions', 'list', '--project-ref', REF, '-o', 'json'],
		['supabase', 'functions', 'delete', 'old-import', '--project-ref', REF],
		['supabase', 'secrets', 'list', '--project-ref', REF, '-o', 'json'],
		['supabase', 'secrets', 'unset', 'OLD_IMPORT_UA', '--project-ref', REF],
	]);
});

test('retired: already gone is absent, and a dry run deletes and unsets nothing', () => {
	const gone = ctx();
	assert.deepEqual(retiredStage(RETIRED).run?.(gone.ctx)?.table.rows, [
		['function', 'old-import', 'absent'],
		['secret', 'OLD_IMPORT_ENABLED', 'absent'],
		['secret', 'OLD_IMPORT_UA', 'absent'],
	]);
	const dry = ctx({
		dryRun: true,
		exec: (_cmd, args) => ({ ok: true, stdout: JSON.stringify(args[0] === 'functions' ? [{ slug: 'old-import' }] : [{ name: 'OLD_IMPORT_UA' }]), stderr: '' }),
	});
	assert.deepEqual(retiredStage(RETIRED).run?.(dry.ctx)?.table.rows, [
		['function', 'old-import', 'would delete'],
		['secret', 'OLD_IMPORT_ENABLED', 'absent'],
		['secret', 'OLD_IMPORT_UA', 'would unset'],
	]);
	assert.ok(dry.commands.every((cmd) => cmd[2] === 'list'), 'a dry run only lists');
});

test('retired: a failed list or delete fails the stage, and a missing ref or token stops it first', () => {
	const listFails = ctx({ exec: () => ({ ok: false, stdout: '', stderr: 'Error: 401\nmore' }) });
	assert.match(retiredStage(RETIRED).run?.(listFails.ctx).failed ?? '', /supabase functions list exited non-zero: Error: 401$/);
	const deleteFails = ctx({
		exec: (_cmd, args) =>
			args[1] === 'list' ? { ok: true, stdout: '[{"slug":"old-import"}]', stderr: '' } : { ok: false, stdout: '', stderr: 'Error: 500' },
	});
	const r = retiredStage(RETIRED).run?.(deleteFails.ctx);
	assert.match(r?.failed ?? '', /supabase functions delete old-import exited non-zero: Error: 500/);
	assert.deepEqual(r?.table.rows, [['function', 'old-import', 'failed']]);
	assert.throws(() => retiredStage(RETIRED).run?.(ctx({ env: { SUPABASE_ACCESS_TOKEN: 'x' } }).ctx), /SUPABASE_PROJECT_REF/);
	assert.throws(() => retiredStage(RETIRED).run?.(ctx({ env: { SUPABASE_PROJECT_REF: REF } }).ctx), /SUPABASE_ACCESS_TOKEN/);
});
