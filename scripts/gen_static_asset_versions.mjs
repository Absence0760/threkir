#!/usr/bin/env node
// Versions the web app's fixed-path static files by their content.
//
// A file under apps/web/static/ is served at a path that never changes, so a
// browser that cached it keeps the old bytes until its copy expires. Until
// mid-October 2026 the deploy sent every such file with a year-long immutable
// header, and the logo redesign (#1091) kept showing its old colours to anyone
// who had loaded the page before (decisions § 2603). Anything only the app's
// own code uses now lives under apps/web/src/lib/assets/ and is imported
// through Vite, which names it by its hash. What is left in static/ has to keep
// its path (a favicon, the PWA manifest and its icons, the default OG image),
// so it is referenced with `?v=<hash of the file>` instead, and this script is
// what computes and writes those hashes:
//
//   apps/web/src/lib/assets/static_asset_versions.ts   the map code reads
//                                                     through staticAsset()
//   apps/web/static/manifest.webmanifest              its icons' ?v=
//   apps/web/static/sw.js                             the notification icon's ?v=
//   apps/web/src/app.html                             favicon, touch icon, manifest
//
// The manifest is rewritten before it is hashed, because its own ?v= in
// app.html has to cover the icon versions it carries.
//
// Run:      node scripts/gen_static_asset_versions.mjs   (pnpm gen:static-asset-versions)
// Verified: apps/web/src/lib/static_asset_fingerprint_guard.test.ts fails when
//           any of the four is stale.

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WEB_DIR = join(REPO_ROOT, 'apps', 'web');
export const STATIC_DIR = join(WEB_DIR, 'static');
export const VERSIONS_MODULE = join(WEB_DIR, 'src', 'lib', 'assets', 'static_asset_versions.ts');

/// Files whose bare references this script rewrites in place. app.html comes
/// last: it names the manifest, whose hash depends on the manifest's rewrite.
export const REWRITTEN_FILES = [
	join(STATIC_DIR, 'manifest.webmanifest'),
	join(STATIC_DIR, 'sw.js'),
	join(WEB_DIR, 'src', 'app.html'),
];

/// The extensions that are versioned: images, the 3D model format and the
/// manifest. Data files (help-guide JSON, the fallback map style) are not
/// rendered assets and are out of this scheme.
export const VERSIONED_EXTENSIONS = new Set([
	'.png',
	'.svg',
	'.webp',
	'.jpg',
	'.jpeg',
	'.gif',
	'.ico',
	'.avif',
	'.glb',
	'.webmanifest',
]);

const HASH_LENGTH = 10;

/** @param {string} name */
function extensionOf(name) {
	const dot = name.lastIndexOf('.');
	return dot < 0 ? '' : name.slice(dot).toLowerCase();
}

/// Every versioned file under static/, as its public path (`/favicon.png`),
/// sorted. Dot-directories (`.well-known`) are skipped: those paths are read
/// by app stores and the OS, never rendered by the app.
/** @returns {string[]} */
export function listVersionedStaticPaths(staticDir = STATIC_DIR) {
	/** @type {string[]} */
	const out = [];
	/** @param {string} dir */
	const walk = (dir) => {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			if (entry.name.startsWith('.')) continue;
			const full = join(dir, entry.name);
			if (entry.isDirectory()) walk(full);
			else if (VERSIONED_EXTENSIONS.has(extensionOf(entry.name))) {
				out.push('/' + relative(staticDir, full).split(sep).join('/'));
			}
		}
	};
	walk(staticDir);
	return out.sort();
}

/** @param {Buffer | string} bytes */
export function contentHash(bytes) {
	return createHash('sha256').update(bytes).digest('hex').slice(0, HASH_LENGTH);
}

/** @param {string} publicPath */
export function hashStaticFile(publicPath, staticDir = STATIC_DIR) {
	return contentHash(readFileSync(join(staticDir, publicPath.slice(1))));
}

/** @param {string} s */
function escapeRegExp(s) {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/// Matches `publicPath` as a whole path (not the tail of a longer one), with
/// any `?v=` it already carries, so a rewrite replaces rather than appends.
/** @param {string} publicPath */
export function referencePattern(publicPath) {
	return new RegExp(`(?<![\\w./-])${escapeRegExp(publicPath)}(\\?v=[0-9a-f]*)?(?![\\w./-])`, 'g');
}

/**
 * Sets every reference to a versioned path in `text` to `path?v=<hash>`.
 * @param {string} text
 * @param {Record<string, string>} versions
 */
export function rewriteReferences(text, versions) {
	let out = text;
	for (const [path, hash] of Object.entries(versions)) {
		out = out.replace(referencePattern(path), `${path}?v=${hash}`);
	}
	return out;
}

/** @param {Record<string, string>} versions */
export function renderVersionsModule(versions) {
	const lines = Object.entries(versions).map(([path, hash]) => `\t'${path}': '${hash}',`);
	return [
		'// Generated by scripts/gen_static_asset_versions.mjs from apps/web/static/.',
		'// Do not edit: run `pnpm gen:static-asset-versions` after changing a file there.',
		'export const STATIC_ASSET_VERSIONS = {',
		...lines,
		'} as const;',
		'',
	].join('\n');
}

/** @returns {Record<string, string>} */
export function computeVersions(staticDir = STATIC_DIR) {
	/** @type {Record<string, string>} */
	const versions = {};
	for (const path of listVersionedStaticPaths(staticDir)) versions[path] = hashStaticFile(path, staticDir);
	return versions;
}

function main() {
	// Rewrite in order, recomputing between files: each file's references must
	// carry the hashes of the files as they are after the earlier rewrites.
	for (const file of REWRITTEN_FILES) {
		const before = readFileSync(file, 'utf8');
		const after = rewriteReferences(before, computeVersions());
		if (after !== before) {
			writeFileSync(file, after);
			console.log(`rewrote ${relative(REPO_ROOT, file)}`);
		}
	}
	const module = renderVersionsModule(computeVersions());
	const current = (() => {
		try {
			return readFileSync(VERSIONS_MODULE, 'utf8');
		} catch {
			return '';
		}
	})();
	if (module !== current) {
		writeFileSync(VERSIONS_MODULE, module);
		console.log(`wrote ${relative(REPO_ROOT, VERSIONS_MODULE)}`);
	}
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
