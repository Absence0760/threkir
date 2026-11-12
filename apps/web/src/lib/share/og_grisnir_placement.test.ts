// Grisnir sits in one corner of every /og/* unfurl and never over the card's
// own content: the route, the stats or the runner's name (#1360).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildBadgeOgSvg } from './og_badge_image';
import { buildChallengeOgSvg } from './og_challenge_image';
import { buildRecapOgSvg } from './og_recap_image';
import { buildRouteOgSvg } from './og_route_image';
import { buildRunOgSvg } from './og_run_image';
import { estimateSvgTextWidthPx } from './svg_text_width';
import type { SharedChallenge } from './share_challenge_lookup';

type Box = { x: number; y: number; w: number; h: number };

function mascotBoxes(svg: string): Box[] {
	return [...svg.matchAll(/<image data-mascot="grisnir" x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"/g)].map(
		(m) => ({ x: +m[1], y: +m[2], w: +m[3], h: +m[4] }),
	);
}

function only(svg: string): Box {
	const boxes = mascotBoxes(svg);
	assert.equal(boxes.length, 1, 'one Grisnir per card');
	const b = boxes[0];
	assert.ok(b.x >= 0 && b.y >= 0 && b.x + b.w <= 1200 && b.y + b.h <= 630, 'inside the 1200x630 card');
	assert.ok(b.h <= 180, 'a corner badge, not a hero');
	return b;
}

const LONG = 'Annemarie-Charlotte Wolkenstein-Trostburg of the Saturday Long Run Club';

test('run: top-right, above the centred distance and clear of the source tag', () => {
	const b = only(buildRunOgSvg({ distance_m: 42195, duration_s: 12000, started_at: '2026-04-04T06:00:00Z', source: 'strava', displayName: LONG }));
	assert.ok(b.x + b.w > 1000, 'right edge');
	// The hero's 180 px numeral has its baseline at 335, so its glyphs start near 205.
	assert.ok(b.y + b.h < 205);
});

test('route: under the wordmark, left of the track viewport and above the title', () => {
	const b = only(buildRouteOgSvg({ name: LONG, distance_m: 10000, track: [{ lat: 0, lng: 0 }, { lat: 0.01, lng: 0.01 }] }));
	assert.ok(b.x + b.w < 1200 - 800 - 40, 'left of the 800 px track viewport');
	assert.ok(b.y + b.h < 630 - 160 - 56, 'above the 56 px title');
});

test('badge: top-right under the tier bar', () => {
	const b = only(buildBadgeOgSvg({ badge_key: 'distance_42k', tier: 'gold', displayName: LONG }));
	assert.ok(b.y >= 12, 'below the tier bar');
	assert.ok(b.x + b.w > 1000);
	assert.ok(b.y + b.h < 630 / 2 - 10 - 72, 'above the 96 px badge name');
});

test('challenge: bottom-right, and the name beside him stops short of him', () => {
	const c: SharedChallenge = {
		id: 'c1',
		title: 'November hundred',
		description: null,
		metric: 'distance',
		scope: 'individual',
		goal_value: 100000,
		starts_at: '2026-11-01T00:00:00Z',
		ends_at: '2026-11-30T23:59:59Z',
		participant_count: 12,
		creator_id: 'u1',
	};
	const svg = buildChallengeOgSvg({ challenge: c, creatorName: LONG });
	const b = only(svg);
	assert.ok(b.y > 630 / 2 + 60, 'below the goal line');
	const by = svg.match(/>(by [^<]+)</)?.[1] ?? '';
	assert.ok(by.length > 0);
	assert.ok(56 + estimateSvgTextWidthPx(by, 32) < b.x, 'the attribution ends left of Grisnir');
});

test('recap: top-right on the dark card, above the hero numeral', () => {
	const b = only(buildRecapOgSvg({ year: 2026, totalDistanceM: 2_345_600, runCount: 312, displayName: LONG }));
	assert.ok(b.x + b.w > 1000);
	// Above the 150 px hero numeral, or right of where it ends.
	const heroRight = 64 + estimateSvgTextWidthPx('2346 km', 150);
	assert.ok(b.y + b.h < 64 + 230 - 110 || b.x > heroRight, `${b.x} vs ${heroRight}`);
});
