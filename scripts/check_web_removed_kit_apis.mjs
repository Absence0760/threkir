#!/usr/bin/env node
// Fails when the built web client still carries a SvelteKit module that Kit
// has removed. Kit 3 kept `$app/stores` only as a stub whose exports throw
// `https://svelte.dev/e/kit/app_stores_removed` on first use, so importing it
// compiles cleanly and the bundle ships — and the throw then lands at run
// time, in whatever code path first touches it. In web@1.12.0 that path was
// @sentry/sveltekit's Svelte 4 tracing variant, reached only after a reader
// accepted error-reporting consent, so no test without a DSN could see it and
// every page went blank for exactly the readers who had opted in
// (decisions § 1896).
//
// The source tree is not where to look: our own code had already moved off
// `$app/stores`, and the import came from a dependency's default export
// condition. The emitted client is the one place every importer meets, and a
// removed-module stub leaves its error URL there whoever pulled it in.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const CLIENT_DIR = join(REPO_ROOT, 'apps', 'web', 'build', '_app');

/// Kit names every removed-module error `<module>_removed` under one URL
/// prefix, so this matches the next removal as well as `$app/stores`.
export const REMOVED_API = /svelte\.dev\/e\/kit\/([a-z0-9_]+_removed)\b/g;

/// Every `.js` file under [root], recursively.
/** @param {string} root @returns {string[]} */
export function jsFiles(root) {
	/** @type {string[]} */
	const out = [];
	for (const name of readdirSync(root)) {
		const path = join(root, name);
		if (statSync(path).isDirectory()) out.push(...jsFiles(path));
		else if (name.endsWith('.js')) out.push(path);
	}
	return out;
}

/// `{ file, code }` for each removed-API stub found in [files], where `file`
/// is relative to [root].
/** @param {string} root @param {string[]} files @returns {{ file: string, code: string }[]} */
export function findRemovedApis(root, files) {
	/** @type {{ file: string, code: string }[]} */
	const hits = [];
	for (const file of files) {
		const text = readFileSync(file, 'utf8');
		for (const m of text.matchAll(REMOVED_API)) {
			hits.push({ file: relative(root, file), code: m[1] });
		}
	}
	return hits;
}

function main() {
	let files;
	try {
		files = jsFiles(CLIENT_DIR);
	} catch {
		console.error(
			`No built client at ${relative(REPO_ROOT, CLIENT_DIR)}. Run ` +
				'`npm run build --workspace=apps/web` first.',
		);
		process.exit(1);
	}
	if (files.length === 0) {
		console.error(`${relative(REPO_ROOT, CLIENT_DIR)} holds no .js files; the build stopped early.`);
		process.exit(1);
	}
	const hits = findRemovedApis(CLIENT_DIR, files);
	if (hits.length > 0) {
		for (const h of hits) {
			console.error(`${h.file}: ships the throwing stub for https://svelte.dev/e/kit/${h.code}`);
		}
		console.error(
			'A module the web client imports — ours or a dependency\'s — still uses a SvelteKit API ' +
				'that Kit has removed; it compiles, and throws when first used. Find the importer with ' +
				'`grep -rn "\\$app/stores" apps/web/src node_modules/<suspect>/`.',
		);
		process.exit(1);
	}
	console.log(`No removed SvelteKit API in the web client (${files.length} .js files scanned).`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
