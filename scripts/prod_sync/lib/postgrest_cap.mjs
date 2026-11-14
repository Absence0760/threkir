// The PostgREST row cap check (decisions § 2531): the keyset walk on
// web, Deno and Dart (POSTGREST_MAX_ROWS / kPostgrestMaxRows) ends on a page
// shorter than the declared `db.max-rows` without a confirming read, which is
// sound only while the server's real cap is at least that. config.toml pins
// the value for the local and CI stacks and the keyset_page suites pin the
// clients to config.toml; this stage closes the last gap, the hosted project,
// whose "Max rows" is a dashboard setting nothing else reads. It writes
// nothing: a lower production cap fails the release so the setting is raised,
// rather than every walk quietly truncating at it.

/** @typedef {import('./stages.mjs').Stage} Stage */

const PROJECT_REF = /^[a-z0-9]{20}$/;

/**
 * `max_rows` under `[api]` in a config.toml, or null when it is not pinned.
 *
 * @param {string} toml
 * @returns {number | null}
 */
export function pinnedMaxRows(toml) {
	const api = /^\[api\]\r?\n([\s\S]*?)(?=^\[|(?![\s\S]))/m.exec(toml)?.[1];
	if (api === undefined) return null;
	const m = /^max_rows\s*=\s*(\d+)\s*(?:#.*)?$/m.exec(api);
	return m ? Number(m[1]) : null;
}

/**
 * The production cap the reader script printed: one non-negative integer
 * line, nothing else, so a response that carried anything more is refused
 * rather than echoed into the step summary.
 *
 * @param {string} stdout
 * @returns {number | null}
 */
export function parseReadCap(stdout) {
	const text = stdout.trim();
	return /^\d+$/.test(text) ? Number(text) : null;
}

/**
 * Reads production's `max_rows` through `reader` (a node script printing only
 * that integer) and fails when it is below `pinned`. Read-only, so a dry run
 * checks too.
 *
 * @param {number | null} pinned
 * @param {string} reader absolute path of the reader script
 * @returns {Stage}
 */
export function postgrestCapStage(pinned, reader) {
	const header = ['setting', 'pinned', 'production', 'verdict'];
	return {
		id: 'postgrest-max-rows',
		title: 'PostgREST row cap',
		note: "Read-only. The keyset walk ends on a page shorter than config.toml's [api] max_rows, so production's cap must not be lower.",
		run(ctx) {
			if (pinned === null || pinned <= 0) throw new Error('apps/backend/supabase/config.toml pins no [api] max_rows');
			if (!PROJECT_REF.test(ctx.env.SUPABASE_PROJECT_REF ?? '')) {
				throw new Error('SUPABASE_PROJECT_REF is unset or not a project ref');
			}
			if (!ctx.env.SUPABASE_ACCESS_TOKEN) throw new Error('SUPABASE_ACCESS_TOKEN is unset');
			const read = ctx.exec('node', [reader]);
			const prod = read.ok ? parseReadCap(read.stdout) : null;
			if (prod === null) {
				return {
					table: { header, rows: [['max_rows', String(pinned), 'unread', 'failed']] },
					failed: `the production max_rows could not be read: ${(read.stderr || 'no integer printed').trim().split('\n')[0]}`,
				};
			}
			const ok = prod >= pinned;
			return {
				table: { header, rows: [['max_rows', String(pinned), String(prod), ok ? 'ok' : 'below the pin']] },
				...(ok
					? {}
					: {
							failed:
								`production caps a response at ${prod} rows, below the ${pinned} the clients' keyset walk relies on, ` +
								`so every walk would stop early and report itself complete. Raise the project's Data API "Max rows" to at least ${pinned}.`,
						}),
			};
		},
	};
}
