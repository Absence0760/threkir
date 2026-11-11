// Unit tests for production config as code (issue #1350, decisions § 2430):
// the shape of apps/backend/ops/prod_config.json, the sign-off rule, the
// rules checked against the repo, the derivations those rules read, the
// web .env overlay, and the static half of the ops task rules. The last test
// runs the guard over the committed tree.
// Run: node --test scripts/prod_sync/lib/prod_config.test.mjs

import assert from 'node:assert/strict';
import test from 'node:test';

import { checkProdConfig } from '../config.mjs';
import {
	FUNCTION_ENV_ALLOW,
	checkAgainstRepo,
	checkTasks,
	cronFunctionsFromMigrations,
	flagNamesFromMigrations,
	functionEnvReads,
	overlayDotenv,
	parseProdConfig,
	signoffProblem,
	webFlagsFrom,
} from './prod_config.mjs';

const EMPTY = { feature_flags: {}, function_env: {}, web_env: {}, cron_urls: [], retired_functions: [], retired_function_env: [] };
const ISSUE = 'https://github.com/Absence0760/threkir/issues/1097#issuecomment-1234567';

/** @param {Record<string, unknown>} over */
const parse = (over) => parseProdConfig({ ...EMPTY, ...over });

const REPO = {
	flagNames: new Set(['live_overlay', 'signup_source']),
	functionEnvRead: new Set(['EXAMPLE_TOGGLE_ENABLED', 'CRON_SECRET']),
	webFlags: new Set(['PUBLIC_COACH_ENABLED', 'PUBLIC_AI_PLAN_ENABLED', 'PUBLIC_COURSE_DRIVE_ENABLED']),
	cronFunctions: new Set(['race_listings_sweep', 'event_refund_sweep']),
	functionDirs: new Set(['race-results-import', 'export-data']),
	docExists: (/** @type {string} */ p) => p === 'docs/ops/deployment.md',
};

const ALLOW = ['EXAMPLE_TOGGLE_ENABLED'];

/**
 * @param {Record<string, unknown>} over
 * @param {typeof REPO} [repo]
 * @param {readonly string[]} [allow]
 */
const repoCheck = (over, repo = REPO, allow = ALLOW) => {
	const { config, problems } = parse(over);
	assert.deepEqual(problems, []);
	return checkAgainstRepo(/** @type {any} */ (config), repo, allow);
};

test('the committed shape: four sections, all required, nothing else', () => {
	assert.deepEqual(parseProdConfig(EMPTY), { config: EMPTY, problems: [] });
	assert.match(parseProdConfig({ ...EMPTY, extra: {} }).problems[0], /unknown section\(s\) extra/);
	assert.match(parseProdConfig({ feature_flags: {} }).problems[0], /missing section\(s\) function_env, web_env, cron_urls/);
	assert.deepEqual(parseProdConfig([]).problems, ['prod_config.json must be an object']);
	assert.match(parse({ feature_flags: [] }).problems[0], /feature_flags must be an object/);
	assert.match(parse({ cron_urls: {} }).problems[0], /cron_urls must be a list/);
});

test('an entry is { enabled, signoff } and nothing more', () => {
	assert.match(parse({ feature_flags: { live_overlay: true } }).problems[0], /must be an object/);
	assert.match(parse({ feature_flags: { live_overlay: { enabled: 'yes' } } }).problems[0], /enabled must be true or false/);
	assert.match(parse({ feature_flags: { live_overlay: { enabled: false, by: 'me' } } }).problems[0], /unknown key\(s\) by/);
	assert.match(parse({ feature_flags: { 'Live-Overlay': { enabled: false } } }).problems[0], /not a valid name/);
	assert.match(parse({ function_env: { parkrun: { enabled: false } } }).problems[0], /not a valid name/);
	assert.deepEqual(parse({ feature_flags: { live_overlay: { enabled: false } } }).config?.feature_flags, {
		live_overlay: { enabled: false, signoff: null },
	});
});

