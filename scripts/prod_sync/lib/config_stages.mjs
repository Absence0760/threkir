// The prod config stages of the production sync (issue #1350, decisions
// § 2430). Pure: each builder takes the parsed config (./prod_config.mjs) and
// returns a Stage for ./stages.mjs; the stages that need more than one
// transaction, or the Supabase CLI, do it through the ctx runStages hands
// them, so tests drive them with fakes.

import { createHash } from 'node:crypto';

import { FUNCTION_ENV_ALLOW, taskName } from './prod_config.mjs';
import { parseCsv, stageScript } from './stages.mjs';

/** @typedef {import('./prod_config.mjs').ProdConfig} ProdConfig */
/** @typedef {import('./stages.mjs').Stage} Stage */
/** @typedef {import('./stages.mjs').StageContext} StageContext */
/** @typedef {import('./stages.mjs').Table} Table */

const PROJECT_REF = /^[a-z0-9]{20}$/;

/** @param {string} s */
const lit = (s) => `'${s.replace(/'/g, "''")}'`;

/** @param {string} text */
export const sha256 = (text) => createHash('sha256').update(text).digest('hex');

/**
 * Upserts each declared flag through private.apply_feature_flag. An absent
 * flag is not in the VALUES list, so it is never touched.
 *
 * @param {ProdConfig} config
 * @returns {Stage}
 */
export function featureFlagsStage(config) {
	const entries = Object.entries(config.feature_flags).sort(([a], [b]) => a.localeCompare(b));
	const note = `${entries.length} declared; a flag absent from prod_config.json is left untouched.`;
	if (entries.length === 0) {
		return { id: 'feature-flags', title: 'Feature flags', note, sql: 'select null::text as flag, null::text as action where false;\n' };
	}
	const values = entries
		.map(([name, t]) => `(${lit(name)}, ${t.enabled}, ${t.signoff ? lit(t.signoff) : 'null'})`)
		.join(',\n  ');
	return {
		id: 'feature-flags',
		title: 'Feature flags',
		note,
		sql:
			// service_role holds no grant on private.feature_flags; it writes
			// through the definer function, which is granted to it alone.
			'set local role service_role;\n' +
			'create temp table prod_config_flags on commit drop as\n' +
			'select f.name as flag, f.enabled, private.apply_feature_flag(f.name, f.enabled) as action, f.signoff\n' +
			`  from (values\n  ${values}\n) as f(name, enabled, signoff);\n` +
			'select flag, enabled, action, signoff from pg_temp.prod_config_flags order by flag;\n',
	};
}

/**
 * The secret digests `supabase secrets list -o json` reports, for the
 * allow-listed names only. Anything else in the listing is dropped unread.
 *
 * @param {string} json
 * @param {readonly string[]} [allow]
 * @returns {Map<string, string>}
 */
export function allowListedDigests(json, allow = FUNCTION_ENV_ALLOW) {
	/** @type {Map<string, string>} */
	const digests = new Map();
	let parsed;
	try {
		parsed = JSON.parse(json);
	} catch {
		return digests;
	}
	if (!Array.isArray(parsed)) return digests;
	for (const item of parsed) {
		if (!item || typeof item !== 'object') continue;
		const name = item.name;
		const value = item.value;
		if (typeof name !== 'string' || !allow.includes(name)) continue;
		if (typeof value === 'string' && /^[0-9a-f]{64}$/.test(value)) digests.set(name, value);
	}
	return digests;
}

/**
 * Sets each declared Edge Function toggle with `supabase secrets set`. Reads
 * the current state only as the CLI's digests, compared with the digest of
 * the value it would write; when the CLI reports no digest it just sets. The
 * only value it ever prints is the boolean it writes.
 *
 * @param {ProdConfig} config
 * @param {readonly string[]} [allow]
 * @returns {Stage}
 */
export function functionEnvStage(config, allow = FUNCTION_ENV_ALLOW) {
	const entries = Object.entries(config.function_env).sort(([a], [b]) => a.localeCompare(b));
	const header = ['name', 'enabled', 'action', 'signoff'];
	return {
		id: 'function-env',
		title: 'Edge Function env toggles',
		note: `${entries.length} declared; set with supabase secrets set, read back only as digests. A toggle absent from prod_config.json is left untouched.`,
		run(ctx) {
			if (entries.length === 0) return { table: { header, rows: [] } };
			for (const [name] of entries) {
				if (!allow.includes(name)) throw new Error(`function_env.${name} is not on the allow-list`);
			}
			const ref = ctx.env.SUPABASE_PROJECT_REF ?? '';
			if (!PROJECT_REF.test(ref)) throw new Error('SUPABASE_PROJECT_REF is unset or not a project ref');
			if (!ctx.env.SUPABASE_ACCESS_TOKEN) throw new Error('SUPABASE_ACCESS_TOKEN is unset');

			const listed = ctx.exec('supabase', ['secrets', 'list', '--project-ref', ref, '-o', 'json']);
			const current = listed.ok ? allowListedDigests(listed.stdout, allow) : new Map();
			/** @type {string[][]} */
			const rows = [];
			/** @type {string[]} */
			const pending = [];
			for (const [name, t] of entries) {
				const value = t.enabled ? 'true' : 'false';
				if (current.get(name) === sha256(value)) {
					rows.push([name, value, 'unchanged', t.signoff ?? '']);
				} else {
					rows.push([name, value, ctx.dryRun ? 'would set' : 'set', t.signoff ?? '']);
					pending.push(`${name}=${value}`);
				}
			}
			if (pending.length > 0 && !ctx.dryRun) {
				const set = ctx.exec('supabase', ['secrets', 'set', ...pending, '--project-ref', ref]);
				if (!set.ok) {
					return {
						table: { header, rows },
						failed: `supabase secrets set exited non-zero: ${firstLine(set.stderr)}`,
					};
				}
			}
			return { table: { header, rows } };
		},
	};
}

