import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	appendPage,
	keysetAfter,
	keysetCursor,
	type KeysetKey,
	type KeysetValue,
	literalSubstringPattern,
	literalSubstringTerm,
	nextCursor,
	publicRouteOrder,
	walkKeyset,
} from './keyset_page.ts';

// ── A tiny evaluator for the filter grammar keysetAfter emits ──────────────
// Enough of PostgREST's logic tree to run a filter against in-memory rows, so
// the suite asserts what the filter SELECTS rather than only how it is spelt.

type Row = Record<string, KeysetValue>;

function splitTop(s: string): string[] {
	const parts: string[] = [];
	let depth = 0;
	let quoted = false;
	let start = 0;
	for (let i = 0; i < s.length; i++) {
		const c = s[i];
		if (quoted) {
			if (c === '\\') i++;
			else if (c === '"') quoted = false;
		} else if (c === '"') quoted = true;
		else if (c === '(') depth++;
		else if (c === ')') depth--;
		else if (c === ',' && depth === 0) {
			parts.push(s.slice(start, i));
			start = i + 1;
		}
	}
	parts.push(s.slice(start));
	return parts;
}

function unquote(v: string): string {
	assert.ok(v.startsWith('"') && v.endsWith('"'), `unquoted literal ${v}`);
	return v.slice(1, -1).replace(/\\(.)/g, '$1');
}

function compareValues(a: KeysetValue, b: string): number {
	if (typeof a === 'number') return a - Number(b);
	const s = String(a);
	return s < b ? -1 : s > b ? 1 : 0;
}

function matches(term: string, row: Row): boolean {
	for (const op of ['and', 'or'] as const) {
		if (term.startsWith(`${op}(`)) {
			const inner = splitTop(term.slice(op.length + 1, -1));
			return op === 'and' ? inner.every((t) => matches(t, row)) : inner.some((t) => matches(t, row));
		}
	}
	const [col, ...rest] = term.split('.');
	const tail = rest.join('.');
	const v = row[col];
	if (tail === 'is.null') return v === null;
	if (tail === 'not.is.null') return v !== null;
	const op = tail.slice(0, 2);
	const lit = unquote(tail.slice(3));
	if (v === null) return false;
	const cmp = compareValues(v, lit);
	if (op === 'eq') return cmp === 0;
	if (op === 'gt') return cmp > 0;
	if (op === 'lt') return cmp < 0;
	throw new Error(`unknown op in ${term}`);
}

function selects(filter: string | null, row: Row): boolean {
	return filter !== null && splitTop(filter).some((t) => matches(t, row));
}

/// Postgres's ORDER BY for `keys`, null placement included.
function sortRows(keys: readonly KeysetKey[], rows: readonly Row[]): Row[] {
	return [...rows].sort((a, b) => {
		for (const k of keys) {
			const x = a[k.column];
			const y = b[k.column];
			if (x === null && y === null) continue;
			if (x === null) return k.nullsFirst ? -1 : 1;
			if (y === null) return k.nullsFirst ? 1 : -1;
			const c = compareValues(x, String(y));
			if (c !== 0) return k.ascending ? c : -c;
		}
		return 0;
	});
}

/// One keyset read: the first `limit` rows after `cursor` in the order.
function readPage(keys: readonly KeysetKey[], rows: readonly Row[], cursor: KeysetValue[] | null, limit: number): Row[] {
	const filter = cursor ? keysetAfter(keys, cursor) : undefined;
	if (filter === null) return [];
	return sortRows(keys, rows.filter((r) => filter === undefined || selects(filter, r))).slice(0, limit);
}

// Ties on the leading key and nulls in it, so every arm of the expansion runs.
const DATA: Row[] = [
	{ at: '2026-01-03T00:00:00.000001+00:00', id: 'a' },
	{ at: '2026-01-02T00:00:00+00:00', id: 'b' },
	{ at: '2026-01-02T00:00:00+00:00', id: 'c' },
	{ at: null, id: 'd' },
	{ at: '2026-01-01T00:00:00+00:00', id: 'e' },
	{ at: null, id: 'f' },
	{ at: '2026-01-02T00:00:00+00:00', id: 'g' },
];