test('enabling needs a sign-off that links the approval', () => {
	assert.match(parse({ feature_flags: { live_overlay: { enabled: true } } }).problems[0], /enabled with no signoff/);
	assert.match(parse({ web_env: { PUBLIC_COACH_ENABLED: { enabled: true, signoff: '' } } }).problems[0], /non-empty string/);
	assert.match(
		parse({ function_env: { EXAMPLE_TOGGLE_ENABLED: { enabled: true, signoff: 'they said yes' } } }).problems[0],
		/neither a GitHub issue/,
	);
	assert.deepEqual(parse({ feature_flags: { live_overlay: { enabled: true, signoff: ISSUE } } }).problems, []);
	for (const ok of [
		ISSUE,
		'https://github.com/Absence0760/threkir/issues/1097',
		'https://github.com/Absence0760/threkir/pull/1351',
		'https://github.com/Absence0760/project-mgmt/issues/10#issuecomment-99',
		'reviews/legal-live-overlay.md',
		'docs/features/clubs.md#signoff',
	]) {
		assert.equal(signoffProblem(ok), null, ok);
	}
	for (const bad of [
		'https://github.com/someone/threkir/issues/1',
		'http://github.com/Absence0760/threkir/issues/1',
		'https://example.com/approval',
		'docs/../secrets.md',
		'reviews/memo.txt',
	]) {
		assert.notEqual(signoffProblem(bad), null, bad);
	}
});

test('cron_urls is a list of distinct function names', () => {
	assert.match(parse({ cron_urls: ['race-listings-sweep'] }).problems[0], /not a function name/);
	assert.match(parse({ cron_urls: ['race_listings_sweep', 'race_listings_sweep'] }).problems[0], /twice/);
	assert.deepEqual(parse({ cron_urls: ['race_listings_sweep'] }).config?.cron_urls, ['race_listings_sweep']);
});

test('every declared flag is one a migration defines', () => {
	assert.deepEqual(repoCheck({ feature_flags: { live_overlay: { enabled: false } } }).problems, []);
	assert.match(repoCheck({ feature_flags: { live_overlayy: { enabled: false } } }).problems[0], /no migration reads or seeds/);
});

test('function env takes only allow-listed booleans an Edge Function reads', () => {
	assert.deepEqual(repoCheck({ function_env: { EXAMPLE_TOGGLE_ENABLED: { enabled: false } } }).problems, []);
	assert.match(repoCheck({ function_env: { CRON_SECRET: { enabled: false } } }).problems[0], /not on the allow-list/);
	assert.match(
		repoCheck({ function_env: { AI_PLAN_ENABLED: { enabled: false } } }).problems[0],
		/no Edge Function reads it; it is set in the coach Lambda/,
	);
	assert.match(repoCheck({ function_env: { WEIGHT_FLUID_ENABLED: { enabled: false } } }).problems[0], /mobile dotenv/);
	const stale = repoCheck({}, { ...REPO, functionEnvRead: new Set() });
	assert.match(stale.problems[0], /FUNCTION_ENV_ALLOW names EXAMPLE_TOGGLE_ENABLED, which no Edge Function reads/);
});

test('web env takes only PUBLIC_* gates the build reads', () => {
	assert.deepEqual(repoCheck({ web_env: { PUBLIC_COURSE_DRIVE_ENABLED: { enabled: false } } }).problems, []);
	assert.match(repoCheck({ web_env: { PUBLIC_SUPABASE_URL: { enabled: false } } }).problems[0], /not a PUBLIC_\* flag/);
});