/**
 * Lists the declared web flags. release-web.yml applies them at build time
 * (scripts/prod_sync/web_env.mjs); the backend release only validates them.
 *
 * @param {ProdConfig} config
 * @returns {Stage}
 */
export function webEnvStage(config) {
	const entries = Object.entries(config.web_env).sort(([a], [b]) => a.localeCompare(b));
	return {
		id: 'web-env',
		title: 'Web build flags',
		note: `${entries.length} declared; validated here, written into apps/web/.env by the next web release. A flag absent from prod_config.json keeps its repo secret.`,
		run: () => ({
			table: {
				header: ['name', 'enabled', 'action', 'signoff'],
				rows: entries.map(([name, t]) => [name, String(t.enabled), 'applied by release-web', t.signoff ?? '']),
			},
		}),
	};
}

/**
 * The SQL that arms each declared cron function: creates or updates its
 * `<fn>_url` Vault entry, and queues one invocation for an entry that was
 * created or changed. The project ref comes from the environment through
 * psql's \getenv, so it is never in the script text.
 *
 * @param {string[]} fns
 */
export function cronArmSql(fns) {
	const arms = fns
		.map(
			(fn, i) =>
				`insert into pg_temp.prod_config_cron (seq, fn, action)\n` +
				`select ${i + 1}, ${lit(fn)}, private.arm_cron_url(${lit(fn)}, format('https://%s.supabase.co/functions/v1/%s', :'project_ref', ${lit(fn.replace(/_/g, '-'))}));\n` +
				`update pg_temp.prod_config_cron set request_id = public.invoke_${fn}() where fn = ${lit(fn)} and action <> 'unchanged';\n`,
		)
		.join('');
	return (
		'\\getenv project_ref SUPABASE_PROJECT_REF\n' +
		'set local role service_role;\n' +
		'create temp table prod_config_cron (seq int, fn text, action text, request_id bigint) on commit drop;\n' +
		arms +
		'select fn, action, request_id from pg_temp.prod_config_cron order by seq;\n'
	);
}

/**
 * pg_net sends a queued request only once its transaction commits, so the
 * outcome is read in a second one.
 *
 * @param {[string, string][]} invoked [fn, request id]
 */
export function cronOutcomeSql(invoked) {
	const values = invoked.map(([fn, id]) => `(${lit(fn)}, ${Number.parseInt(id, 10)}::bigint)`).join(', ');
	return (
		'set local role service_role;\n' +
		`select v.fn, private.cron_invoke_outcome(v.id, 30) as status from (values ${values}) as v(fn, id);\n`
	);
}

/**
 * Arms each declared cron function and, for one it created or changed,
 * checks the first invocation answered 2xx. Reports status codes only.
 *
 * @param {ProdConfig} config
 * @returns {Stage}
 */
