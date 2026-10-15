// Keyset ("cursor") pagination for the load-more lists.
//
// Pure — no Svelte / Supabase dependencies, so it runs under `npx tsx --test`.
// Mirrored byte-for-byte in behaviour by
// `packages/core_models/lib/src/keyset_page.dart` (registered in
// docs/architecture/parity_pairs.md).
//
// An OFFSET names a position, and a position moves whenever the list changes
// between two reads: delete a row from page 1 and offset 50 now starts at what
// was row 51, so row 50 is never shown; insert one above the boundary and the
// last row of page 1 comes back on page 2. A keyset names the last ROW shown —
// its sort values, ending on a unique column so the order is total — and asks
// for the rows strictly after it, which no insert or delete elsewhere in the
// list can move.

export type KeysetValue = string | number | boolean | null;

/// The last row's values for each key of the order, in key order.
export type KeysetCursor = readonly KeysetValue[];

/// One column of a total order, spelled exactly as the `.order()` call that
/// sorts by it. `nullsFirst` is required rather than defaulted because the two
/// clients default it differently (postgrest-js omits it and Postgres puts
/// nulls first on a descending key; postgrest-dart always sends nullslast), so
/// a key spec that left it out would mean two different orders.
export interface KeysetKey {
	readonly column: string;
	readonly ascending: boolean;
	readonly nullsFirst: boolean;
}

/// One load-more page: the rows to show, and the cursor for the next read —
/// null when the server returned a short page, i.e. the list is exhausted.
/// `next` comes from the last row the SERVER returned, not the last row
/// rendered, so a row the caller drops after the read (a follower whose
/// profile is gone) neither ends the list early nor shifts the next page.
export interface KeysetPage<T> {
	rows: T[];
	next: KeysetCursor | null;
}

const COLUMN = /^[a-z_][a-z0-9_]*$/;

function checkColumn(column: string): string {
	if (!COLUMN.test(column)) throw new Error(`keyset: not a plain column name: ${column}`);
	return column;
}

