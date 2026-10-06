import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildStaticMarkerMapUrl,
	buildTrackThumbnailUrl,
	mapsDirectionsUrl,
	geoUri,
} from './static_map';
import { mapTrackLine } from './basemap_contrast';
import { buildMapStyleUrl, type MapStyle } from './map-style-url';

test('buildStaticMarkerMapUrl centres on lon,lat and adds a marker', () => {
	const url = buildStaticMarkerMapUrl(51.5074, -0.1278, {
		w: 320,
		h: 180,
		style: 'streets-v2',
		key: 'KEY'
	});
	assert.ok(url);
	// MapTiler path is lon,lat,zoom — longitude first.
	assert.match(url!, /\/static\/-0\.12780,51\.50740,14\/320x180@2x\.png/);
	assert.match(url!, /markers=-0\.12780,51\.50740/);
	assert.match(url!, /key=KEY/);
});

test('buildStaticMarkerMapUrl honours a custom zoom', () => {
	const url = buildStaticMarkerMapUrl(10, 20, {
		w: 100,
		h: 100,
		style: 'streets-v2',
		key: 'K',
		zoom: 9
	});
	assert.match(url!, /\/static\/20\.00000,10\.00000,9\//);
});

test('buildStaticMarkerMapUrl returns null without a key', () => {
	assert.equal(
		buildStaticMarkerMapUrl(1, 2, { w: 10, h: 10, style: 's', key: '' }),
		null
	);
});

test('buildStaticMarkerMapUrl rejects out-of-range / non-finite coords', () => {
	const opts = { w: 10, h: 10, style: 's', key: 'K' };
	assert.equal(buildStaticMarkerMapUrl(91, 0, opts), null);
	assert.equal(buildStaticMarkerMapUrl(0, 181, opts), null);
	assert.equal(buildStaticMarkerMapUrl(Number.NaN, 0, opts), null);
});

test('mapsDirectionsUrl builds a universal Google Maps query', () => {
	assert.equal(
		mapsDirectionsUrl(51.5074, -0.1278),
		'https://www.google.com/maps/search/?api=1&query=51.5074,-0.1278'
	);
});

test('geoUri encodes the optional label', () => {
	assert.equal(geoUri(1, 2), 'geo:1,2');
	assert.equal(geoUri(1, 2, 'Town Square'), 'geo:1,2?q=1,2(Town%20Square)');
});

// ── buildTrackThumbnailUrl — a thumbnail sits on the user's basemap ──────
// Pre-fix both thumbnails asked MapTiler for a hard-coded `streets-v2`, so a
// runner whose live maps were satellite or dark saw a light street map in
// every list, and the mobile twin's hard-coded `streets-v2-dark` showed a
// dark one to a runner in the light theme (decisions § 1749).

const TRACK = [
	{ lat: 51.5, lng: -0.12 },
	{ lat: 51.51, lng: -0.13 },
];

function thumb(
	mapStyle: MapStyle,
	prefersDark: boolean,
	extra: Partial<{ key: string; overrideUrl: string; allowThirdParty: boolean }> = {},
): string | null {
	return buildTrackThumbnailUrl(TRACK, {
		w: 220,
		h: 140,
		mapStyle,
		prefersDark,
		key: 'KEY',
		overrideUrl: '',
		allowThirdParty: true,
		...extra,
	});
}

function strokeOf(url: string | null): string {
	const m = url?.match(/stroke:%23([0-9A-Fa-f]{6})\|/);
	assert.ok(m, `no stroke in ${url}`);
	return `#${m[1]}`;
}

const EXPECTED_SLUG: Record<MapStyle, { light: string; dark: string }> = {
	streets: { light: 'streets-v2', dark: 'streets-v2-dark' },
	satellite: { light: 'satellite', dark: 'satellite' },
	outdoors: { light: 'outdoor-v2', dark: 'outdoor-v2' },
	dark: { light: 'streets-v2-dark', dark: 'streets-v2-dark' },
};

test("buildTrackThumbnailUrl: every map_style × theme requests the live map's slug", () => {
	for (const style of Object.keys(EXPECTED_SLUG) as MapStyle[]) {
		for (const prefersDark of [false, true]) {
			const slug = prefersDark ? EXPECTED_SLUG[style].dark : EXPECTED_SLUG[style].light;
			const url = thumb(style, prefersDark);
			assert.ok(
				url?.startsWith(`https://api.maptiler.com/maps/${slug}/static/auto/220x140@2x.png?`),
				`${style} / ${prefersDark ? 'dark' : 'light'} → ${url}`,
			);
			// The thumbnail and the live map name the same basemap.
			assert.equal(
				buildMapStyleUrl(style, 'KEY', prefersDark),
				`https://api.maptiler.com/maps/${slug}/style.json?key=KEY`,
			);
		}
	}
});

test('buildTrackThumbnailUrl: light streets in the light theme (the reported bug)', () => {
	const url = thumb('streets', false);
	assert.match(url ?? '', /\/maps\/streets-v2\/static\//);
	assert.doesNotMatch(url ?? '', /streets-v2-dark/);
});

test('buildTrackThumbnailUrl: the stroke follows the resolved ground, not the theme', () => {
	// `dark` under a light theme is dark ground; `outdoors` under a dark theme
	// is light ground; satellite counts as dark (basemap_contrast.ts).
	assert.equal(strokeOf(thumb('dark', false)), mapTrackLine(true));
	assert.equal(strokeOf(thumb('outdoors', true)), mapTrackLine(false));
	assert.equal(strokeOf(thumb('satellite', false)), mapTrackLine(true));
	assert.equal(strokeOf(thumb('streets', false)), mapTrackLine(false));
	assert.notEqual(mapTrackLine(true), mapTrackLine(false));
});

test('buildTrackThumbnailUrl: the dev override wins and keeps the path grammar', () => {
	const url = thumb('satellite', true, {
		overrideUrl: '  http://localhost:8080/styles/basic/style.json ',
		key: '',
	});
	assert.ok(
		url?.startsWith('http://localhost:8080/styles/basic/static/auto/220x140.png?path='),
		url ?? 'null',
	);
	assert.match(url ?? '', /fill:%23ffffff00\|stroke:%23[0-9A-F]{6}\|width:4\|-0\.12000,51\.50000\|/);
	// An override is light ground unless its URL names a dark style.
	assert.equal(strokeOf(url), mapTrackLine(false));
	const dark = thumb('streets', false, {
		overrideUrl: 'http://localhost:8080/styles/dark/style.json',
	});
	assert.equal(strokeOf(dark), mapTrackLine(true));
});

test('buildTrackThumbnailUrl: the self-hosted override needs no consent; MapTiler does', () => {
	assert.equal(thumb('streets', false, { allowThirdParty: false }), null);
	assert.ok(
		thumb('streets', false, {
			allowThirdParty: false,
			overrideUrl: 'http://localhost:8080/styles/basic/style.json',
		}),
	);
});

test('buildTrackThumbnailUrl: no key and no override → null, so the SVG preview draws', () => {
	assert.equal(thumb('streets', false, { key: '  ' }), null);
	assert.equal(
		buildTrackThumbnailUrl([TRACK[0]], {
			w: 220,
			h: 140,
			mapStyle: 'streets',
			prefersDark: false,
			key: 'KEY',
			overrideUrl: '',
			allowThirdParty: true,
		}),
		null,
	);
});