const ORDERS: Record<string, KeysetKey[]> = {};
for (const ascending of [true, false]) {
	for (const nullsFirst of [true, false]) {
		ORDERS[`at ${ascending ? 'asc' : 'desc'} nulls ${nullsFirst ? 'first' : 'last'}`] = [
			{ column: 'at', ascending, nullsFirst },
			{ column: 'id', ascending: !ascending, nullsFirst: false },
		];
	}
}

for (const [name, keys] of Object.entries(ORDERS)) {
	test(`${name}: after any row selects exactly the rows behind it`, () => {
		const sorted = sortRows(keys, DATA);
		sorted.forEach((row, i) => {
			const filter = keysetAfter(keys, keysetCursor(keys, row) as KeysetValue[]);
			const got = sorted.filter((r) => selects(filter, r)).map((r) => r.id);
			assert.deepEqual(got, sorted.slice(i + 1).map((r) => r.id), `after ${row.id}`);
		});
	});

	test(`${name}: walking pages of 2 visits every row once`, () => {
		const seen: KeysetValue[] = [];
		let cursor: KeysetValue[] | null = null;
		for (let guard = 0; guard < 10; guard++) {
			const page = readPage(keys, DATA, cursor, 2);
			seen.push(...page.map((r) => r.id));
			const next = nextCursor(keys, page, 2);
			if (next === null) break;
			cursor = [...next];
		}
		assert.deepEqual(seen, sortRows(keys, DATA).map((r) => r.id));
	});
}

test('a row deleted from page 1 does not make page 2 skip one, as an offset does', () => {
	// The bug this module exists for. Newest-first, page size 2: page 1 is
	// a, then the b/c/g tie broken by id. Deleting page 1's first row before
	// "load more" shifts every position down by one, so OFFSET 2 starts a row
	// late and the row that was third is never shown; the cursor still names
	// the last row shown.
	const keys = ORDERS['at desc nulls last'];
	const sorted = sortRows(keys, DATA);
	const page1 = readPage(keys, DATA, null, 2);
	const after = DATA.filter((r) => r.id !== page1[0].id);
	const page2 = readPage(keys, after, [...keysetCursor(keys, page1[1])], 2);
	assert.deepEqual(page2.map((r) => r.id), sorted.slice(2, 4).map((r) => r.id));
	const offsetPage2 = sortRows(keys, after).slice(2, 4);
	assert.notDeepEqual(offsetPage2.map((r) => r.id), page2.map((r) => r.id));
});

test('a row inserted above the boundary is not repeated on page 2', () => {
	const keys = ORDERS['at desc nulls last'];
	const page1 = readPage(keys, DATA, null, 2);
	const grown = [{ at: '2026-02-01T00:00:00+00:00', id: 'z' }, ...DATA];
	const page2 = readPage(keys, grown, [...keysetCursor(keys, page1[1])], 2);
	assert.equal(page2.some((r) => page1.some((p) => p.id === r.id)), false);
});

test('the filter spells a two-key descending order the way the feed cursor does', () => {
	const keys: KeysetKey[] = [
		{ column: 'started_at', ascending: false, nullsFirst: true },
		{ column: 'id', ascending: false, nullsFirst: true },
	];
	assert.equal(
		keysetAfter(keys, ['2026-01-01T10:00:00.5+00:00', 'r1']),
		'started_at.lt."2026-01-01T10:00:00.5+00:00",' +
			'and(started_at.eq."2026-01-01T10:00:00.5+00:00",id.lt."r1")',
	);
});

test('a nulls-last key admits the nulls behind a non-null cursor', () => {
	const keys: KeysetKey[] = [
		{ column: 'joined_at', ascending: true, nullsFirst: false },
		{ column: 'user_id', ascending: true, nullsFirst: false },
	];
	assert.equal(
		keysetAfter(keys, ['2026-01-01', 'u1']),
		'or(joined_at.gt."2026-01-01",joined_at.is.null),' +
			'and(joined_at.eq."2026-01-01",or(user_id.gt."u1",user_id.is.null))',
	);
	assert.equal(
		keysetAfter(keys, [null, 'u1']),
		'and(joined_at.is.null,or(user_id.gt."u1",user_id.is.null))',
	);
});

