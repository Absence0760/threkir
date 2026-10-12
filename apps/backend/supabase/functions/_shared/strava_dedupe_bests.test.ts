/// Pins the server importer's cross-provider dedupe and embedded-best window
/// — the two decisions that settle whether an imported Strava run is skipped
/// as a duplicate and which `fastest_*_s` it lands with. The dedupe half is
/// also run against its web twin (apps/web/src/lib/integrations/garmin_dedupe.ts)
/// on the same inputs, so the two importers cannot disagree about which runs
/// are the same effort.
///
/// Run with:
///   cd apps/backend && deno test --no-check supabase/functions/_shared/strava_dedupe_bests.test.ts

import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	collectRunIdentities,
	computeEmbeddedBests,
	CROSS_PROVIDER_DISTANCE_FRACTION,
	CROSS_PROVIDER_START_TOLERANCE_S,
	fastestWindowSeconds,
	isCrossProviderDuplicate,
	medianFixIntervalS,
	type RawRunRow,
	type RunIdentity,
} from './strava.ts';
import * as webTwin from '../../../../web/src/lib/integrations/garmin_dedupe.ts';

const T0 = Date.parse('2026-03-01T08:00:00Z');
const iso = (offsetS: number) => new Date(T0 + offsetS * 1000).toISOString();

Deno.test('isCrossProviderDuplicate — the start tolerance is inclusive at 180 s and exclusive past it', () => {
	assertEquals(CROSS_PROVIDER_START_TOLERANCE_S, 180);
	const existing: RunIdentity[] = [{ startedAtMs: T0, distanceM: 10000 }];
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0 + 180_000, distanceM: 10000 }, existing), true);
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0 - 180_000, distanceM: 10000 }, existing), true);
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0 + 180_001, distanceM: 10000 }, existing), false);
});

Deno.test('isCrossProviderDuplicate — the distance fraction is 5 % of the larger run, inclusive, and symmetric', () => {
	assertEquals(CROSS_PROVIDER_DISTANCE_FRACTION, 0.05);
	const at = (d: number): RunIdentity => ({ startedAtMs: T0, distanceM: d });
	assertEquals(isCrossProviderDuplicate(at(9500), [at(10000)]), true, '500 m of 10 000 m is exactly 5 %');
	assertEquals(isCrossProviderDuplicate(at(10000), [at(9500)]), true, 'and the same pair the other way round');
	assertEquals(isCrossProviderDuplicate(at(9499), [at(10000)]), false);
	assertEquals(isCrossProviderDuplicate(at(10000), [at(9499)]), false);
});

Deno.test('isCrossProviderDuplicate — a warm-up and the race that followed it are not merged', () => {
	// Same start window, very different distances: a 2 km warm-up stamped a
	// minute before the 10 km race must not suppress the race import.
	const warmUp: RunIdentity = { startedAtMs: T0, distanceM: 2000 };
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0 + 60_000, distanceM: 10000 }, [warmUp]), false);
});

Deno.test('isCrossProviderDuplicate — two distance-less rows at the same start are the same effort', () => {
	const manual: RunIdentity = { startedAtMs: T0, distanceM: 0 };
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0 + 30_000, distanceM: 0 }, [manual]), true);
	assertEquals(
		isCrossProviderDuplicate({ startedAtMs: T0, distanceM: 5000 }, [manual]),
		false,
		'a zero-distance row does not swallow a real run at the same start',
	);
});

Deno.test('isCrossProviderDuplicate — an unreadable row is skipped, not allowed to block or match', () => {
	const rows: RunIdentity[] = [
		{ startedAtMs: NaN, distanceM: 10000 },
		{ startedAtMs: T0, distanceM: NaN },
		{ startedAtMs: T0 + 60_000, distanceM: 10050 },
	];
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0, distanceM: 10000 }, rows), true, 'the third row still matches');
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0, distanceM: 10000 }, rows.slice(0, 2)), false);
	assertEquals(isCrossProviderDuplicate({ startedAtMs: NaN, distanceM: 10000 }, rows), false);
	assertEquals(isCrossProviderDuplicate({ startedAtMs: T0, distanceM: 10000 }, []), false);
});

