// Every image the web app renders reaches the browser under a URL that changes
// with its content (decisions § 2600).
//
// Until mid-October 2026 the deploy sent every file under static/ with a
// year-long immutable header, and static/ files keep their names, so the logo
// redesign (#1091) went on showing its old colours to browsers that had cached
// /logo-mark.svg. Two ways out, and this guard holds both:
//
//   - a file only the app's own code loads lives under src/lib/assets/ and is
//     imported through Vite, which emits it as _app/immutable/assets/<name>.<hash>
//   - a file that must keep its public path stays in static/, is listed in
//     FIXED_PATH below with the reason, and is referenced as `<path>?v=<hash>`
//     (written by scripts/gen_static_asset_versions.mjs) or through
//     staticAsset() from #lib/assets/static_asset.ts
//
// Fix a failure with `pnpm gen:static-asset-versions` when a hash is stale,
// or by moving the file to src/lib/assets/ and importing it when it is new.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

import {
	REWRITTEN_FILES,
	STATIC_DIR,
	computeVersions,
	listVersionedStaticPaths,
	referencePattern,
	rewriteReferences,
} from '../../../../scripts/gen_static_asset_versions.mjs';
import { STATIC_ASSET_VERSIONS } from './assets/static_asset_versions.ts';

const WEB_DIR = resolve(import.meta.dirname, '..', '..');
const SRC_DIR = join(WEB_DIR, 'src');

interface FixedPath {
	why: string;
	/// The consumer needs the exact path, so a reference must not carry a
	/// query. None of these is referenced by the app's own code today.
	exact?: true;
}

/// Every versioned file static/ may hold, and why it cannot be a Vite import.
/// A new image in static/ fails until it is listed here or moved.
const FIXED_PATH: Record<string, FixedPath> = {
	'/favicon.png': { why: 'browsers and the push notification fetch the site icon from the page head and sw.js' },
	'/apple-touch-icon.png': { why: 'iOS reads the home-screen icon from the page head' },
	'/manifest.webmanifest': { why: 'the PWA manifest is linked from app.html, which Vite does not process' },
	'/icon-192.png': { why: 'a PWA manifest icon, and the manifest is a static file' },
	'/icon-512.png': { why: 'a PWA manifest icon, and the Organization logo in the landing JSON-LD' },
	'/og-default.png': { why: 'crawlers fetch the og:image URL, which the share Lambdas also write' },
	'/wordmark.svg': { why: 'not rendered by the app; the dark lockup kept at a stable public URL', exact: true },
	'/bimi-logo.svg': { why: 'the BIMI DNS record names this exact URL; mail providers fetch it', exact: true },
	'/email-logo.png': {
		why: 'the auth-email Edge Function puts this exact URL in mail it sends; sent mail cannot be re-versioned',
		exact: true,
	},
};

function walk(dir: string, keep: (file: string) => boolean): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) out.push(...walk(full, keep));
		else if (keep(full)) out.push(full);
	}
	return out;
}

/// The files that render or link a static path: the app source (not its unit
/// tests, and not the generated map whose keys are the bare paths) and the two
/// static files that name others.
function referencingFiles(): string[] {
	const generated = join(SRC_DIR, 'lib', 'assets', 'static_asset_versions.ts');
	const source = walk(
		SRC_DIR,
		(f) => /\.(svelte|ts|js|css|html)$/.test(f) && !f.endsWith('.test.ts') && f !== generated,
	);
	return [...source, join(STATIC_DIR, 'sw.js'), join(STATIC_DIR, 'manifest.webmanifest')];
}

const rel = (f: string) => relative(WEB_DIR, f).split(sep).join('/');

test('the generated version map matches the files in static/', () => {
	assert.deepEqual(
		{ ...STATIC_ASSET_VERSIONS },
		computeVersions(),
		'src/lib/assets/static_asset_versions.ts is stale: run `pnpm gen:static-asset-versions`',
	);
});

test('app.html, the manifest and sw.js carry the current ?v= of every file they name', () => {
	const versions = computeVersions();
	for (const file of REWRITTEN_FILES) {
		const text = readFileSync(file, 'utf8');
		assert.equal(
			rewriteReferences(text, versions),
			text,
			`${rel(file)} names a static file by a stale or missing ?v=: run \`pnpm gen:static-asset-versions\``,
		);
	}
});

test('every image left in static/ has a reason it needs a fixed path', () => {
	const present = listVersionedStaticPaths();
	const unlisted = present.filter((p) => !(p in FIXED_PATH));
	assert.deepEqual(
		unlisted,
		[],
		'these static/ files are not in FIXED_PATH. If only the app loads them, move them to ' +
			'src/lib/assets/ and import them, so Vite names them by their hash; otherwise list them with the reason',
	);
	const stale = Object.keys(FIXED_PATH).filter((p) => !present.includes(p));
	assert.deepEqual(stale, [], 'FIXED_PATH lists files static/ no longer has: remove them');
});

test('every rendered reference to a static image is fingerprinted', () => {
	const versions = computeVersions();
	const offences: string[] = [];
	for (const file of referencingFiles()) {
		const text = readFileSync(file, 'utf8');
		for (const path of listVersionedStaticPaths()) {
			for (const m of text.matchAll(referencePattern(path))) {
				const exact = FIXED_PATH[path]?.exact === true;
				const query = m[1];
				const viaHelper = /staticAsset\(\s*['"`]$/.test(text.slice(Math.max(0, m.index - 20), m.index));
				const line = text.slice(0, m.index).split('\n').length;
				if (exact) {
					if (query) offences.push(`${rel(file)}:${line} ${path} must keep its exact path, without ?v=`);
				} else if (!viaHelper && query !== `?v=${versions[path]}`) {
					offences.push(`${rel(file)}:${line} ${m[0]}`);
				}
			}
		}
	}
	assert.deepEqual(
		offences,
		[],
		'name a static file through staticAsset() from #lib/assets/static_asset.ts, or with the ?v= ' +
			'`pnpm gen:static-asset-versions` writes; an image only the app uses belongs in src/lib/assets/',
	);
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
	assert.deepEqual(
		[...imageDirs],
		[],
		'static/ holds a directory of images; move them to src/lib/assets/ and import them',
	);
});
