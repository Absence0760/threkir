/// Pins the Deno keyset walk to its source, apps/web/src/lib/core/keyset_page.ts,
/// by running both on the same inputs: the filter each cursor produces, the
/// cursor each row yields, and the pages a walk asks for and what it returns.
/// The web suite (core/keyset_page.test.ts) owns the behaviour; this owns the
/// copy.
///
/// Run with:
///   cd apps/backend && deno test --no-check supabase/functions/_shared/keyset_page.test.ts

import { assertEquals, assertRejects, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import * as deno from './keyset_page.ts';
import * as web from '../../../../web/src/lib/core/keyset_page.ts';

const ORDERS: deno.KeysetKey[][] = [
	[{ column: 'started_at', ascending: false, nullsFirst: true }, { column: 'id', ascending: false, nullsFirst: true }],
	[{ column: 'joined_at', ascending: true, nullsFirst: false }, { column: 'user_id', ascending: true, nullsFirst: false }],
	[{ column: 'run_count', ascending: false, nullsFirst: false }, { column: 'id', ascending: false, nullsFirst: true }],
];

const CURSORS: deno.KeysetCursor[] = [
	['2026-03-01T08:00:00.123456+00:00', 'a"b\\c'],
	[null, 'id-1'],
	[42, null],
	[true, 'x'],
];

Deno.test('keysetAfter — the copy builds the same filter as the web original', () => {
	for (const keys of ORDERS) {
		for (const cursor of CURSORS) {
			assertEquals(deno.keysetAfter(keys, cursor), web.keysetAfter(keys, cursor), JSON.stringify({ keys, cursor }));
		}
	}
});

Deno.test('keysetAfter — the copy refuses what the original refuses', () => {
	assertThrows(() => deno.keysetAfter([], []));
	assertThrows(() => deno.keysetAfter(ORDERS[0], ['only one']));
	assertThrows(() => deno.keysetAfter([{ column: 'a;drop', ascending: true, nullsFirst: true }], ['x']));
	assertThrows(() => deno.keysetAfter([{ column: 'n', ascending: true, nullsFirst: true }], [Infinity]));
});

Deno.test('keysetCursor — the copy reads the same values from a row', () => {
	const row = { started_at: '2026-03-01T08:00:00.123456+00:00', id: 'r-1', extra: { nested: true } };
	assertEquals(deno.keysetCursor(ORDERS[0], row), web.keysetCursor(ORDERS[0], row));
	assertThrows(() => deno.keysetCursor(ORDERS[0], { started_at: 'x' }));
	assertThrows(() => deno.keysetCursor([{ column: 'extra', ascending: true, nullsFirst: true }], row));
});

/// `n` rows in walk order for ORDERS[0], answering the cursor by its id arm.
function source(n: number, cap = Infinity) {
	const rows = Array.from({ length: n }, (_, i) => ({ started_at: `2026-01-${String(n - i).padStart(2, '0')}`, id: `r-${n - i}` }));
	const calls: Array<{ after: string | null; limit: number }> = [];
	const fetchPage = (after: string | null, limit: number) => {
		calls.push({ after, limit });
		const id = after === null ? null : /id\.lt\."([^"]+)"/.exec(after)?.[1];
		const from = id == null ? 0 : rows.findIndex((r) => r.id === id) + 1;
		return Promise.resolve({ data: rows.slice(from, from + Math.min(limit, cap)), error: null });
	};
	return { calls, fetchPage };
}

Deno.test('walkKeyset — the copy asks for the same pages and returns the same walk', async () => {
	for (const [n, pageSize, cap] of [[0, 3, Infinity], [7, 3, Infinity], [6, 3, Infinity], [9, 4, 2]] as const) {
		const a = source(n, cap);
		const b = source(n, cap);
		const da = await deno.walkKeyset(ORDERS[0], a.fetchPage, { pageSize });
		const wb = await web.walkKeyset(ORDERS[0], b.fetchPage, { pageSize });
		assertEquals(da, wb, `n=${n} pageSize=${pageSize} cap=${cap}`);
		assertEquals(a.calls, b.calls);
	}
	assertEquals(deno.KEYSET_WALK_PAGE_SIZE, web.KEYSET_WALK_PAGE_SIZE);
});

Deno.test('walkKeyset — the copy ends a stalled or failing walk the same way', async () => {
	const stuck = () => Promise.resolve({ data: [{ started_at: 'a', id: 'x' }], error: null });
	const [ds, ws] = [await deno.walkKeyset(ORDERS[0], stuck, { pageSize: 1 }), await web.walkKeyset(ORDERS[0], stuck, { pageSize: 1 })];
	assertEquals([ds.rows, ds.complete, String(ds.error)], [ws.rows, ws.complete, String(ws.error)]);
	const failing = () => Promise.resolve({ data: null, error: 'boom' });
	assertEquals(await deno.walkKeyset(ORDERS[0], failing), await web.walkKeyset(ORDERS[0], failing));
	await Promise.all([
		assertRejects(() => deno.walkKeyset(ORDERS[0], failing, { pageSize: 0 })),
		assertRejects(() => web.walkKeyset(ORDERS[0], failing, { pageSize: 0 })),
	]);
});

