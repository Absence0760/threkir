// Every share card must paint its words from the bundled face alone. The
// production Lambdas have no system fonts, and resvg drops a `<text>` it has no
// face for without an error, so the cards unfurled as a bare polyline or a
// blank canvas (issue #1287) while every builder test, which reads the SVG
// string, stayed green. These render through `OG_RESVG_OPTIONS` — the exact
// options `renderOgPng` uses, system fonts off — and read the pixels.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Resvg } from '@resvg/resvg-js';

import { OG_FONT_FAMILY } from './og_card_font';
import { OG_RESVG_OPTIONS } from './og_png_render';
import { buildBadgeOgSvg } from './og_badge_image';
import { buildChallengeOgSvg } from './og_challenge_image';
import { buildRecapOgSvg } from './og_recap_image';
import { buildRouteOgSvg } from './og_route_image';
import { buildRunOgSvg } from './og_run_image';

type Box = readonly [x0: number, y0: number, x1: number, y1: number];

function render(svg: string, withFont = true) {
	const options = withFont ? OG_RESVG_OPTIONS : { ...OG_RESVG_OPTIONS, font: { loadSystemFonts: false } };
	return new Resvg(svg, options).render();
}

/// Pixels inside `box` that differ from the card's ground, read at (8, 315):
/// inside every card's left margin and below the badge and challenge cards'
/// 12 px top bar, so plain background on all of them.
function inkInBox(svg: string, box: Box, withFont = true): number {
	const img = render(svg, withFont);
	const px = img.pixels;
	const g = (315 * img.width + 8) * 4;
	const ground = [px[g], px[g + 1], px[g + 2]];
	let ink = 0;
	for (let y = box[1]; y < box[3]; y++) {
		for (let x = box[0]; x < box[2]; x++) {
			const i = (y * img.width + x) * 4;
			if (Math.abs(px[i] - ground[0]) + Math.abs(px[i + 1] - ground[1]) + Math.abs(px[i + 2] - ground[2]) > 96) {
				ink++;
			}
		}
	}
	return ink;
}

const WHOLE_CARD: Box = [0, 0, 1200, 630];

// og_route_image.ts sets the title's baseline at H - 160 = 470 in a 56 px
// face from x = 40; a title-only card (no track) puts nothing else there.
const ROUTE_TITLE: Box = [40, 470 - 56, 1160, 470 + 14];

test('the route card paints its title from the bundled face', () => {
	const svg = buildRouteOgSvg({ name: 'Philadelphia Marathon', distance_m: 42195, surface: 'road', track: [] });
	const ink = inkInBox(svg, ROUTE_TITLE);
	assert.ok(ink > 2000, `only ${ink} title pixels inked — the bundled face did not load`);
	assert.equal(
		inkInBox(svg, ROUTE_TITLE, false),
		0,
		'with no face loaded the title area should be blank; if it is not, this test no longer detects a missing font',
	);
});

const CARDS: ReadonlyArray<readonly [string, string]> = [
	['route', buildRouteOgSvg({ name: 'Hampstead Heath loop', distance_m: 5000, surface: 'trail', track: [] })],
	[
		'run',
		buildRunOgSvg({
			distance_m: 10000,
			duration_s: 3000,
			started_at: '2026-11-01T08:00:00Z',
			source: 'Threkir',
			displayName: 'Alex',
		}),
	],
	['badge', buildBadgeOgSvg({ badge_key: 'first_run', tier: 'gold', earned_at: '2026-11-01T08:00:00Z', displayName: 'Alex' })],
	['recap', buildRecapOgSvg({ year: 2026, totalDistanceM: 1234000, runCount: 150, displayName: 'Alex' })],
	['challenge', buildChallengeOgSvg({ challenge: null })],
];

for (const [kind, svg] of CARDS) {
	test(`the ${kind} card's text is set in the bundled face and paints with it`, () => {
		const families = [...svg.matchAll(/font-family="([^"]*)"/g)].map((m) => m[1]);
		assert.ok(families.length > 0, `${kind} card has no text`);
		for (const family of families) {
			assert.ok(family.startsWith(`${OG_FONT_FAMILY},`), `${kind} card names "${family}", not the bundled face first`);
		}
		const withFont = inkInBox(svg, WHOLE_CARD);
		const without = inkInBox(svg, WHOLE_CARD, false);
		assert.ok(
			withFont - without > 1000,
			`${kind} card: ${withFont} inked pixels with the bundled face against ${without} without — its text is not painting`,
		);
	});
}
