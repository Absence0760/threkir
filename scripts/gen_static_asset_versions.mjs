#!/usr/bin/env node
// Versions the web app's fixed-path static files by their content.
//
// A file under apps/web/static/ is served at a path that never changes, so a
// browser that cached it keeps the old bytes until its copy expires. Until
// mid-October 2026 the deploy sent every such file with a year-long immutable
// header, and the logo redesign (#1091) kept showing its old colours to anyone
// who had loaded the page before (decisions § 2603). Anything only the app's
// own code uses lives under apps/web/src/lib/assets/ and is imported through
// Vite, which names it by its hash. What is left in static/ has to keep its
// path, so every reference to it carries `?v=<hash of the file>`, and this
// script writes that query in place: into the app source under apps/web/src
// (app.html, the OG meta tags, the share-meta builders, the JSON-LD logo) and
// into static/manifest.webmanifest and static/sw.js.
//
// The query is written into each reference rather than read from a shared
// module, because a module every share page imports becomes a chunk of its
// own in the client build, and the code budget counts every file (decisions
// § 2603). The manifest is rewritten first, because the ?v= app.html gives it
// has to cover the icon versions it carries.
//
// Run:      node scripts/gen_static_asset_versions.mjs   (pnpm gen:static-asset-versions)
// Verified: apps/web/src/lib/static_asset_fingerprint_guard.test.ts fails when
//           any reference is bare or stale.

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const WEB_DIR = join(REPO_ROOT, 'apps', 'web');
export const STATIC_DIR = join(WEB_DIR, 'static');
const SRC_DIR = join(WEB_DIR, 'src');

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

/**
 * Every versioned file static/ may hold, and why it cannot be a Vite import.
 * `exact` marks a path an outside party names exactly: it is never given a
 * query, and none of them is referenced by the app's own code.
 * @type {Record<string, { why: string, exact?: true }>}
 */
export const FIXED_PATH = {
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

/** @param {string} s */
function escapeRegExp(s) {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/// Matches `publicPath` as a whole path (not the tail of a longer one, so
/// `apps/web/static/og-default.png` in a comment is left alone), with any `?v=`
/// it already carries, so a rewrite replaces rather than appends.
/** @param {string} publicPath */
export function referencePattern(publicPath) {
	return new RegExp(`(?<![\\w./-])${escapeRegExp(publicPath)}(\\?v=[0-9a-f]*)?(?![\\w./-])`, 'g');
}

/// The current hash of every versioned file that is not exact-path.
/** @returns {Record<string, string>} */
export function computeVersions(staticDir = STATIC_DIR) {
	/** @type {Record<string, string>} */
	const versions = {};
	for (const path of listVersionedStaticPaths(staticDir)) {
		if (FIXED_PATH[path]?.exact) continue;
		versions[path] = contentHash(readFileSync(join(staticDir, path.slice(1))));
	}
	return versions;
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

/** @param {string} dir @param {(file: string) => boolean} keep @returns {string[]} */
function walkFiles(dir, keep) {
	/** @type {string[]} */
	const out = [];
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const full = join(dir, entry.name);
		if (entry.isDirectory()) out.push(...walkFiles(full, keep));
		else if (keep(full)) out.push(full);
	}
	return out.sort();
}

/// The files that render or link a static path, in rewrite order: the
/// manifest first (app.html names it), then sw.js and the app source. Unit
/// tests are left out; they assert the shape of a URL, not a hash.
export function referencingFiles() {
	return [
		join(STATIC_DIR, 'manifest.webmanifest'),
		join(STATIC_DIR, 'sw.js'),
		...walkFiles(SRC_DIR, (f) => /\.(svelte|ts|js|css|html)$/.test(f) && !f.endsWith('.test.ts')),
	];
}

function main() {
	for (const file of referencingFiles()) {
		const before = readFileSync(file, 'utf8');
		// Recomputed per file: the manifest's own hash changes when it is rewritten.
		const after = rewriteReferences(before, computeVersions());
		if (after !== before) {
			writeFileSync(file, after);
			console.log(`rewrote ${relative(REPO_ROOT, file)}`);
		}
	}
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
