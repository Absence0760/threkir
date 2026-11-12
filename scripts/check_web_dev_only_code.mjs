#!/usr/bin/env node
// Fails when the built web client carries a module that exists for `vite dev`
// only. Such a module is reached through a dynamic import inside an
// `import.meta.env.DEV` branch, which a build replaces with `false` and
// removes, so nothing of it should reach a chunk. A static import, or a
// branch the bundler can no longer prove dead, would ship it silently: the
// build passes and the page still works, with dev-only code (and the local
// tileserver URLs it reasons about) sitting in every reader's download.
//
// Each module is named by a marker string it carries, so the check reads the
// emitted client where every importer meets, the way
// `check_web_removed_kit_apis.mjs` does. The marker must still occur in the
// module's source, or the guard fails as stale rather than passing on a
// string nothing emits any more.

import { readFileSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import { CLIENT_DIR, jsFiles } from './check_web_removed_kit_apis.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

/** @typedef {{ source: string, marker: string }} DevOnlyModule */

/// `source` is repo-relative; `marker` is a string literal in it that no
/// other module carries and the minifier keeps (a log prefix survives).
/** @type {readonly DevOnlyModule[]} */
export const DEV_ONLY_MODULES = [
	{ source: 'apps/web/src/lib/routes/dev_basemap_fallback.ts', marker: '[dev-basemap]' },
];

/// The registered modules whose marker no longer occurs in their source.
/** @param {readonly DevOnlyModule[]} modules @param {(path: string) => string} read @returns {DevOnlyModule[]} */
export function staleMarkers(modules, read) {
	return modules.filter((m) => {
		try {
			return !read(m.source).includes(m.marker);
		} catch {
			return true;
		}
	});
}

/// `{ file, source }` for each emitted file that carries a dev-only marker,
/// where `file` is relative to [root].
/** @param {string} root @param {string[]} files @param {readonly DevOnlyModule[]} modules @returns {{ file: string, source: string }[]} */
export function findDevOnlyCode(root, files, modules) {
	/** @type {{ file: string, source: string }[]} */
	const hits = [];
	for (const file of files) {
		const text = readFileSync(file, 'utf8');
		for (const m of modules) {
			if (text.includes(m.marker)) hits.push({ file: relative(root, file), source: m.source });
		}
	}
	return hits;
}

function main() {
	const stale = staleMarkers(DEV_ONLY_MODULES, (p) => readFileSync(join(REPO_ROOT, p), 'utf8'));
	if (stale.length > 0) {
		for (const m of stale) {
			console.error(`${m.source}: no longer contains its marker ${JSON.stringify(m.marker)}, or is gone.`);
		}
		console.error(
			'Update DEV_ONLY_MODULES in scripts/check_web_dev_only_code.mjs to a string the module ' +
				'still carries, or remove the entry with the module.',
		);
		process.exit(1);
	}
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
	const hits = findDevOnlyCode(CLIENT_DIR, files, DEV_ONLY_MODULES);
	if (hits.length > 0) {
		for (const h of hits) console.error(`${h.file}: carries dev-only ${h.source}`);
		console.error(
			'A module meant for `vite dev` only reached the production client. Import it dynamically ' +
				'inside an `if (import.meta.env.DEV)` branch, never statically.',
		);
		process.exit(1);
	}
	console.log(
		`No dev-only module in the web client (${DEV_ONLY_MODULES.length} checked, ${files.length} .js files scanned).`,
	);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
