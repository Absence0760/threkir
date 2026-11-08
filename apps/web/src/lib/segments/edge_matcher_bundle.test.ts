// The `segment-match` Edge Function scores runs with THIS module, bundled into
// apps/backend/supabase/functions/_shared/segment_matcher.generated.js by
// scripts/gen_edge_segment_matcher.mjs (decisions § 2392). The bundle is
// committed because the deploy bundler cannot reach apps/web, so an edit here
// that is not regenerated would leave the server timing runs by the old rule
// while the web and the phone use the new one, and nothing else would notice.
// Rebuilding and comparing byte-for-byte is what notices.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { OUTPUT, buildMatcher } from '../../../../../scripts/gen_edge_segment_matcher.mjs';
import { computeGlobalSegmentEfforts } from './segments';
import type { TrackPoint } from '../types';

test('the Edge Function bundle of the segment matcher is current', async () => {
	const committed = readFileSync(OUTPUT, 'utf8');
	const rebuilt = await buildMatcher();
	assert.equal(
		committed,
		rebuilt,
		'segment_matcher.generated.js is stale: run `pnpm gen:edge-segment-matcher` and commit it.',
	);
});

test('the bundle times a run exactly as the web module does', async () => {
	const bundle = (await import(OUTPUT)) as {
		computeGlobalSegmentEfforts: typeof computeGlobalSegmentEfforts;
	};
	const t0 = Date.parse('2026-09-01T09:00:00Z');
	const track: TrackPoint[] = [];
	for (let i = 0; i <= 60; i++) {
		track.push({
			lat: 37.5 + i * 0.0001,
			lng: -77.5,
			ts: new Date(t0 + i * 5000).toISOString(),
		} as TrackPoint);
	}
	const segments = [
		{
			points: [
				{ lat: 37.501, lng: -77.5 },
				{ lat: 37.505, lng: -77.5 },
			],
			distance_m: 445,
		},
		{
			points: [
				{ lat: 37.501, lng: -77.5 },
				{ lat: 37.505, lng: -77.5 },
			],
			distance_m: 445,
			checkpoints: [{ lat: 37.503, lng: -77.49 }],
		},
	];
	const web = computeGlobalSegmentEfforts(track, segments);
	assert.ok(web[0] !== null, 'the fixture must produce a match, or the comparison proves nothing');
	assert.equal(web[1], null, 'the off-line checkpoint must refuse the second geometry');
	assert.deepEqual(bundle.computeGlobalSegmentEfforts(track, segments), web);
});