test('a null cursor on a nulls-first key is followed by every non-null', () => {
	assert.equal(
		keysetAfter([{ column: 'featured_at', ascending: false, nullsFirst: true }], [null]),
		'featured_at.not.is.null',
	);
});

test('nothing can follow a null on a nulls-last final key', () => {
	assert.equal(keysetAfter([{ column: 'x', ascending: true, nullsFirst: false }], [null]), null);
});

test('literals are quoted and escaped; numbers and booleans are stringified', () => {
	const k = (column: string): KeysetKey => ({ column, ascending: true, nullsFirst: true });
	assert.equal(keysetAfter([k('name')], ['a"b\\c']), 'name.gt."a\\"b\\\\c"');
	assert.equal(keysetAfter([k('run_count')], [5]), 'run_count.gt."5"');
	assert.equal(keysetAfter([k('flag')], [false]), 'flag.gt."false"');
});

test('a malformed order or cursor throws rather than reading the wrong page', () => {
	const k: KeysetKey = { column: 'id', ascending: true, nullsFirst: true };
	assert.throws(() => keysetAfter([], []), /at least one key/);
	assert.throws(() => keysetAfter([k], ['a', 'b']), /2 values for 1 keys/);
	assert.throws(() => keysetAfter([{ ...k, column: 'id,x' }], ['a']), /plain column/);
	assert.throws(() => keysetAfter([k], [Number.NaN]), /finite/);
	assert.throws(() => keysetCursor([k], { other: 1 }), /no id/);
	assert.throws(() => keysetCursor([k], { id: { nested: true } }), /not a scalar/);
});

test('nextCursor ends the list on a short page and continues from the last row of a full one', () => {
	const keys: KeysetKey[] = [{ column: 'id', ascending: true, nullsFirst: true }];
	assert.equal(nextCursor(keys, [{ id: 'a' }], 2), null);
	assert.equal(nextCursor(keys, [], 2), null);
	assert.deepEqual(nextCursor(keys, [{ id: 'a' }, { id: 'b' }], 2), ['b']);
});

test('the public-route orders keep the RPC prefix and end on id', () => {
	const spell = (sort: 'newest' | 'popular' | 'featured') =>
		publicRouteOrder(sort).map(
			(k) => `${k.column} ${k.ascending ? 'asc' : 'desc'} nulls ${k.nullsFirst ? 'first' : 'last'}`,
		);
	assert.deepEqual(spell('newest'), ['created_at desc nulls last', 'id desc nulls last']);
	assert.deepEqual(spell('popular'), [
		'run_count desc nulls last',
		'created_at desc nulls first',
		'id desc nulls last',
	]);
	assert.deepEqual(spell('featured'), [
		'featured_at desc nulls last',
		'created_at desc nulls first',
		'id desc nulls last',
	]);
});

// ── walkKeyset ─────────────────────────────────────────────────────────────

/// A fake PostgREST over `table()` — read on every call, so a test can change
/// the table mid-walk — that runs the walk's filter through the evaluator,
/// sorts by `keys`, and answers at most `cap` rows however many were asked
/// for. `beforeRead(n)` runs before the n-th read (0-based).
function walkServer(
	keys: readonly KeysetKey[],
	table: () => readonly Row[],
	opts: { cap?: number; beforeRead?: (n: number) => void } = {},
) {
	const calls: { after: string | null; limit: number }[] = [];
	const fetchPage = async (after: string | null, limit: number) => {
		opts.beforeRead?.(calls.length);
		calls.push({ after, limit });
		const admitted = table().filter((r) => after === null || selects(after, r));
		const take = Math.min(limit, opts.cap ?? limit);
		return { data: sortRows(keys, admitted).slice(0, take), error: null };
	};
	return { fetchPage, calls };
}

const WALK_KEYS = ORDERS['at desc nulls last'];
const walkIds = (rows: readonly Row[]) => rows.map((r) => r.id);

test('walkKeyset: every row once, in order, across pages', async () => {
	for (const keys of Object.values(ORDERS)) {
		const { fetchPage } = walkServer(keys, () => DATA);
		const walk = await walkKeyset(keys, fetchPage, { pageSize: 2 });
		assert.equal(walk.complete, true);
		assert.deepEqual(walkIds(walk.rows), walkIds(sortRows(keys, DATA)));
	}
});

