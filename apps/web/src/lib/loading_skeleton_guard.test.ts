// A page loading its content shows a skeleton shaped like the page it becomes
// (decisions § 2288), never the running-figure loader that used to stand in
// the middle of an empty page.
//
// The figure held none of the layout the content would take, so the arriving
// frame landed as a re-layout, and it made a second loading language beside
// the `.skel` rows the list pages already drew. A wait that is not page
// content (GPS acquisition, finishing a sign-in) may earn an indicator of its
// own, but under a new name and with a reason recorded here, not this one.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';

// cwd is apps/web (see `test:unit` in package.json).
const SRC = 'src';
const SELF = join('src', 'lib', 'loading_skeleton_guard.test.ts');

function walk(dir: string): string[] {
	return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
		const p = join(dir, e.name);
		if (e.isDirectory()) return walk(p);
		return /\.(svelte|ts|js)$/.test(e.name) ? [p] : [];
	});
}

test('no page loads its content behind the running figure', () => {
	const files = walk(SRC).filter((f) => f !== SELF);
	assert.ok(files.length > 100, 'the walk must actually reach the source tree');
	const offenders = files.filter((f) => /\bActivityLoader\b/.test(readFileSync(f, 'utf-8')));
	assert.deepEqual(
		offenders.map((f) => relative(SRC, f)),
		[],
		'compose SkeletonBlock (lib/components/SkeletonBlock.svelte) or the page-local ' +
			'.skel rows into the shape the page settles into, with one role="status" line'
	);
	assert.equal(existsSync(join(SRC, 'lib', 'components', 'ActivityLoader.svelte')), false);
});

test('the pages that took the figure hold their layout with a skeleton', () => {
	for (const page of [
		'routes/runs/heatmap/+page.svelte',
		'routes/gym/routines/+page.svelte',
		'routes/nutrition/[date]/[slot]/+page.svelte',
	]) {
		const src = readFileSync(join(SRC, page), 'utf-8');
		assert.match(src, /<SkeletonBlock\b/, `${page} must draw a skeleton while it loads`);
		assert.match(
			src,
			/class="visually-hidden" role="status"/,
			`${page} must announce the load once, not once per block`
		);
	}
});
