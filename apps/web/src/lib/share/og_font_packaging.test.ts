// The bundled share-card face has to reach every runtime that rasterises a
// card. Rendering correctly here proves the face works; these prove the
// production Lambdas get it and that nothing reopens the system-font path
// that left the cards blank in production (issue #1287).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { OG_FONT_DIR, OG_FONT_FILES } from './og_card_font';

const WEB = fileURLToPath(new URL('../../../', import.meta.url));
const REPO = join(WEB, '..', '..');
const FONT_DIR = join(WEB, 'src', 'lib', 'share', OG_FONT_DIR);

function sources(dir: string): string[] {
	return readdirSync(join(WEB, dir), { recursive: true, encoding: 'utf8' })
		.filter((f) => /\.(ts|mjs|js|svelte)$/.test(f) && !f.split(/[\\/]/).includes('node_modules') && !f.split(/[\\/]/).includes('dist'))
		.map((f) => join(dir, f));
}

test('the face files on disk are exactly the ones the rasteriser loads', () => {
	const onDisk = readdirSync(FONT_DIR).filter((f) => f.endsWith('.ttf')).sort();
	assert.deepEqual(onDisk, [...OG_FONT_FILES].sort());
	assert.ok(existsSync(join(FONT_DIR, 'OFL.txt')), 'the OFL licence must ship beside the face');
});

test('the faces are the same bytes assets/fonts/gen-manrope.py writes for the apps', () => {
	for (const name of OG_FONT_FILES) {
		const app = join(REPO, 'packages', 'ui_kit', 'fonts', name);
		assert.ok(readFileSync(join(FONT_DIR, name)).equals(readFileSync(app)), `${name} drifted from ${app}`);
	}
});

test('nothing rasterises with system fonts, and only og_png_render builds a card rasteriser', () => {
	const systemFonts = new RegExp('loadSystemFonts' + '\\s*:\\s*true');
	const offenders: string[] = [];
	const constructors: string[] = [];
	for (const file of [...sources('src'), ...sources('lambda')]) {
		const text = readFileSync(join(WEB, file), 'utf8');
		if (systemFonts.test(text)) offenders.push(file);
		if (/new Resvg\(/.test(text) && !file.endsWith('.test.ts')) constructors.push(file);
	}
	assert.deepEqual(offenders, [], 'a card rendered with system fonts has text locally and none in a Lambda');
	assert.deepEqual(constructors.map((f) => f.replace(/\\/g, '/')), ['src/lib/share/og_png_render.ts']);
});

test('every Lambda that renders a card ships the face in its zip', () => {
	const lambdas = readdirSync(join(WEB, 'lambda'), { withFileTypes: true }).filter((d) => d.isDirectory());
	const renderers = lambdas.filter((d) => {
		const entry = join(WEB, 'lambda', d.name, 'src', 'index.ts');
		return existsSync(entry) && /from '[^']*\/og_[a-z]+_png'/.test(readFileSync(entry, 'utf8'));
	});
	assert.ok(renderers.length >= 5, `found only ${renderers.length} card-rendering Lambdas`);
	for (const d of renderers) {
		const build = readFileSync(join(WEB, 'lambda', d.name, 'build.mjs'), 'utf8');
		assert.match(build, /copyOgFonts\(distDir\)/, `${d.name}/build.mjs does not copy the face into dist`);
		assert.match(build, /zip -qr [^\n]*\$\{OG_FONT_DIR_NAME\}/, `${d.name}/build.mjs does not zip the face`);
	}
	assert.match(readFileSync(join(WEB, 'lambda', 'og_fonts_bundle.mjs'), 'utf8'), /OG_FONT_DIR_NAME = 'og-fonts'/);
	assert.equal(OG_FONT_DIR, 'og-fonts/');
});