test('walkKeyset: a row deleted mid-walk does not make the walk skip another, as an offset walk does', async () => {
	// The data-loss bug: a backup pages runs by OFFSET, the runner deletes a
	// run the walk already passed, every later run moves up one position, and
	// the next OFFSET starts a row late — one run is never archived.
	const sorted = sortRows(WALK_KEYS, DATA);
	let table: readonly Row[] = DATA;
	const deleteFirst = (n: number) => {
		if (n === 1) table = table.filter((r) => r.id !== sorted[0].id);
	};
	const { fetchPage } = walkServer(WALK_KEYS, () => table, { beforeRead: deleteFirst });
	const walk = await walkKeyset(WALK_KEYS, fetchPage, { pageSize: 2 });
	assert.equal(walk.complete, true);
	assert.deepEqual(walkIds(walk.rows), walkIds(sorted));

	// The same deletion under the OFFSET walk this replaced loses sorted[2].
	table = DATA;
	const offsetRows: Row[] = [];
	for (let from = 0, n = 0; ; from += 2, n++) {
		deleteFirst(n);
		const page = sortRows(WALK_KEYS, table).slice(from, from + 2);
		offsetRows.push(...page);
		if (page.length < 2) break;
	}
	assert.equal(offsetRows.some((r) => r.id === sorted[2].id), false);
});

test('walkKeyset: a row inserted mid-walk behind the cursor repeats nothing, as an offset walk does', async () => {
	const sorted = sortRows(WALK_KEYS, DATA);
	const newest: Row = { at: '2026-02-01T00:00:00+00:00', id: 'z' };
	let table: readonly Row[] = DATA;
	const insert = (n: number) => {
		if (n === 1) table = [newest, ...DATA];
	};
	const { fetchPage } = walkServer(WALK_KEYS, () => table, { beforeRead: insert });
	const walk = await walkKeyset(WALK_KEYS, fetchPage, { pageSize: 2 });
	assert.deepEqual(walkIds(walk.rows), walkIds(sorted));

	table = DATA;
	const offsetRows: Row[] = [];
	for (let from = 0, n = 0; ; from += 2, n++) {
		insert(n);
		const page = sortRows(WALK_KEYS, table).slice(from, from + 2);
		offsetRows.push(...page);
		if (page.length < 2) break;
	}
	assert.equal(offsetRows.filter((r) => r.id === sorted[1].id).length, 2);
});

test('walkKeyset: a server capping below the page size is not read as exhausted', async () => {
	const { fetchPage } = walkServer(WALK_KEYS, () => DATA, { cap: 2 });
	const walk = await walkKeyset(WALK_KEYS, fetchPage, { pageSize: 5 });
	assert.equal(walk.complete, true);
	assert.deepEqual(walkIds(walk.rows), walkIds(sortRows(WALK_KEYS, DATA)));
});

test('walkKeyset: a short first page costs one confirming read; a full last page one empty read', async () => {
	const short = walkServer(WALK_KEYS, () => DATA);
	assert.equal((await walkKeyset(WALK_KEYS, short.fetchPage, { pageSize: 10 })).rows.length, 7);
	assert.equal(short.calls.length, 2);
	assert.equal(short.calls[0].after, null, 'the first page is unfiltered');

	const exact = walkServer(WALK_KEYS, () => DATA.slice(0, 6));
	assert.equal((await walkKeyset(WALK_KEYS, exact.fetchPage, { pageSize: 3 })).rows.length, 6);
	assert.equal(exact.calls.length, 3);

	const empty = walkServer(WALK_KEYS, () => []);
	const none = await walkKeyset(WALK_KEYS, empty.fetchPage);
	assert.deepEqual(none, { rows: [], complete: true, error: null });
	assert.equal(empty.calls[0].limit, 1000);
});

