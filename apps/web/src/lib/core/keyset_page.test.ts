import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	appendPage,
	keysetAfter,
	keysetCursor,
	literalSubstringPattern,
	nextCursor,
	publicRouteOrder,
	type KeysetKey,
	type KeysetValue,
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
