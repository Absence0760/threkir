// A static-map image is decoration over a card that works without it, so a
// failed request has to leave the card intact (conventions.md § Layered
// resilience). `StaticMapImage.svelte` owns that fallback; a raw `<img>` fed a
// static-map URL has none, and a MapTiler outage renders it as a broken image —
// which is what every route and run thumbnail did until issue #902.
//
// The consumers are a closed set rather than a scan for a variable name: a file
// that starts calling a static-map URL builder fails here until it is listed,
// with the URL it renders, so the new surface is checked the day it appears.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripComments } from './core/strip_comments';

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC = join(HERE, '..');

const BUILDER_CALL = /\b(?:buildStaticMapUrl|buildLocalStaticMapUrl|buildStaticMarkerMapUrl)\s*\(/;

/** Each file that builds a static-map URL, and the name its URL is rendered under. */
const CONSUMERS: Record<string, string> = {
	'lib/components/RouteTrackPreview.svelte': 'mapUrl',
	'lib/components/RunTrackPreview.svelte': 'mapUrl',
	'routes/runs/[id]/+page.svelte': 'shareMapUrl',
	'routes/clubs/[slug]/events/[id]/+page.svelte': 'meetMapUrl',
};

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) svelteFiles(full, out);
		else if (entry.endsWith('.svelte')) out.push(full);
	}
	return out;
}

function source(file: string): string {
	const markup = readFileSync(file, 'utf-8').replace(/<!--[\s\S]*?(?:-->|$)/g, (c) =>
		c.replace(/[^\n]/g, ' '),
	);
	return stripComments(markup);
}

function rel(file: string): string {
	return relative(SRC, file).split('\\').join('/');
}

function imgWithSrc(name: string): RegExp {
	return new RegExp(`<img\\b[^>]*\\bsrc=\\{\\s*${name}\\s*\\}`);
}

function staticMapImageWithSrc(name: string): RegExp {
	return new RegExp(`<StaticMapImage\\b[^>]*\\bsrc=\\{\\s*${name}\\s*\\}`);
}

test('every file that builds a static-map URL is a registered consumer', () => {
	const files = svelteFiles(SRC);
	assert.ok(files.length > 100, `the walk reached only ${files.length} .svelte files`);
	const building = files
		.filter((f) => BUILDER_CALL.test(source(f)))
		.map(rel)
		.sort();
	assert.deepEqual(
		building,
		Object.keys(CONSUMERS).sort(),
		'A static-map URL is rendered through StaticMapImage, which falls back when the ' +
			'request fails. Render the new one through it and register the file in CONSUMERS; ' +
			'drop an entry whose file no longer builds a URL.',
	);
});

test('each consumer renders its static-map URL through StaticMapImage, never a raw img', () => {
	for (const [path, name] of Object.entries(CONSUMERS)) {
		const text = source(join(SRC, path));
		assert.match(text, staticMapImageWithSrc(name), `${path} must render ${name} through <StaticMapImage>`);
		assert.doesNotMatch(
			text,
			imgWithSrc(name),
			`${path} renders ${name} in a raw <img>, which shows a broken image when the map request fails`,
		);
	}
});

test('no img builds a static-map URL inline', () => {
	const offenders = svelteFiles(SRC)
		.filter((f) => /<img\b[^>]*\bsrc=\{[^}]*\bbuild\w*MapUrl\s*\(/.test(source(f)))
		.map(rel);
	assert.deepEqual(offenders, []);
});

test('the StaticMapImage fallback is keyed to the URL that failed', () => {
	const text = source(join(SRC, 'lib/components/StaticMapImage.svelte'));
	assert.match(text, /onerror=\{\s*\(\)\s*=>\s*\(failedSrc = src\)\s*\}/);
	assert.match(text, /\{#if failedSrc === src\}\s*\{@render fallback\?\.\(\)\}/);
});

test('the patterns see a real mount and a raw img', () => {
	assert.match('<StaticMapImage src={mapUrl} alt="" lazy>', staticMapImageWithSrc('mapUrl'));
	assert.match('<StaticMapImage\n\t\t\t\tsrc={shareMapUrl}\n\t\t\t\talt=""', staticMapImageWithSrc('shareMapUrl'));
	assert.match('<img\n\tsrc={ meetMapUrl }\n\talt="x" />', imgWithSrc('meetMapUrl'));
	assert.doesNotMatch('<img src={mapUrlFallback} />', imgWithSrc('mapUrl'));
	assert.doesNotMatch(source(join(SRC, 'lib/components/Avatar.svelte')), BUILDER_CALL);
});