Deno.test('isCrossProviderDuplicate — the server and web importers agree on every case', () => {
	assertEquals(webTwin.CROSS_PROVIDER_START_TOLERANCE_S, CROSS_PROVIDER_START_TOLERANCE_S);
	assertEquals(webTwin.CROSS_PROVIDER_DISTANCE_FRACTION, CROSS_PROVIDER_DISTANCE_FRACTION);
	const existing: RunIdentity[] = [
		{ startedAtMs: T0, distanceM: 10000 },
		{ startedAtMs: T0 + 3_600_000, distanceM: 0 },
		{ startedAtMs: NaN, distanceM: 5000 },
	];
	for (const dt of [-181, -180, -1, 0, 1, 179, 180, 181, 3600, 3780, 3781]) {
		for (const d of [0, 1, 9499, 9500, 10000, 10526, 10527, NaN]) {
			const c = { startedAtMs: T0 + dt * 1000, distanceM: d };
			assertEquals(
				isCrossProviderDuplicate(c, existing),
				webTwin.isCrossProviderDuplicate(c, existing),
				`dt=${dt}s d=${d}`,
			);
		}
	}
});

function pager(rows: RawRunRow[]) {
	const calls: Array<[number, number]> = [];
	const fetchPage = (from: number, to: number) => {
		calls.push([from, to]);
		return Promise.resolve(rows.slice(from, to + 1));
	};
	return { calls, fetchPage };
}

const rowsOf = (n: number): RawRunRow[] =>
	Array.from({ length: n }, (_, i) => ({ started_at: iso(i * 86400), distance_m: 5000 + i }));

Deno.test('collectRunIdentities — pages past PostgREST\'s 1000-row cap with inclusive ranges', async () => {
	const { calls, fetchPage } = pager(rowsOf(2500));
	const out = await collectRunIdentities(fetchPage);
	assertEquals(out.length, 2500, 'a pro with 2 500 runs is compared against all of them');
	assertEquals(calls, [[0, 999], [1000, 1999], [2000, 2999]]);
	assertEquals(out[2499], { startedAtMs: T0 + 2499 * 86400_000, distanceM: 7499 });
});

Deno.test('collectRunIdentities — an exactly-full last page costs one empty fetch and then stops', async () => {
	const { calls, fetchPage } = pager(rowsOf(4));
	const out = await collectRunIdentities(fetchPage, 2);
	assertEquals(out.length, 4);
	assertEquals(calls, [[0, 1], [2, 3], [4, 5]]);
});

Deno.test('collectRunIdentities — a null page ends the walk with what was read so far', async () => {
	const calls: number[] = [];
	const out = await collectRunIdentities((from) => {
		calls.push(from);
		return Promise.resolve(from === 0 ? rowsOf(2) : null);
	}, 2);
	assertEquals(out.length, 2);
	assertEquals(calls, [0, 2]);
});

Deno.test('collectRunIdentities — the safety ceiling bounds the number of fetches', async () => {
	let fetches = 0;
	const out = await collectRunIdentities(() => {
		fetches++;
		return Promise.resolve(rowsOf(10));
	}, 10, 35);
	assertEquals(fetches, 4, 'from = 0, 10, 20, 30 — the next would be past 35');
	assertEquals(out.length, 40);
});

Deno.test('collectRunIdentities — an unparseable start is skipped and a null distance reads as 0', async () => {
	const { fetchPage } = pager([
		{ started_at: null, distance_m: 5000 },
		{ started_at: 'not a date', distance_m: 5000 },
		{ started_at: iso(0), distance_m: null },
	]);
	const out = await collectRunIdentities(fetchPage);
	assertEquals(out, [{ startedAtMs: T0, distanceM: 0 }]);
});

Deno.test('collectRunIdentities — the server and web pagers read the same rows the same way', async () => {
	const rows = [...rowsOf(5), { started_at: 'x', distance_m: 1 }, { started_at: iso(9), distance_m: null }];
	const a = pager(rows);
	const b = pager(rows);
	assertEquals(await collectRunIdentities(a.fetchPage, 3, 100), await webTwin.collectRunIdentities(b.fetchPage, 3, 100));
	assertEquals(a.calls, b.calls);
});

const pt = (s: number | null) => ({ lat: 0, lng: 0, ...(s == null ? {} : { ts: iso(s) }) });

Deno.test('medianFixIntervalS — odd and even counts, and 1 s when nothing is timestamped', () => {
	assertEquals(medianFixIntervalS([pt(0), pt(1), pt(3), pt(8)]), 2, 'intervals 1, 2, 5');
	assertEquals(medianFixIntervalS([pt(0), pt(1), pt(3), pt(6), pt(10)]), 2.5, 'intervals 1, 2, 3, 4');
	assertEquals(medianFixIntervalS([pt(null), pt(null)]), 1);
	assertEquals(medianFixIntervalS([]), 1);
});