/// A PostgREST literal, always double-quoted: a timestamp carries `:` and `.`,
/// both reserved inside a logic tree, and quoting every value is simpler than
/// deciding which need it.
function literal(value: string | number | boolean): string {
	if (typeof value === 'number' && !Number.isFinite(value)) {
		throw new Error(`keyset: not a finite number: ${value}`);
	}
	return `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function equalTerm(key: KeysetKey, value: KeysetValue): string {
	const col = checkColumn(key.column);
	return value === null ? `${col}.is.null` : `${col}.eq.${literal(value)}`;
}

/// Rows whose `key` sorts strictly after `value`, or null when none can.
function afterTerm(key: KeysetKey, value: KeysetValue): string | null {
	const col = checkColumn(key.column);
	if (value === null) return key.nullsFirst ? `${col}.not.is.null` : null;
	const strict = `${col}.${key.ascending ? 'gt' : 'lt'}.${literal(value)}`;
	return key.nullsFirst ? strict : `or(${strict},${col}.is.null)`;
}

/// The filter for "strictly after `cursor` in the order `keys`", as the body
/// of a PostgREST `.or(...)`: the row-value comparison
/// `(k1, k2, …) > (c1, c2, …)` expanded into "k1 after c1, or k1 equal and k2
/// after c2, or …", with each key's direction and null placement honoured.
/// Null when no row can follow the cursor, which the caller answers with an
/// empty page rather than an unfiltered read.
export function keysetAfter(keys: readonly KeysetKey[], cursor: KeysetCursor): string | null {
	if (keys.length === 0) throw new Error('keyset: an order needs at least one key');
	if (cursor.length !== keys.length) {
		throw new Error(`keyset: cursor has ${cursor.length} values for ${keys.length} keys`);
	}
	const alternatives: string[] = [];
	for (let i = 0; i < keys.length; i++) {
		const after = afterTerm(keys[i], cursor[i]);
		if (after === null) continue;
		const terms = [...keys.slice(0, i).map((k, j) => equalTerm(k, cursor[j])), after];
		alternatives.push(terms.length === 1 ? terms[0] : `and(${terms.join(',')})`);
	}
	return alternatives.length === 0 ? null : alternatives.join(',');
}

/// The cursor for `row`: its value for each key, read as the server sent it.
/// A timestamp must stay the server's string — re-serialising it through
/// `Date` drops the microseconds, and the equality arm then matches nothing.
export function keysetCursor(keys: readonly KeysetKey[], row: object): KeysetCursor {
	return keys.map((k) => {
		const value = (row as Record<string, unknown>)[k.column];
		if (value === undefined) throw new Error(`keyset: row has no ${k.column}`);
		if (
			value !== null &&
			typeof value !== 'string' &&
			typeof value !== 'number' &&
			typeof value !== 'boolean'
		) {
			throw new Error(`keyset: ${k.column} is not a scalar`);
		}
		return value;
	});
}

/// The next cursor after a raw server page of `limit` rows: the last row's
/// cursor when the page was full, null when it was short.
export function nextCursor(
	keys: readonly KeysetKey[],
	page: readonly object[],
	limit: number,
): KeysetCursor | null {
	if (page.length < limit || page.length === 0) return null;
	return keysetCursor(keys, page[page.length - 1]);
}

/// `shown` followed by the rows of `page` not already in it, compared on
/// `keyOf`; the row already on screen keeps its place.
///
/// Keyset paging makes the boundary overlap of an offset impossible, so this
/// is no longer what stops a repeat on an ordinary insert. It stays because a
/// row can still MOVE past the cursor between two reads when its own sort
/// value changes: a member who leaves and rejoins gets a new `joined_at` at the
/// end of an oldest-first roster they are already on, and a public route
/// whose `run_count` drops re-sorts below the cursor of a "popular" list.
/// Appended blindly, that row renders twice, and a keyed `{#each}` throws
/// `each_key_duplicate` and takes the page down.
export function appendPage<T>(
	shown: readonly T[],
	page: readonly T[],
	keyOf: (row: T) => string,
): T[] {
	const seen = new Set(shown.map(keyOf));
	const out = [...shown];
	for (const row of page) {
		const key = keyOf(row);
		if (seen.has(key)) continue;
		seen.add(key);
		out.push(row);
	}
	return out;
}

/// A pattern for PostgREST's `imatch` operator (Postgres `~*`, read through
/// postgrest-js `regexIMatch`) that matches `text` as a case-insensitive
/// substring, every character literally.
///
/// Not `ilike`: PostgREST rewrites EVERY `*` in a like/ilike value to `%`
/// before Postgres sees it (`star` in PostgREST's `pgFmtFilter`), with no
/// escape, so a literal asterisk cannot be expressed in a like pattern at all —
/// and `%`, `_` and `\` are LIKE's own metacharacters on top. `imatch` takes
/// its value verbatim, and in a Postgres advanced regex a backslash before a
/// non-alphanumeric character means that character, so escaping the regex
/// metacharacters is the whole job. `%`, `_`, `,`, quotes and the rest are
/// ordinary in a regex and pass through. A substring regex needs no anchors,
/// and `routes_name_trgm` (gin_trgm_ops) serves `~*` as it served `ilike`.
///
/// For a TOP-LEVEL filter only: inside an `or=`/`and=` tree the value also
/// needs quoting, because `,` `(` `)` are the tree's own delimiters — use
/// `literalSubstringTerm` there.
export function literalSubstringPattern(text: string): string {
	return text.replace(/[\\^$.|?*+()[\]{}]/g, '\\$&');
}

/// One `column imatch pattern` filter for INSIDE a PostgREST `or=`/`and=`
/// tree, matching `text` as a case-insensitive literal substring of `column`.
///
/// Inside a tree PostgREST reads an unquoted value up to the next `,` or `)`
/// (`pLogicSingleVal` in `ApiRequest/QueryParams.hs`), so raw text containing
/// either ends the filter early: a `,` starts a new, malformed filter and a
/// `)` closes the tree — a parse error, or worse a different filter. A
/// double-quoted value is read up to the closing quote with `\` escaping the
/// next character, so the pattern is quoted with `\` and `"` escaped —
/// the same quoting the keyset literals use.
export function literalSubstringTerm(column: string, text: string): string {
	return `${checkColumn(column)}.imatch.${literal(literalSubstringPattern(text))}`;
}

export type PublicRouteSort = 'newest' | 'popular' | 'featured';

/// The total order of each public-route search sort. The first keys are the
/// dropped `search_public_routes` RPC's (migration 20270326_001), null
/// placement included, so the partial indexes that migration built still serve
/// the prefix; `id` is appended because none of the three was total — two routes
/// created in the same instant could swap between reads.
export function publicRouteOrder(sort: PublicRouteSort): readonly KeysetKey[] {
	const id: KeysetKey = { column: 'id', ascending: false, nullsFirst: false };
	const createdAt: KeysetKey = { column: 'created_at', ascending: false, nullsFirst: true };
	switch (sort) {
		case 'popular':
			return [{ column: 'run_count', ascending: false, nullsFirst: false }, createdAt, id];
		case 'featured':
			return [{ column: 'featured_at', ascending: false, nullsFirst: false }, createdAt, id];
		case 'newest':
			return [{ column: 'created_at', ascending: false, nullsFirst: false }, id];
	}
}

/// What a whole-table walk read, and whether it is all of it.
export interface KeysetWalk<T> {
	rows: T[];
	/// False when a page errored or the walk stopped advancing — i.e. when
	/// `rows` is known to be short of what the table holds.
	complete: boolean;
	/// The first page error, or the no-progress error; null on a whole read.
	error: unknown;
}

/// The size a walk ASKS for: PostgREST's `db.max-rows`. Deliberately not
/// assumed to be the size it gets — see `walkKeyset`.
export const KEYSET_WALK_PAGE_SIZE = 1000;

export interface WalkKeysetOptions {
	pageSize?: number;
	/// Walk only the rows strictly after this cursor.
	start?: KeysetCursor | null;
}

function sameCursor(a: KeysetCursor, b: KeysetCursor): boolean {
	return a.length === b.length && a.every((v, i) => v === b[i]);
}

/// Every row `fetchPage` can produce, one keyset page at a time — the walk a
/// backup, an export or a dedupe set needs, where "every row" is the contract.
///
/// `fetchPage(after, limit)` must apply `after` (a PostgREST `or` body, null on
/// the first page) and sort by exactly `keys`, then ask for `limit` rows. Each
/// page starts strictly after the last row the previous one returned, so a row
/// inserted or deleted while the walk runs moves no other row across a page
/// boundary: it is read once or (if it arrived behind the walk) not at all,
/// and every row present for the whole walk is read exactly once. An OFFSET
/// walk names positions instead, so the same delete skips a row and the same
/// insert repeats one.
///
/// **A short page is not proof of exhaustion.** A server whose `db.max-rows`
/// is below `pageSize` answers every page short with a 200, so the walk stops
/// only on an empty page, or on one both short of the ask AND shorter than the
/// page before it — the shape a genuinely exhausted result set has and a
/// consistently-capping one does not. A short first page therefore costs one
/// confirming read.
///
/// Never throws for a page error: a walk that dies half-way still holds rows
/// worth keeping, and `complete` is how the caller tells that apart from a
/// whole read. There is no row ceiling — a ceiling would reinstate the silent
/// truncation one order of magnitude higher. The runaway it used to guard (a
/// server that ignores the window and answers the same page forever) is caught
/// instead by the cursor: a page whose last row is the cursor it was asked to
/// pass has not advanced, and the walk stops short rather than looping.
/// The Dart half throws where this returns, per each side's error contract.
export async function walkKeyset<T extends object>(
	keys: readonly KeysetKey[],
	fetchPage: (
		after: string | null,
		limit: number,
	) => PromiseLike<{ data: T[] | null; error: unknown }>,
	opts: WalkKeysetOptions = {},
): Promise<KeysetWalk<T>> {
	const pageSize = opts.pageSize ?? KEYSET_WALK_PAGE_SIZE;
	if (!Number.isInteger(pageSize) || pageSize <= 0) {
		throw new Error(`keyset: page size must be a positive integer: ${pageSize}`);
	}
	const rows: T[] = [];
	let cursor: KeysetCursor | null = opts.start ?? null;
	let previous: number | null = null;
	for (;;) {
		let after: string | null = null;
		if (cursor !== null) {
			after = keysetAfter(keys, cursor);
			if (after === null) return { rows, complete: true, error: null };
		}
		const { data, error } = await fetchPage(after, pageSize);
		if (error) return { rows, complete: false, error };
		const page = data ?? [];
		if (page.length === 0) return { rows, complete: true, error: null };
		const next = keysetCursor(keys, page[page.length - 1]);
		if (cursor !== null && sameCursor(next, cursor)) {
			return { rows, complete: false, error: new Error('keyset: the walk stopped advancing') };
		}
		rows.push(...page);
		if (page.length < pageSize && previous !== null && page.length < previous) {
			return { rows, complete: true, error: null };
		}
		previous = page.length;
		cursor = next;
	}
}
