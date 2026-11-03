import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	attributionText,
	climbIndexAt,
	endCardAlpha,
	STORY_SAFE_BOTTOM,
	STORY_SAFE_TOP,
	videoAttribution,
	videoOverlayLayout,
} from './video_overlay.ts';
import { AWS_TERRAIN_SOURCE } from '#lib/routes/terrain_source.ts';

const L = videoOverlayLayout(1080, 1920);

test('the title and the attribution stay out of the story UI bands', () => {
	assert.ok(L.title.y - L.title.size >= STORY_SAFE_TOP);
	assert.ok(L.attribution.y <= 1920 - STORY_SAFE_BOTTOM + L.attribution.size);
	assert.ok(L.attribution.y + 8 < 1920);
});

test('the stats sit above the elevation strip, the strip above the attribution', () => {
	assert.ok(L.distance.y < L.strip.y);
	assert.ok(L.strip.y + L.strip.h < L.attribution.y - L.attribution.size);
	assert.equal(L.strip.x + L.strip.w, 1080 - L.strip.x);
});

test('the end card stacks mark, wordmark, totals and address down the middle', () => {
	const e = L.end;
	assert.ok(e.mark.y + e.mark.size < e.wordmark.y);
	assert.ok(e.wordmark.y < e.lines[0].y && e.lines[0].y < e.lines[1].y && e.lines[1].y < e.url.y);
	assert.ok(e.url.y < 1920 - STORY_SAFE_BOTTOM);
});

test('the terrain credit prints as plain text', () => {
	assert.equal(attributionText(AWS_TERRAIN_SOURCE.attribution), 'Terrain Tiles: Mapzen, USGS and others');
	assert.equal(
		attributionText('&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'),
		'© OpenStreetMap contributors',
	);
});

test('every credit appears once, basemap first', () => {
	const osm = '&copy; <a href="x">OpenStreetMap</a> contributors';
	assert.equal(
		videoAttribution([osm, null, osm, AWS_TERRAIN_SOURCE.attribution, '']),
		'© OpenStreetMap contributors · Terrain Tiles: Mapzen, USGS and others',
	);
});

test('the climb overlay names the climb the flight is on, and none between', () => {
	const climbs = [
		{ startM: 100, endM: 400, gainM: 30, avgGradePct: 5, name: null },
		{ startM: 900, endM: 1200, gainM: 40, avgGradePct: 6, name: 'Hill' },
	] as never[];
	assert.equal(climbIndexAt(climbs, 50), -1);
	assert.equal(climbIndexAt(climbs, 250), 0);
	assert.equal(climbIndexAt(climbs, 600), -1);
	assert.equal(climbIndexAt(climbs, 1200), 1);
});

test('the end card fades in over its first quarter and holds', () => {
	assert.equal(endCardAlpha(0), 0);
	assert.equal(endCardAlpha(0.125), 0.5);
	assert.equal(endCardAlpha(0.5), 1);
	assert.equal(endCardAlpha(Number.NaN), 1);
});
