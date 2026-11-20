// Every image the web app renders reaches the browser under a URL that changes
// with its content (decisions § 2603).
//
// Until mid-October 2026 the deploy sent every file under static/ with a
// year-long immutable header, and static/ files keep their names, so the logo
// redesign (#1091) went on showing its old colours to browsers that had cached
// /logo-mark.svg. Two ways out, and this guard holds both:
//
//   - a file only the app's own code loads lives under src/lib/assets/ and is
//     imported through Vite, which emits it as _app/immutable/assets/<name>.<hash>
//   - a file that must keep its public path stays in static/, is listed in
//     FIXED_PATH (scripts/gen_static_asset_versions.mjs) with the reason, and
//     every reference to it carries the `?v=<hash>` that script writes
//
// Fix a failure with `pnpm gen:static-asset-versions` when a reference is bare
// or stale, or by moving the file to src/lib/assets/ and importing it when it
// is new.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { relative, resolve, sep } from 'node:path';

import {
	FIXED_PATH,
	computeVersions,
	listVersionedStaticPaths,
	referencePattern,
	referencingFiles,
	rewriteReferences,
} from '../../../../scripts/gen_static_asset_versions.mjs';

const WEB_DIR = resolve(import.meta.dirname, '..', '..');
const rel = (f: string) => relative(WEB_DIR, f).split(sep).join('/');
const lineOf = (text: string, index: number) => text.slice(0, index).split('\n').length;

test('every reference to a fixed-path static file carries its current ?v=', () => {
	const versions = computeVersions();
	const offences: string[] = [];
	for (const file of referencingFiles()) {
		const text = readFileSync(file, 'utf8');
		for (const [path, hash] of Object.entries(versions)) {
			for (const m of text.matchAll(referencePattern(path))) {
				if (m[1] !== `?v=${hash}`) offences.push(`${rel(file)}:${lineOf(text, m.index)} ${m[0]}`);
			}
		}
	}
	assert.deepEqual(
		offences,
		[],
		'a bare or stale reference to a static file: run `pnpm gen:static-asset-versions`. ' +
			'An image only the app uses belongs in src/lib/assets/, imported through Vite',
	);
});

test('the generator leaves every file it covers unchanged (nothing is stale)', () => {
	const versions = computeVersions();
	for (const file of referencingFiles()) {
		const text = readFileSync(file, 'utf8');
		assert.equal(rewriteReferences(text, versions), text, `${rel(file)} is stale: run \`pnpm gen:static-asset-versions\``);
	}
});

test('an exact-path file is never given a query', () => {
	const offences: string[] = [];
	for (const file of referencingFiles()) {
		const text = readFileSync(file, 'utf8');
		for (const [path, entry] of Object.entries(FIXED_PATH)) {
			if (!entry.exact) continue;
			for (const m of text.matchAll(referencePattern(path))) {
				if (m[1]) offences.push(`${rel(file)}:${lineOf(text, m.index)} ${m[0]}`);
			}
		}
	}
	assert.deepEqual(offences, [], 'these paths are named exactly by an outside party (see FIXED_PATH)');
});

test('every image left in static/ has a reason it needs a fixed path', () => {
	const present = listVersionedStaticPaths();
	assert.deepEqual(
		present.filter((p) => !(p in FIXED_PATH)),
		[],
		'these static/ files are not in FIXED_PATH. If only the app loads them, move them to ' +
			'src/lib/assets/ and import them, so Vite names them by their hash; otherwise list them with the reason',
	);
	assert.deepEqual(
		Object.keys(FIXED_PATH).filter((p) => !present.includes(p)),
		[],
		'FIXED_PATH lists files static/ no longer has: remove them',
	);
	for (const [path, { why }] of Object.entries(FIXED_PATH)) {
		assert.ok(why.length > 30, `FIXED_PATH's reason for ${path} has to say something`);
	}
});

test('static/ holds no directory of images, whose paths code builds at run time', () => {
	// A path assembled at run time (`/brand/grisnir/grisnir-${pose}`) never
	// matches a whole-path search, which is how the mascot art read before it
	// moved. No directory of images may come back to static/ to be built into.
	const imageDirs = new Set(
		listVersionedStaticPaths()
			.filter((p) => p.lastIndexOf('/') > 0)
			.map((p) => p.slice(0, p.lastIndexOf('/') + 1)),
	);
	assert.deepEqual([...imageDirs], [], 'static/ holds a directory of images; move them to src/lib/assets/ and import them');
});
