// A TCX carries the device's own cumulative distance on every Trackpoint
// (`<DistanceMeters>`); the run importers stamp it on the track as `distM`
// the same way the FIT path does, so an imported TCX splits on the watch's
// distance rather than the hop-sum of its positions (#1387). DOMParser is not
// available under node, so the parse is pinned through the per-point reader
// and the importers' `withDeviceDistances` step. Mirrors
// packages/gpx_parser/test/route_parser_test.dart (`RouteParser.tcxWithDistances`).

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { trackpointDistance } from './import';
import { withDeviceDistances } from './garmin-fit';
import { computeRealSplits } from '../runs/run_stats';
import type { TrackPoint } from '../types';

const METRES_PER_MILE = 1609.344;
const M_PER_DEG = 111_320;

const child = (localName: string, textContent: string | null) => ({ localName, textContent });

test('trackpointDistance — reads the Trackpoint’s own <DistanceMeters>', () => {
	assert.equal(trackpointDistance({ children: [child('Time', 'x'), child('DistanceMeters', ' 1234.5 ')] }), 1234.5);
	assert.equal(trackpointDistance({ children: [child('DistanceMeters', '0')] }), 0);
});

test('trackpointDistance — NaN when the point carries none or an unreadable one', () => {
	assert.ok(Number.isNaN(trackpointDistance({ children: [child('Time', 'x')] })));
	assert.ok(Number.isNaN(trackpointDistance({})));
	for (const text of ['', '   ', null, 'abc']) {
		assert.ok(Number.isNaN(trackpointDistance({ children: [child('DistanceMeters', text)] })), String(text));
	}
});

/// A TCX-shaped run at 3.0 m/s: positions zig-zag 3 m either side of the road
/// for the first 600 m, the device's distance runs true along it.
function tcxShapedRun(): { track: TrackPoint[]; distances: number[] } {
	const track: TrackPoint[] = [];
	const distances: number[] = [];
	const t0 = Date.parse('2026-11-14T12:00:00Z');
	for (let i = 0; i <= 617; i++) {
		const d = i * 6;
		const latM = d < 600 ? (i % 2 === 0 ? 3 : -3) : 0;
		track.push({ lat: latM / M_PER_DEG, lng: d / M_PER_DEG, ts: new Date(t0 + i * 2000).toISOString() });
		distances.push(d + 12);
	}
	return { track, distances };
}

test('an imported TCX splits on its device distance, not the positions (#1387)', () => {
	const { track, distances } = tcxShapedRun();
	const stamped = withDeviceDistances(track, distances);
	assert.equal(stamped[0].distM, 0);
	assert.equal(stamped.at(-1)!.distM, 617 * 6);
	const total = stamped.at(-1)!.distM!;
	const splits = computeRealSplits(stamped, METRES_PER_MILE, total);
	assert.deepEqual(splits.map((s) => s.distance_m), [1609, 1609, 483]);
	for (const s of splits) assert.ok(Math.abs(s.pace_s - 333) <= 1, `split ${s.km} pace ${s.pace_s}`);

	const onPositions = computeRealSplits(track, METRES_PER_MILE, total);
	assert.ok(onPositions[0].pace_s < 333 - 30, `positions-only first mile ${onPositions[0].pace_s}`);
});

test('a TCX with a gap in its distance stream keeps splitting on positions', () => {
	const { track, distances } = tcxShapedRun();
	distances[300] = Number.NaN;
	assert.equal(withDeviceDistances(track, distances), track);
});
