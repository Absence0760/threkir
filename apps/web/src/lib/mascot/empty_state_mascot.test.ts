import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

import { emptyStateShowsMascot } from './mascot.ts';

// Grisnir waits only in the "nothing yet" states that name him, never in an
// error or failure state (#1364, apps/web/static/brand/grisnir/README.md).

const SRC = resolve(new URL('.', import.meta.url).pathname, '../..');

test('an empty state shows him only when opted in, known and on', () => {
	const on = { mascot: true, tone: 'neutral', role: undefined, prefShown: true };
	assert.equal(emptyStateShowsMascot(on), true);
	assert.equal(emptyStateShowsMascot({ ...on, mascot: undefined }), false);
	assert.equal(emptyStateShowsMascot({ ...on, prefShown: null }), false, 'unknown setting: hidden, no flash');
	assert.equal(emptyStateShowsMascot({ ...on, prefShown: false }), false);
});

test('an error or failure empty state refuses him whatever is passed', () => {
	const on = { mascot: true, tone: 'neutral', role: undefined, prefShown: true };
	assert.equal(emptyStateShowsMascot({ ...on, tone: 'danger' }), false);
	assert.equal(emptyStateShowsMascot({ ...on, role: 'alert' }), false);
	assert.equal(emptyStateShowsMascot({ ...on, role: 'alertdialog' }), false);
});

function svelteFiles(dir: string): string[] {
	const out: string[] = [];
	for (const e of readdirSync(dir, { withFileTypes: true })) {
		if (e.name === 'node_modules' || e.name.startsWith('.')) continue;
		const p = join(dir, e.name);
		if (e.isDirectory()) out.push(...svelteFiles(p));
		else if (e.name.endsWith('.svelte')) out.push(p);
	}
	return out;
}

test('EmptyState decides through emptyStateShowsMascot, so its error variants refuse him', () => {
	const src = readFileSync(join(SRC, 'lib/components/EmptyState.svelte'), 'utf8');
	assert.match(src, /emptyStateShowsMascot\(\{ mascot, tone, role: rest\.role, prefShown \}\)/);
	assert.match(src, /\{#if showMascot\}\s*<GrisnirArt/);
});

test('only the named "nothing yet" states opt in, and none of them is an error', () => {
	const optedIn: string[] = [];
	for (const file of svelteFiles(SRC)) {
		const text = readFileSync(file, 'utf8');
		for (const m of text.matchAll(/<EmptyState\b([^>]*?)>/gs)) {
			if (!/\bmascot\b(?!=\{false\})/.test(m[1])) continue;
			const rel = relative(SRC, file);
			assert.doesNotMatch(m[1], /tone="danger"|role="alert"/, `${rel}: Grisnir on an error state`);
			optedIn.push(rel);
		}
	}
	assert.deepEqual(optedIn.sort(), [
		'lib/components/SocialFeed.svelte',
		'routes/routes/+page.svelte',
		'routes/runs/+page.svelte',
	]);
});