test('walkKeyset: a page error returns the rows read so far, flagged short, and never throws', async () => {
	const { fetchPage } = walkServer(WALK_KEYS, () => DATA);
	let n = 0;
	const walk = await walkKeyset(
		WALK_KEYS,
		(after, limit) =>
			n++ === 0 ? fetchPage(after, limit) : Promise.resolve({ data: null, error: new Error('reset') }),
		{ pageSize: 2 },
	);
	assert.equal(walk.rows.length, 2);
	assert.equal(walk.complete, false);
	assert.equal((walk.error as Error).message, 'reset');
});

test('walkKeyset: a server that ignores the filter stops short instead of looping', async () => {
	const first = sortRows(WALK_KEYS, DATA).slice(0, 2);
	const walk = await walkKeyset(WALK_KEYS, async () => ({ data: first, error: null }), { pageSize: 2 });
	assert.deepEqual(walkIds(walk.rows), walkIds(first), 'the repeated page is not appended');
	assert.equal(walk.complete, false);
	assert.match(String(walk.error), /stopped advancing/);
});

test('walkKeyset: a start cursor walks only the rows after it', async () => {
	const sorted = sortRows(WALK_KEYS, DATA);
	const { fetchPage } = walkServer(WALK_KEYS, () => DATA);
	const walk = await walkKeyset(WALK_KEYS, fetchPage, {
		pageSize: 2,
		start: keysetCursor(WALK_KEYS, sorted[2]),
	});
	assert.deepEqual(walkIds(walk.rows), walkIds(sorted.slice(3)));
});

test('walkKeyset: a non-positive page size is refused', async () => {
	const { fetchPage } = walkServer(WALK_KEYS, () => DATA);
	await assert.rejects(walkKeyset(WALK_KEYS, fetchPage, { pageSize: 0 }), /positive integer/);
});

// ── literalSubstringPattern ────────────────────────────────────────────────
// The pattern goes to Postgres `~*`. For the metacharacters escaped here a JS
// RegExp reads `\<char>` exactly as a Postgres advanced regex does (that
// character, literally), so a case-insensitive JS RegExp stands in for the
// server below.

const TRICKY = ['5*5', '100%', 'a_b', 'c:\\dir', 'x,y', 'f(1)', 'a.b', '"q"', "it's", '[a]', '{2}', 'a|b', '^$', 'a+?', '***'];

test('every character of the query matches literally, anywhere in the name', () => {
	for (const text of TRICKY) {
		const re = new RegExp(literalSubstringPattern(text), 'i');
		assert.ok(re.test(`Route ${text.toUpperCase()} loop`), `${text} must match itself`);
	}
});

test('a wildcard-looking character matches only itself', () => {
	const miss: Array<[string, string]> = [
		['5*5', '5555'],
		['5*5', '55'],
		['a_b', 'axb'],
		['a.b', 'axb'],
		['100%', '1000'],
		['c:\\dir', 'c:dir'],
		['a|b', 'b'],
		['a+?', 'aa'],
		['[a]', 'a'],
		['{2}', 'x'],
	];
	for (const [text, name] of miss) {
		assert.ok(!new RegExp(literalSubstringPattern(text), 'i').test(name), `${text} must not match ${name}`);
	}
});

test('the regex metacharacters are escaped and nothing else is', () => {
	assert.equal(literalSubstringPattern('5*5'), '5\\*5');
	assert.equal(literalSubstringPattern('\\^$.|?*+()[]{}'), '\\\\\\^\\$\\.\\|\\?\\*\\+\\(\\)\\[\\]\\{\\}');
	assert.equal(literalSubstringPattern(`100% a_b, "q" it's -#éß`), `100% a_b, "q" it's -#éß`);
});

