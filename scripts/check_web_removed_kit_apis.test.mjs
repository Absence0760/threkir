import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { findRemovedApis, jsFiles } from './check_web_removed_kit_apis.mjs';

/** @param {Record<string, string>} files */
function fixture(files) {
	const root = mkdtempSync(join(tmpdir(), 'removed-kit-apis-'));
	for (const [path, text] of Object.entries(files)) {
		mkdirSync(join(root, path, '..'), { recursive: true });
		writeFileSync(join(root, path), text);
	}
	return root;
}

// The minified shape web@1.12.0 actually shipped in its Sentry chunk.
const STORES_STUB = 'function r(){throw new Error("https://svelte.dev/e/kit/app_stores_removed")}const p={subscribe:r};';

test('flags the $app/stores stub in a nested chunk', () => {
	const root = fixture({
		'immutable/chunks/CX5Sua7h.js': STORES_STUB,
		'immutable/entry/app.js': 'export const ok = 1;',
	});
	try {
		assert.deepEqual(findRemovedApis(root, jsFiles(root)), [
			{ file: join('immutable', 'chunks', 'CX5Sua7h.js'), code: 'app_stores_removed' },
		]);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('matches a future removed module by the naming pattern, not a list', () => {
	const root = fixture({ 'a.js': '"https://svelte.dev/e/kit/app_paths_removed"' });
	try {
		assert.deepEqual(findRemovedApis(root, jsFiles(root)).map((h) => h.code), ['app_paths_removed']);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});

test('passes a client with other Kit error URLs and no removed module', () => {
	const root = fixture({
		'a.js': '"https://svelte.dev/e/kit/navigation_failed" "https://svelte.dev/e/kit/app_stores_removed_note"',
		'b.css': 'https://svelte.dev/e/kit/app_stores_removed',
	});
	try {
		assert.deepEqual(findRemovedApis(root, jsFiles(root)), []);
	} finally {
		rmSync(root, { recursive: true, force: true });
	}
});
