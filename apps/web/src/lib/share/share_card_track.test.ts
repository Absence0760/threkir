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
