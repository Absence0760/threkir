// Source-level guards for the single brand icon colour (issue #483).
//
// The app icon renders in many places — web favicon / PWA manifest,
// Android + iOS launcher icons, and the Android status-bar notification
// icon — and every one derives from ONE master, assets/icon.svg, whose
// coral→violet gradient is #C24E24 → #5B4B8A (decisions § 1773). This test pins that
// canonical pair across every machine-readable brand-colour surface so a
// future edit to one of them can't silently drift the icon colour out of
// sync on a single platform (which is exactly what #483 reported).
//
// The binary PNG launcher icons are regenerated from the master by
// assets/gen-icons.sh and can't be asserted as text; this guard covers
// the config + vector + SVG surfaces, which is where drift creeps in.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const CORAL = '#C24E24';
const VIOLET = '#5B4B8A';

// cwd is apps/web (see `test:unit` in package.json). Repo root is two up.
function readWeb(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}
function readRepo(...parts: string[]): string {
	return readFileSync(resolve('..', '..', ...parts), 'utf-8');
}

test('master icon.svg carries the canonical coral→violet gradient', () => {
	const svg = readRepo('assets', 'icon.svg');
	assert.match(svg, new RegExp(`stop-color="${CORAL}"`), 'master must start coral');
	assert.match(svg, new RegExp(`stop-color="${VIOLET}"`), 'master must end violet');
});

test('PWA manifest theme/background colours match the master gradient stops', () => {
	const manifest = JSON.parse(readWeb('static', 'manifest.webmanifest'));
	assert.equal(manifest.theme_color, CORAL, 'theme_color must be the coral stop');
	assert.equal(manifest.background_color, VIOLET, 'background_color must be the violet stop');
});

test('app.html meta theme-color matches the manifest theme_color', () => {
	const html = readWeb('src', 'app.html');
	assert.match(
		html,
		new RegExp(`<meta name="theme-color" content="${CORAL}"`),
		'the browser chrome colour must be the coral brand colour'
	);
});

test('web logo-mark + wordmark SVGs reuse the same gradient stops', () => {
	for (const file of ['logo-mark.svg', 'wordmark.svg', 'wordmark-light.svg', 'bimi-logo.svg']) {
		const svg = readWeb('static', file);
		assert.match(svg, new RegExp(`stop-color="${CORAL}"`), `${file} must start coral`);
		assert.match(svg, new RegExp(`stop-color="${VIOLET}"`), `${file} must end violet`);
	}
});

test('the brand SVGs draw their words as outlines, never as live text', () => {
	// An <img> SVG cannot load a webfont, so live <text> renders in whatever
	// face the viewing device has. The wordmark drew "Threkir" in system-ui:
	// Noto Sans fitted its canvas, CI's DejaVu Sans overran it and clipped the
	// name to "Threki" (run 35134263272). assets/gen-wordmark.sh outlines it.
	for (const file of ['logo-mark.svg', 'wordmark.svg', 'wordmark-light.svg', 'bimi-logo.svg']) {
		const svg = readWeb('static', file);
		assert.doesNotMatch(
			svg,
			/<text[\s>]/,
			`${file} draws live <text>; outline it (assets/gen-wordmark.sh for the wordmarks)`,
		);
	}
});

// The transactional-email mark is the one brand surface whose source does not
// live in static/ — only its rendered PNG does, because email clients can't
// display an SVG. The source still has to hold the gradient, or the mark in
// every email drifts from the icon beside it in the inbox.
test('email header mark source reuses the same gradient stops', () => {
	const svg = readRepo('assets', 'email-logo.svg');
	assert.match(svg, new RegExp(`stop-color="${CORAL}"`), 'email-logo.svg must start coral');
	assert.match(svg, new RegExp(`stop-color="${VIOLET}"`), 'email-logo.svg must end violet');
	// Same hazard as the outlined wordmarks above: gen-email-logo.sh rasterises
	// this on whoever's machine runs it, so live <text> would bake in that
	// machine's font.
	assert.doesNotMatch(svg, /<text[\s>]/, 'email-logo.svg must not draw live <text>');
});

test('Android brand_coral colour resource matches the master coral stop', () => {
	// Android colours are #AARRGGBB; the coral stop is fully opaque.
	const colors = readRepo(
		'apps',
		'mobile_android',
		'android',
		'app',
		'src',
		'main',
		'res',
		'values',
		'colors.xml'
	);
	assert.match(
		colors,
		/<color name="brand_coral">#FFC24E24<\/color>/,
		'brand_coral must be opaque #C24E24 so the notification accent matches the icon'
	);
});

test('Android notification icon is a monochrome vector of the master glyph, not the full-colour launcher', () => {
	const drawable = readRepo(
		'apps',
		'mobile_android',
		'android',
		'app',
		'src',
		'main',
		'res',
		'drawable',
		'ic_stat_threkir.xml'
	);
	// A status-bar small icon is masked to its alpha silhouette, so it
	// must be a white glyph on transparency — a full-colour opaque icon
	// renders as a solid square (the #483 bug).
	assert.match(drawable, /android:fillColor="#FFFFFFFF"/, 'glyph must be white');
	assert.match(
		drawable,
		/M30 10 H44 V90 H30 Z/,
		'glyph path must be the master þ lettermark'
	);

	const bridge = readRepo(
		'apps',
		'mobile_android',
		'android',
		'app',
		'src',
		'main',
		'kotlin',
		'com',
		'threkir',
		'app',
		'RunNotificationBridge.kt'
	);
	assert.match(
		bridge,
		/setSmallIcon\(R\.drawable\.ic_stat_threkir\)/,
		'notification must use the monochrome drawable'
	);
	assert.doesNotMatch(
		bridge,
		/setSmallIcon\(R\.mipmap\.ic_launcher\)/,
		'notification must NOT use the full-colour launcher mipmap as its small icon'
	);
});