Deno.test('medianFixIntervalS — repeated or backward stamps add no zero/negative interval', () => {
	// A watch that re-sends a fix must not drag the median toward 0 s, which
	// would tell the smoother the device samples far faster than it does.
	assertEquals(medianFixIntervalS([pt(0), pt(0), pt(0), pt(5), pt(10)]), 5);
	assertEquals(medianFixIntervalS([pt(10), pt(4), pt(14)]), 10, 'only 4 -> 14 counts');
	assertEquals(medianFixIntervalS([pt(0), pt(null), pt(4)]), 4, 'an untimed point between does not split the gap');
});

/// A straight track with a timestamp per point and an explicit cumulative, so
/// the window maths is tested without haversine rounding in the way.
function track(stepsM: number[], stepsS: number[]) {
	const pts = [pt(0)];
	const cum = [0];
	let t = 0;
	for (let i = 0; i < stepsM.length; i++) {
		t += stepsS[i];
		pts.push(pt(t));
		cum.push(cum[i] + stepsM[i]);
	}
	return { pts, cum };
}

Deno.test('fastestWindowSeconds — refuses what cannot hold the window', () => {
	const { pts, cum } = track([100, 100], [30, 30]);
	assertEquals(fastestWindowSeconds(pts, 1000, cum), null, '200 m cannot hold 1 km');
	assertEquals(fastestWindowSeconds(pts.slice(0, 1), 100, cum.slice(0, 1)), null);
	assertEquals(fastestWindowSeconds(pts, 0, cum), null);
	assertEquals(fastestWindowSeconds(pts, -5, cum), null);
	assertThrows(() => fastestWindowSeconds(pts, 100, [0, 100]), RangeError);
});

Deno.test('fastestWindowSeconds — interpolates the start inside a leg rather than rounding to a fix', () => {
	// 300 m legs at 60 s each: an even 5 m/s. Without interpolation the
	// smallest span covering 1 000 m is four legs (1 200 m, 240 s); the true
	// 1 km time is 200 s.
	const { pts, cum } = track(Array(10).fill(300), Array(10).fill(60));
	assertEquals(fastestWindowSeconds(pts, 1000, cum), 200);
});

Deno.test('fastestWindowSeconds — finds the fast kilometre in the middle of a slow run', () => {
	// 100 m legs: 2 km at 30 s/leg (5:00/km), 1 km at 24 s/leg (4:00/km), 2 km at 30 s/leg.
	const s = [...Array(20).fill(30), ...Array(10).fill(24), ...Array(20).fill(30)];
	const { pts, cum } = track(Array(50).fill(100), s);
	assertEquals(fastestWindowSeconds(pts, 1000, cum), 240);
	assertEquals(fastestWindowSeconds(pts, 5000, cum), 1440, 'the whole 5 km');
});

Deno.test('fastestWindowSeconds — a track that is the window to within float drift still counts', () => {
	// An accumulated sum of legs lands a hair under the nominal distance; the
	// relative tolerance is what lets a nominally-exact 1 km produce a best.
	const { pts, cum } = track(Array(10).fill(100), Array(10).fill(30));
	cum[cum.length - 1] = 1000 * (1 - 1e-12);
	assertEquals(fastestWindowSeconds(pts, 1000, cum), 300);
	cum[cum.length - 1] = 1000 * (1 - 1e-6);
	assertEquals(fastestWindowSeconds(pts, 1000, cum), null, 'a real millimetre short is short');
});

Deno.test('fastestWindowSeconds — a window with an untimed end is skipped, not timed from a neighbour', () => {
	const { pts, cum } = track(Array(10).fill(100), Array(10).fill(30));
	delete (pts[10] as { ts?: string }).ts;
	assertEquals(fastestWindowSeconds(pts, 1000, cum), null, 'the only window ends on the untimed point');
});

Deno.test('computeEmbeddedBests — fills only the brackets the device distance covers', () => {
	// 6 km at an even 5:00/km on the provider's own distance stream.
	const { pts, cum } = track(Array(60).fill(100), Array(60).fill(30));
	const out = computeEmbeddedBests(pts, 'run', cum);
	assertEquals(out, { fastest_5k_s: 1500 });
	assertEquals(computeEmbeddedBests(pts.slice(0, 2), 'run', cum.slice(0, 2)), {}, 'fewer than 3 points is no best');
});
