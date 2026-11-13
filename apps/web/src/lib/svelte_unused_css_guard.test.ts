import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { compile } from 'svelte/compiler';

// `svelte-check` does not report the compiler's `css_unused_selector`, so a
// style whose markup was deleted passed `pnpm check` and shipped: the route
// page kept `.route-meta`, `.meta-sep`, `.surface-tag` and `.featured-pill`
// for markup that had moved into shared components. This compiles every
// component and fails on a selector that matches nothing it renders.
//
// A selector that styles markup the compiler cannot see (a child component's
// root, `{@html}` output) belongs under `:global(...)`, which the compiler
// does not check. ALLOWED is for the rare case that cannot be written that
// way; it may only shrink, and an entry that no longer fires fails.

const ROOT = resolve(import.meta.dirname, '../..');
const SRC = join(ROOT, 'src');

const ALLOWED: Record<string, string> = {};

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const name of readdirSync(dir)) {
		const p = join(dir, name);
		if (statSync(p).isDirectory()) svelteFiles(p, out);
		else if (p.endsWith('.svelte')) out.push(p);
	}
	return out;
}

function unusedSelectors(file: string): string[] {
	const { warnings } = compile(readFileSync(file, 'utf8'), { filename: file, generate: false });
	return warnings
		.filter((w) => w.code === 'css_unused_selector')
		.map((w) => `${relative(ROOT, file)}: ${w.message.split('\n')[0]}`);
}

test('no component keeps a style for markup it no longer renders', () => {
	const files = svelteFiles(SRC);
	assert.ok(files.length > 100, `found only ${files.length} components`);
	const found = files.flatMap(unusedSelectors);
	assert.deepEqual(
		found.filter((f) => !(f in ALLOWED)),
		[],
		'delete each selector, or move a style for markup the compiler cannot see under :global(...)',
	);
	for (const entry of Object.keys(ALLOWED)) {
		assert.ok(found.includes(entry), `${entry} is allowed but no longer fires; drop it`);
	}
});

test('the guard sees an unused selector', () => {
	const { warnings } = compile('<p class="a">x</p><style>.a { color: red } .gone { color: blue }</style>', {
		filename: 'Probe.svelte',
		generate: false,
	});
	assert.deepEqual(
		warnings.filter((w) => w.code === 'css_unused_selector').map((w) => w.message.split('\n')[0]),
		['Unused CSS selector ".gone"'],
	);
});