test('a paired web flag notes its server half, and a Coach-only flag needs the Coach on', () => {
	const r = repoCheck({ web_env: { PUBLIC_AI_PLAN_ENABLED: { enabled: true, signoff: ISSUE } } });
	assert.deepEqual(r.problems, []);
	assert.match(r.notices[0], /set its other half AI_PLAN_ENABLED to match in the coach Lambda/);
	const off = repoCheck({
		web_env: {
			PUBLIC_AI_PLAN_ENABLED: { enabled: true, signoff: ISSUE },
			PUBLIC_COACH_ENABLED: { enabled: false },
		},
	});
	assert.match(off.problems[0], /PUBLIC_AI_PLAN_ENABLED is on but web_env\.PUBLIC_COACH_ENABLED is off/);
});

test('a docs sign-off must exist; a reviews one cannot be checked', () => {
	assert.deepEqual(repoCheck({ feature_flags: { live_overlay: { enabled: true, signoff: 'docs/ops/deployment.md#x' } } }).problems, []);
	assert.match(
		repoCheck({ feature_flags: { live_overlay: { enabled: true, signoff: 'docs/ops/nope.md' } } }).problems[0],
		/does not exist/,
	);
	assert.deepEqual(repoCheck({ feature_flags: { live_overlay: { enabled: true, signoff: 'reviews/memo.md' } } }).problems, []);
});

test('a cron function needs an invoker reading its Vault URL entry', () => {
	assert.deepEqual(repoCheck({ cron_urls: ['event_refund_sweep'] }).problems, []);
	assert.match(repoCheck({ cron_urls: ['weekly_digest'] }).problems[0], /no migration defines public\.invoke_weekly_digest/);
});

test('the derivations read reads, seeds, invokers and env gets, not comments', () => {
	const migrations = [
		"-- where f.name = 'commented_out'\nselect (select f.enabled from private.feature_flags f\n  where f.name = 'route_photo_orphan_sweep');",
		"insert into private.feature_flags (name, enabled)\nvalues ('recurrence_utc_clock_legacy', true) on conflict do nothing;",
		"select coalesce((select enabled from private.feature_flags where name = 'live_overlay'), false);",
		"create or replace function public.invoke_race_listings_sweep()\nreturns bigint as $$\nbegin\n  select 1 from vault.decrypted_secrets where name = 'race_listings_sweep_url';\nend;\n$$;",
		"create or replace function public.invoke_weekly_digest()\nreturns bigint as $$ select 1 $$;",
	];
	assert.deepEqual([...flagNamesFromMigrations(migrations)].sort(), ['live_overlay', 'recurrence_utc_clock_legacy', 'route_photo_orphan_sweep']);
	assert.deepEqual([...cronFunctionsFromMigrations(migrations)], ['race_listings_sweep']);
	assert.deepEqual([...functionEnvReads(["if (Deno.env.get('EXAMPLE_TOGGLE_ENABLED') === 'true')", 'Deno.env.get("X_Y")'])], [
		'EXAMPLE_TOGGLE_ENABLED',
		'X_Y',
	]);
	const yml = '  cat <<EOF\n  PUBLIC_A_ENABLED=${PUBLIC_A_ENABLED}\n  EOF\n  PUBLIC_B_ENABLED: x';
	const modules = [
		"import { PUBLIC_A_ENABLED } from '$app/env/public';",
		"export const b = import.meta.env.PUBLIC_B_ENABLED;",
	];
	assert.deepEqual([...webFlagsFrom(modules, yml)], ['PUBLIC_A_ENABLED'], 'a flag the build never writes is not one this file can set');
});

test('the web overlay replaces only declared flags and appends a missing one', () => {
	const dotenv = 'PUBLIC_SUPABASE_URL=https://x\nPUBLIC_COACH_ENABLED=\nPUBLIC_AI_PLAN_ENABLED=true\n';
	assert.deepEqual(overlayDotenv(dotenv, {}), { text: dotenv, applied: [] });
	const r = overlayDotenv(dotenv, {
		PUBLIC_COACH_ENABLED: { enabled: true, signoff: ISSUE },
		PUBLIC_AI_PLAN_ENABLED: { enabled: false, signoff: null },
		PUBLIC_COURSE_DRIVE_ENABLED: { enabled: false, signoff: null },
	});
	assert.equal(
		r.text,
		'PUBLIC_SUPABASE_URL=https://x\nPUBLIC_COACH_ENABLED=true\nPUBLIC_AI_PLAN_ENABLED=false\nPUBLIC_COURSE_DRIVE_ENABLED=false\n',
	);
	assert.deepEqual(r.applied, ['PUBLIC_COACH_ENABLED', 'PUBLIC_AI_PLAN_ENABLED', 'PUBLIC_COURSE_DRIVE_ENABLED']);
});