// ── literalSubstringTerm ───────────────────────────────────────────────────
// A faithful model of how PostgREST reads the filters of a flat `or=(…)` body:
// `pLogicSingleVal` (ApiRequest/QueryParams.hs) tries a double-quoted value
// first — `\` escapes the next character, and the closing quote must be
// followed by `,` or `)` — and otherwise takes everything up to the next `,`
// or `)`. A `)` before the end of the body closes the tree, so it is an error
// here. Returns each filter as [column, operator, value].
function parseOrBody(body: string): Array<[string, string, string]> {
	const out: Array<[string, string, string]> = [];
	let i = 0;
	for (;;) {
		const head = /^([a-z_][a-z0-9_]*)\.([a-z]+)\./.exec(body.slice(i));
		if (!head) throw new Error(`not a filter at ${i}: ${body.slice(i)}`);
		i += head[0].length;
		let value = '';
		let quoted = false;
		if (body[i] === '"') {
			let j = i + 1;
			while (j < body.length && body[j] !== '"') {
				if (body[j] === '\\') j++;
				value += body[j] ?? '';
				j++;
			}
			if (j < body.length && (j + 1 === body.length || body[j + 1] === ',' || body[j + 1] === ')')) {
				i = j + 1;
				quoted = true;
			} else value = '';
		}
		if (!quoted) {
			let j = i;
			while (j < body.length && body[j] !== ',' && body[j] !== ')') j++;
			value = body.slice(i, j);
			i = j;
		}
		out.push([head[1], head[2], value]);
		if (i === body.length) return out;
		if (body[i] !== ',') throw new Error(`the tree closes early at ${i}: ${body}`);
		i++;
	}
}

const DELIMITERS = [...TRICKY, ',', '(', ')', '.', '"', '\\', '*', '%', '_', ',()."\\*%_', 'a"),b.eq.(', '\\"', '{x}'];

test('a substring term survives every logic-tree delimiter and matches literally', () => {
	for (const text of DELIMITERS) {
		const body = [literalSubstringTerm('name', text), literalSubstringTerm('location_label', text)].join(',');
		const filters = parseOrBody(body);
		assert.deepEqual(
			filters.map(([c, op]) => [c, op]),
			[
				['name', 'imatch'],
				['location_label', 'imatch'],
			],
			`${text} must stay two filters`,
		);
		for (const [, , value] of filters) {
			assert.equal(value, literalSubstringPattern(text), `${text} must reach the server unchanged`);
			assert.ok(new RegExp(value, 'i').test(`Club ${text.toUpperCase()}!`), `${text} must match itself`);
		}
	}
	assert.throws(() => literalSubstringTerm('name,x', 'a'), /not a plain column name/);
});

test('the raw interpolation club search used is not the filter it meant', () => {
	// What browseClubs sent before: the term unquoted inside the tree.
	const raw = (t: string) => `name.ilike.%${t}%,location_label.ilike.%${t}%`;
	assert.throws(() => parseOrBody(raw('x,y')), /not a filter/);
	assert.throws(() => parseOrBody(raw('f(1)')), /closes early/);
	assert.deepEqual(parseOrBody(raw('5k')), [
		['name', 'ilike', '%5k%'],
		['location_label', 'ilike', '%5k%'],
	]);
});

// ── appendPage ─────────────────────────────────────────────────────────────

const id = (r: { id: string }) => r.id;
const rows = (...ids: string[]) => ids.map((i) => ({ id: i }));

test('a row that moved past the cursor between reads is not repeated', () => {
	// A member who leaves and rejoins an oldest-first roster gets a new
	// joined_at at the end, so the keyset page after the cursor returns them
	// again. Appended blindly, m1 renders twice and the keyed member list
	// throws each_key_duplicate.
	const merged = appendPage(rows('m1', 'm2'), rows('m3', 'm1'), id);
	assert.deepEqual(merged.map(id), ['m1', 'm2', 'm3']);
});

test('a page with no overlap appends in order', () => {
	assert.deepEqual(appendPage(rows('a', 'b'), rows('c', 'd'), id).map(id), ['a', 'b', 'c', 'd']);
});

test('the row already shown keeps its place and its value', () => {
	const shown = [{ id: 'a', v: 1 }];
	const merged = appendPage(shown, [{ id: 'a', v: 2 }, { id: 'b', v: 3 }], (r) => r.id);
	assert.deepEqual(merged, [
		{ id: 'a', v: 1 },
		{ id: 'b', v: 3 },
	]);
});

test('duplicates inside one page collapse too', () => {
	assert.deepEqual(appendPage([], rows('a', 'a', 'b'), id).map(id), ['a', 'b']);
});

test('the shown list is not mutated', () => {
	const shown = rows('a');
	appendPage(shown, rows('b'), id);
	assert.deepEqual(shown.map(id), ['a']);
});
