// Every share card and the finisher certificate is a hand-built SVG that resvg
// (og:image) or the browser (certificate download) parses as XML. XML 1.0
// cannot carry a C0 control other than tab/LF/CR, a lone surrogate or
// U+FFFE/U+FFFF in any form — no entity spells them — so one in a route name,
// event title or a finisher name imported from a timing sheet made the parser
// refuse the whole card: the og:image fell back to a blank 1x1 and the
// certificate download failed. `routes.name`, `events.title` and
// `event_results.finisher_name` carry no control-character CHECK (only
// `user_profiles.display_name` does), so the writers have to.
//
// Each case renders through the same `@resvg/resvg-js` the og endpoints use,
// so the assertion is "a real XML parser accepts it", not a regex.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Resvg } from '@resvg/resvg-js';

import { buildRouteOgSvg } from './og_route_image';
import { buildRunOgSvg } from './og_run_image';
import { buildBadgeOgSvg } from './og_badge_image';
import { buildRecapOgSvg } from './og_recap_image';
import { buildFinisherCertificateSvg } from '../runs/finisher_certificate';

const HOSTILE = 'Col\u0001de\u000Bla \uD800Croix￾';

function parses(svg: string): void {
	assert.doesNotThrow(() => new Resvg(svg), 'resvg parses the SVG');
	assert.ok(svg.includes('�'), 'the forbidden characters became U+FFFD');
}

test('route card: a control character in the route name still yields a parseable SVG', () => {
	parses(
		buildRouteOgSvg({
			name: HOSTILE,
			distance_m: 10_000,
			surface: 'trail',
			track: [
				{ lat: 45.0, lng: 6.0 },
				{ lat: 45.01, lng: 6.01 }
			] as never
		})
	);
});

test('finisher certificate: hostile finisher name, event title and club name still parse', () => {
	const svg = buildFinisherCertificateSvg({
		eventTitle: HOSTILE,
		finisherName: `Ann${'\u0002'}e`,
		clubName: `Club\u001F`,
		durationS: 3725,
		distanceM: 10_000,
		rank: 3,
		dateIso: '2026-05-01T08:00:00Z',
		unit: 'km'
	});
	parses(svg);
	assert.ok(!/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(svg));
});

test('run card: a control character in the display name or source still parses', () => {
	parses(
		buildRunOgSvg({
			distance_m: 5000,
			duration_s: 1500,
			started_at: '2026-01-01T00:00:00Z',
			source: 'app\u0007',
			displayName: HOSTILE
		})
	);
});

test('badge card: a control character in the display name still parses', () => {
	parses(
		buildBadgeOgSvg({ badge_key: null, tier: 'gold', earned_at: '2026-01-01', displayName: HOSTILE })
	);
});

test('recap card: a control character in the display name or period label still parses', () => {
	parses(
		buildRecapOgSvg({
			year: 2026,
			totalDistanceM: 1_000_000,
			runCount: 100,
			displayName: HOSTILE,
			periodLabel: `March\u0003 2026`
		})
	);
});