test('task files are named, unique, plain SQL and leave the transaction alone', () => {
	assert.deepEqual(
		checkTasks([
			{ file: 'README.md', body: '' },
			{ file: '20271201000001_backfill_names.sql', body: "select private.set_ops_task_result(jsonb_build_object('n', 1));\n" },
		]),
		[],
	);
	assert.match(checkTasks([{ file: 'backfill.sql', body: 'select 1;' }])[0], /not <14-digit timestamp>_<snake_name>\.sql/);
	assert.match(
		checkTasks([
			{ file: '20271201000001_a.sql', body: 'select 1;' },
			{ file: '20271201000001_b.sql', body: 'select 1;' },
		])[0],
		/reuses the timestamp of 20271201000001_a\.sql/,
	);
	assert.match(checkTasks([{ file: '20271201000001_a.sql', body: '-- nothing\n' }])[0], /has no SQL/);
	assert.match(checkTasks([{ file: '20271201000001_a.sql', body: '\\o /tmp/x\nselect 1;' }])[0], /psql meta-command/);
	assert.match(checkTasks([{ file: '20271201000001_a.sql', body: 'select 1;\ncommit;\n' }])[0], /controls its own transaction/);
	assert.match(checkTasks([{ file: '20271201000001_a.sql', body: 'begin;\nselect 1;' }])[0], /controls its own transaction/);
});

test('the allow-list holds only boolean toggles', () => {
	for (const name of FUNCTION_ENV_ALLOW) assert.match(name, /_ENABLED$|_GATE$/);
});

test('the committed config and tasks pass the guard', () => {
	const { config, problems, tasks } = checkProdConfig();
	assert.deepEqual(problems, []);
	assert.notEqual(config, null);
	assert.ok(tasks.some((t) => t.file === 'README.md'), 'apps/backend/ops/tasks/README.md says how a task is written');
});

test('retired names are lists of function directories and env names, each once', () => {
	assert.deepEqual(parse({ retired_functions: ['old-import'], retired_function_env: ['OLD_UA'] }).config?.retired_functions, ['old-import']);
	assert.match(parse({ retired_functions: 'old-import' }).problems[0], /must be a list/);
	assert.match(parse({ retired_functions: ['Old_Import'] }).problems[0], /not a name like parkrun-import/);
	assert.match(parse({ retired_functions: ['old-import', 'old-import'] }).problems[0], /twice/);
	assert.match(parse({ retired_function_env: ['old-ua'] }).problems[0], /not a name like PARKRUN_USER_AGENT/);
});

test('a retirement the repo still ships is refused', () => {
	assert.deepEqual(repoCheck({ retired_functions: ['old-import'], retired_function_env: ['OLD_UA'] }).problems, []);
	assert.match(repoCheck({ retired_functions: ['export-data'] }).problems[0], /still has a directory under supabase\/functions/);
	assert.match(repoCheck({ retired_function_env: ['CRON_SECRET'] }).problems[0], /still reads with Deno\.env\.get/);
	assert.match(
		repoCheck({ function_env: { EXAMPLE_TOGGLE_ENABLED: { enabled: false } }, retired_function_env: ['EXAMPLE_TOGGLE_ENABLED'] }, { ...REPO, functionEnvRead: new Set(['EXAMPLE_TOGGLE_ENABLED']) }).problems.join('\n'),
		/function_env also sets/,
	);
});
