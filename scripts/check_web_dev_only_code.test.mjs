import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import { DEV_ONLY_MODULES, findDevOnlyCode, staleMarkers } from './check_web_dev_only_code.mjs';
import { jsFiles } from './check_web_removed_kit_apis.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const MODULES = [{ source: 'apps/web/src/lib/routes/dev_thing.ts', marker: '[dev-thing]' }];

/** @param {Record<string, string>} files */
function fixture(files) {
	const root = mkdtempSync(join(tmpdir(), 'dev-only-code-'));
	for (const [path, text] of Object.entries(files)) {
		mkdirSync(join(root, path, '..'), { recursive: true });
		writeFileSync(join(root, path), text);
	}
	return root;
}

test('flags a chunk that carries a dev-only marker', () => {
	const root = fixture({
		'immutable/chunks/Ab12.js': 'console.info(`[dev-thing] viewport outside; showing ${a}`);',
		'immutable/entry/app.js': 'export const ok = 1;',
	});
	try {
		assert.deepEqual(findDevOnlyCode(root, jsFiles(root), MODULES), [
			{ file: join('immutable', 'chunks', 'Ab12.js'), source: MODULES[0].source },
		]);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('passes a client without the marker, and ignores non-JS output', () => {
	const root = fixture({ 'a.js': 'const dev = "[dev-other]";', 'b.css': '/* [dev-thing] */' });
	try {
		assert.deepEqual(findDevOnlyCode(root, jsFiles(root), MODULES), []);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('a marker its source no longer carries is reported stale', () => {
	assert.deepEqual(staleMarkers(MODULES, () => 'console.info("[dev-thing] hi")'), []);
	assert.deepEqual(staleMarkers(MODULES, () => 'console.info("renamed")'), MODULES);
	assert.deepEqual(
		staleMarkers(MODULES, () => {
			throw new Error('ENOENT');
		}),
		MODULES,
	);
});

test('every registered module still carries its marker', () => {
	assert.deepEqual(
		staleMarkers(DEV_ONLY_MODULES, (p) => readFileSync(join(REPO_ROOT, p), 'utf8')),
		[],
	);
});
