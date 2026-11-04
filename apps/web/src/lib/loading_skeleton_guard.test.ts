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

// One shimmer, in SkeletonBlock.svelte. Pages used to carry their own copy of
// the `.skel` rule and its keyframes (29 of them by 2026-11-03), each free to
// drift in tint, cadence or reduced-motion handling, and most painted
// --color-bg-tertiary, which in dark is byte-identical to --color-surface, so
// the block vanished on a card between sweeps.
const SKELETON_BLOCK = join('src', 'lib', 'components', 'SkeletonBlock.svelte');

// A keyframe that sweeps `background-position` is a shimmer whatever it is
// called; the name check catches one written some other way.
function handRolledShimmers(src: string): string[] {
	const found: string[] = [];
	const kf = /@keyframes\s+([\w-]+)\s*\{/g;
	for (let m = kf.exec(src); m; m = kf.exec(src)) {
		let depth = 1;
		let i = kf.lastIndex;
		while (i < src.length && depth > 0) {
			if (src[i] === '{') depth++;
			else if (src[i] === '}') depth--;
			i++;
		}
		const body = src.slice(kf.lastIndex, i);
		if (/shimmer|skel/i.test(m[1]) || /background-position/.test(body)) {
			found.push(`@keyframes ${m[1]}`);
		}
	}
	if (/\.skel(?![\w-])/.test(src)) found.push('.skel selector');
	if (/class(?::[\w-]+)?=["{][^"}]*(?<![\w-])skel(?![\w-])/.test(src)) found.push('class="skel"');
	return found;
}

test('handRolledShimmers flags the copied shape and spares the shared one', () => {
	assert.deepEqual(
		handRolledShimmers(
			'<span class="skel skel-line"></span>\n.skel { animation: skel-shimmer 1.4s; }\n' +
				'@keyframes skel-shimmer { 0% { background-position: 200% 0; } }'
		),
		['@keyframes skel-shimmer', '.skel selector', 'class="skel"']
	);
	assert.deepEqual(
		handRolledShimmers('@keyframes wave { to { background-position: -100% 0; } }'),
		['@keyframes wave']
	);
	assert.deepEqual(
		handRolledShimmers(
			'<div class="skel-card"><SkeletonBlock height="1rem" /></div>\n' +
				'.skel-card { display: flex; }\n@keyframes pulse { 50% { opacity: 0.4; } }'
		),
		[]
	);
});

test('no page hand-rolls a skeleton shimmer; SkeletonBlock is the one implementation', () => {
	const files = [...walk(SRC).filter((f) => f.endsWith('.svelte')), join(SRC, 'app.css')].filter(
		(f) => f !== SKELETON_BLOCK
	);
	const offenders = files.flatMap((f) =>
		handRolledShimmers(readFileSync(f, 'utf-8')).map((hit) => `${relative(SRC, f)}: ${hit}`)
	);
	assert.deepEqual(
		offenders,
		[],
		'draw a loading placeholder with <SkeletonBlock height= width= radius=> ' +
			'(lib/components/SkeletonBlock.svelte); a `.skel-*` layout wrapper is fine, ' +
			'a copied `.skel` fill or shimmer keyframe is not'
	);
	const block = readFileSync(SKELETON_BLOCK, 'utf-8');
	assert.match(
		block,
		/prefers-reduced-motion:\s*reduce/,
		'the shared shimmer must freeze under reduced motion'
	);
	assert.match(
		block,
		/--color-fill-subtle/,
		'a skeleton is a subtle FILL (conventions.md § Web boundaries)'
	);
});
