import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));

/// Every share lookup that filters a uuid column by a URL segment must reject
/// a non-uuid BEFORE querying.
///
/// Postgres raises 22P02 when a uuid column is compared to a non-uuid, which
/// PostgREST returns as a 400 and supabase-js surfaces in `error` — so
/// `/share/run/hello` took the `upstream_unreachable` branch and emitted the
/// tagged line a CloudWatch metric filter alarms on. The alarm fires at 5
/// occurrences per 5-minute window, so roughly ten junk share URLs in ten
/// minutes paged the on-call engineer from anonymous traffic, and there is no
/// WAF rate rule on /share/* or /og/*. The alarm's own comment claims that
/// line fires "only on a real infra failure … NOT on a clean not-found".
/// Where a lookup first queries by the caller's id: a `.eq('id', …)` filter or
/// an RPC called with `p_id: id`. Profile and recap use the RPC form, and the
/// filter-only scan let both ship without the guard.
function firstIdQuery(src: string): number {
	const hits = [src.indexOf(".eq('id'"), src.search(/\bp_id:\s*id\b/)].filter((i) => i >= 0);
	return hits.length ? Math.min(...hits) : -1;
}

/// Why a lookup source fails the guard, or null when it passes.
function guardProblem(src: string): string | null {
	const query = firstIdQuery(src);
	if (query < 0) return null;
	const guard = src.indexOf('isEntityId(');
	if (guard < 0) return 'queries by a uuid id but never calls isEntityId';
	if (guard > query) return 'calls isEntityId only after it has queried';
	return null;
}

test('every uuid-keyed share lookup guards its id before querying', () => {
	const files = readdirSync(dir).filter(
		(f) => f.startsWith('share_') && f.endsWith('_lookup.ts'),
	);
	assert.ok(files.length >= 5, 'expected the share lookups to be here');

	for (const f of files) {
		const problem = guardProblem(readFileSync(resolve(dir, f), 'utf8'));
		assert.equal(
			problem,
			null,
			`${f} ${problem} — a malformed segment will raise 22P02 and trip the upstream alarm`,
		);
	}
});

test('the guard check sees both query forms, and a guard placed too late', () => {
	assert.equal(guardProblem("q.eq('slug', slug)"), null, 'a slug lookup is not uuid-keyed');
	assert.match(guardProblem("q.eq('id', id)") ?? '', /never calls/);
	assert.match(guardProblem(".rpc('public_profile_by_id', { p_id: id })") ?? '', /never calls/);
	assert.match(
		guardProblem(".rpc('x', { p_id: id }); if (!isEntityId(id)) return") ?? '',
		/only after/,
	);
	assert.equal(guardProblem("if (!isEntityId(id)) return; .rpc('x', { p_id: id })"), null);
	// An owner lookup keyed on a row's own column is not the caller's id.
	assert.equal(guardProblem(".rpc('x', { p_id: run.user_id })"), null);
});
