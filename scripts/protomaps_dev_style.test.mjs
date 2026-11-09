import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// bin/protomaps-dev.sh writes the local tileserver's style.json and
// style-dark.json. Their vector source is the only place the OpenStreetMap
// credit can come from on the dev stack: the map's attribution control and the
// flyover video's credit line both read the style's sources. A style without
// it renders OSM data uncredited, which the ODbL forbids.

const scriptUrl = new URL('../bin/protomaps-dev.sh', import.meta.url);
const script = readFileSync(scriptUrl, 'utf8');
const terrainSource = readFileSync(
	new URL('../apps/web/src/lib/routes/terrain_source.ts', import.meta.url),
	'utf8',
);
const mobileCredits = readFileSync(
	new URL('../apps/mobile_android/lib/basemap_credits.dart', import.meta.url),
	'utf8',
);

// The script dispatches on its argument and starts docker, so the test lifts
// out the assignment and the function it needs and runs only those.
function styleWriter() {
	const credit = script.match(/^BASEMAP_ATTRIBUTION=.*$/m);
	assert.ok(credit, 'bin/protomaps-dev.sh no longer defines BASEMAP_ATTRIBUTION');
	const fn = script.match(/^write_style\(\) \{\n[\s\S]*?\nEOF\n\}\n/m);
	assert.ok(fn, 'bin/protomaps-dev.sh no longer defines write_style()');
	return `${credit[0]}\n${fn[0]}`;
}

/** @param {string[]} args */
function writeStyle(args) {
	const dir = mkdtempSync(join(tmpdir(), 'protomaps-style-'));
	try {
		const file = join(dir, 'style.json');
		execFileSync('bash', ['-c', `${styleWriter()}\nwrite_style "$@"`, 'bash', file, ...args]);
		return JSON.parse(readFileSync(file, 'utf8'));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

test('both generated styles go through write_style', () => {
	const calls = [...script.matchAll(/^\s*write_style "\$(\w+)"/gm)].map((m) => m[1]);
	assert.deepEqual(calls.sort(), ['DARK_STYLE_FILE', 'STYLE_FILE']);
});

test('the generated style is valid JSON whose vector source credits Protomaps and OpenStreetMap', () => {
	const style = writeStyle(['Protomaps Basic (dev)', '#F2EFE9', '#AAD3DF', '#B8B2A7']);
	const sources = Object.values(style.sources);
	assert.ok(sources.length > 0);
	for (const source of sources) {
		assert.match(source.attribution ?? '', /href="https:\/\/www\.openstreetmap\.org\/copyright"/);
		assert.match(source.attribution ?? '', /&copy; OpenStreetMap contributors/);
		assert.match(source.attribution ?? '', /href="https:\/\/protomaps\.com\/"[^>]*>&copy; Protomaps</);
	}
});

test('the credits are the wording the app uses for them elsewhere', () => {
	const attribution = writeStyle(['n', '#000', '#000', '#000']).sources.v3.attribution;
	const osm = attribution.match(/<a href="https:\/\/www\.openstreetmap\.org[^]*?<\/a>/)?.[0];
	assert.ok(osm && terrainSource.includes(`'${osm}'`), `terrain_source.ts no longer carries this OpenStreetMap credit: ${osm}`);
	// The mobile maps credit the same tiles with the same party and link.
	assert.match(mobileCredits, /name: 'Protomaps',\s*url: 'https:\/\/protomaps\.com\/'/);
});
