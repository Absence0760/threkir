import { test } from 'node:test';
import assert from 'node:assert/strict';
import { shareCardTrack } from './share_card_track';
import type { PrivacyZone } from '../routes/privacy';

const home: PrivacyZone = { lat: 40.7128, lng: -74.006, radius_m: 200 };
// 0.01 deg of longitude is ~843 m east of the zone centre: outside it.
const out = (dLng: number) => ({ lat: home.lat, lng: home.lng + dLng });

test('unknown zones draw no line, never the unclipped track', () => {
	assert.deepEqual(shareCardTrack([out(0.01), out(0.02)], null), []);
});

test('no zones draw the whole track', () => {
	const track = [out(0.01), out(0.02)];
	assert.equal(shareCardTrack(track, []), track);
});

test('the ends are trimmed where the raw or the smoothed position is in a zone', () => {
	const track = [
		{ lat: home.lat, lng: home.lng },
		{ ...out(0.01), smoothedLat: home.lat, smoothedLng: home.lng },
		out(0.02),
		out(0.03),
		{ lat: home.lat, lng: home.lng },
	];
	assert.deepEqual(shareCardTrack(track, [home]), [track[2], track[3]]);
});

test("the share card's map image is requested at the box its CSS draws it in", async () => {
	// A 1080x600 request into this box was cropped by object-fit: cover. Read
	// the four numbers back out of the card's styles so a layout change that
	// forgets SHARE_CARD_MAP fails here rather than cropping a posted image.
	const { readFileSync } = await import('node:fs');
	const { fileURLToPath } = await import('node:url');
	const { SHARE_CARD_MAP } = await import('./share_card_track');
	const page = readFileSync(
		fileURLToPath(new URL('../../routes/runs/[id]/+page.svelte', import.meta.url)),
		'utf-8',
	);
	const rule = (selector: string) => {
		const at = page.indexOf(`${selector} {`);
		assert.ok(at >= 0, `no ${selector} rule`);
		return page.slice(at, page.indexOf('}', at));
	};
	const px = (block: string, prop: string) => {
		const m = new RegExp(`\\n\\s*${prop}:\\s*(\\d+)px`).exec(block);
		assert.ok(m, `no ${prop} in px`);
		return Number(m[1]);
	};
	const card = rule('.share-card');
	const map = rule('.share-card-inner :global(.share-card-map)');
	const border = Number(/border:\s*(\d+)px/.exec(map)?.[1]);
	assert.ok(border > 0, 'the map border width moved');
	assert.deepEqual(SHARE_CARD_MAP, {
		w: px(card, 'width') - 2 * px(card, 'padding') - 2 * border,
		h: px(map, 'height') - 2 * border,
	});
});