export function cronUrlsStage(config) {
	const fns = [...config.cron_urls];
	const header = ['function', 'vault_entry', 'action', 'first_run'];
	return {
		id: 'cron-urls',
		title: 'Cron URL entries',
		note: `${fns.length} declared; an entry absent from prod_config.json is left untouched, and an unchanged one is not invoked.`,
		run(ctx) {
			if (fns.length === 0) return { table: { header, rows: [] } };
			if (!PROJECT_REF.test(ctx.env.SUPABASE_PROJECT_REF ?? '')) {
				throw new Error('SUPABASE_PROJECT_REF is unset or not a project ref');
			}
			const armed = ctx.runSql(stageScript(cronArmSql(fns), { dryRun: ctx.dryRun }));
			if (!armed.ok) return { table: { header, rows: [] }, failed: armed.stderr };
			const arms = parseCsv(armed.stdout).rows;
			const invoked = arms.filter((r) => r[2] !== '').map((r) => /** @type {[string, string]} */ ([r[0], r[2]]));

			/** @type {Map<string, string>} */
			const outcome = new Map();
			if (!ctx.dryRun && invoked.length > 0) {
				const polled = ctx.runSql(stageScript(cronOutcomeSql(invoked), { dryRun: false }));
				if (!polled.ok) return { table: { header, rows: [] }, failed: polled.stderr };
				for (const [fn, status] of parseCsv(polled.stdout).rows) outcome.set(fn, status);
			}
			const rows = arms.map(([fn, action, requestId]) => [
				fn,
				`${fn}_url`,
				ctx.dryRun && action !== 'unchanged' ? `would be ${action}` : action,
				requestId !== ''
					? ctx.dryRun
						? 'not sent (dry run)'
						: (outcome.get(fn) ?? 'missing')
					: action === 'unchanged'
						? 'not invoked'
						: 'invoker sent nothing',
			]);
			// An invoker may send nothing when it has no work (the refund sweep
			// with no order to reconcile); that is not a failed first run.
			const bad = ctx.dryRun ? [] : rows.filter((r) => r[3] !== 'not invoked' && r[3] !== 'invoker sent nothing' && !/^2[0-9]{2}$/.test(r[3]));
			return {
				table: { header, rows },
				failed:
					bad.length > 0
						? `the first run of ${bad.map((r) => `${r[0]} answered ${r[3]}`).join(', ')}; the Vault entry is armed, so the schedule keeps calling it. Read the function's logs.`
						: undefined,
			};
		},
	};
}

/**
 * One task's transaction: records it in the ledger, runs its SQL with its
 * output discarded, and selects the ledger row. The ledger refuses a task
 * whose file changed after it ran, so a race with another sync fails rather
 * than running twice.
 *
 * @param {{ file: string, body: string }} task
 */
export function taskSql(task) {
	const name = taskName(task.file);
	return (
		`select private.begin_ops_task(${lit(name)}, ${lit(sha256(task.body))}) = 'run' as ops_task_run \\gset\n` +
		'\\if :ops_task_run\n' +
		'\\o /dev/null\n' +
		task.body +
		(task.body.endsWith('\n') ? '' : '\n') +
		'\\o\n' +
		'\\endif\n' +
		`select name, result::text as result from private.ops_task_runs where name = ${lit(name)};\n`
	);
}

/**
 * Runs every committed task the ledger has not recorded, oldest first, each
 * in its own transaction. Tasks run as the release's connection role, as a
 * migration does, since a task is reviewed like one and may need the same
 * rights.
 *
 * @param {{ file: string, body: string }[]} tasks
 * @returns {Stage}
 */
export function opsTasksStage(tasks) {
	const sorted = tasks.filter((t) => t.file !== 'README.md').sort((a, b) => a.file.localeCompare(b.file));
	const header = ['task', 'sha256', 'action', 'result'];
	return {
		id: 'ops-tasks',
		title: 'One-off ops tasks',
		note: `${sorted.length} committed; each runs once and is recorded in private.ops_task_runs.`,
		run(ctx) {
			if (sorted.length === 0) return { table: { header, rows: [] } };
			const names = sorted.map((t) => lit(taskName(t.file))).join(', ');
			const ledger = ctx.runSql(
				stageScript(`select name, sha256 from private.ops_task_runs where name in (${names}) order by name;\n`, { dryRun: true }),
			);
			if (!ledger.ok) return { table: { header, rows: [] }, failed: ledger.stderr };
			const ran = new Map(parseCsv(ledger.stdout).rows.map(([n, s]) => [n, s]));

			/** @type {string[][]} */
			const rows = [];
			for (const task of sorted) {
				const name = taskName(task.file);
				const digest = sha256(task.body);
				const recorded = ran.get(name);
				if (recorded !== undefined && recorded !== digest) {
					rows.push([name, digest.slice(0, 12), 'changed after it ran', '']);
					return {
						table: { header, rows },
						failed: `ops task ${name} ran as ${recorded.slice(0, 12)} and its file is now ${digest.slice(0, 12)}; a task is never edited after it runs. Restore it and add a new task.`,
					};
				}
			}
			for (const task of sorted) {
				const name = taskName(task.file);
				const digest = sha256(task.body);
				if (ran.has(name)) {
					rows.push([name, digest.slice(0, 12), 'already ran', '']);
					continue;
				}
				const r = ctx.runSql(stageScript(taskSql(task), { dryRun: ctx.dryRun }));
				if (!r.ok) {
					rows.push([name, digest.slice(0, 12), 'failed, rolled back', '']);
					return { table: { header, rows }, failed: r.stderr };
				}
				const result = parseCsv(r.stdout).rows[0]?.[1] ?? '';
				rows.push([name, digest.slice(0, 12), ctx.dryRun ? 'would run' : 'ran', result.slice(0, 200)]);
			}
			return { table: { header, rows } };
		},
	};
}

/** @param {string} text */
const firstLine = (text) => (text.trim().split('\n')[0] ?? '').slice(0, 300);
