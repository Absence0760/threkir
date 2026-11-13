import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { parse } from 'svelte/compiler';

// A section's heading is `SectionHeader` (conventions.md § Web section
// headers; issue #1374), the twin of ui_kit's `SectionHeader`: the eyebrow
// over a group, or the `title` form of an in-body section, with an optional
// action that wraps under it. Before it, each page drew its own: a
// `.section-title` h2 in four sizes and three colours, the global
// `.section-label` micro-label pressed into service as a card's heading on a
// `<span>` no screen reader could find, and h2s uppercased by a page rule.
//
// This counts, per file, the hand-built section headings left:
//   - an element with a `section-title` class, or a `.section-title` rule;
//   - the `section-label` class on a heading, on a `<p>`, or as the one label
//     directly in a `*-head` / `*-header` row (a card head) — the micro-label class is
//     still right for a field's or a stat's caption, or a row of column
//     captions, which this leaves alone;
//   - an h2–h6 whose own class a rule in the file uppercases;
//   - a rule in the file that uppercases h2–h6 elements (`.card h2 { … }`).
// The counts may only shrink: a file over its count fails, and so does one
// under it until the entry is lowered or removed.

const SRC = resolve(new URL('.', import.meta.url).pathname, '..');
const COMPONENT = 'lib/components/SectionHeader.svelte';
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

/// Hand-built section headings left to migrate.
const LEFT: Record<string, number> = {};

type Attr = { type?: string; name?: string; value?: unknown };
type Node = { type?: string; name?: string; attributes?: Attr[]; fragment?: { nodes?: unknown[] } };

function staticClasses(el: Node): string[] {
	for (const a of el.attributes ?? []) {
		if (a.type !== 'Attribute' || a.name !== 'class') continue;
		const parts = Array.isArray(a.value) ? a.value : [a.value];
		return parts
			.map((p) => (p && typeof p === 'object' && 'data' in p ? String((p as { data: unknown }).data) : ' '))
			.join('')
			.split(/\s+/)
			.filter(Boolean);
	}
	return [];
}

const HEADING = /^h[2-6]$/;
const HEAD_ROW = /(^|-)head(er)?$/;
const UPPER = /text-transform\s*:\s*uppercase/;

/// The rules of a style block, flattened out of any `@media` / `:global {}`
/// nesting: [selector list, declarations].
function rules(css: string): [string, string][] {
	const out: [string, string][] = [];
	for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) out.push([m[1].trim(), m[2]]);
	return out;
}

function handBuiltSectionHeads(source: string): number {
	const root = parse(source, { modern: true });
	const css = root.css
		? source.slice(root.css.content.start, root.css.content.end).replace(/\/\*[\s\S]*?\*\//g, '')
		: '';
	const upperClasses = new Set<string>();
	let n = 0;
	for (const [selectors, body] of rules(css)) {
		if (/\.section-title(?![\w-])/.test(selectors)) n++;
		if (!UPPER.test(body)) continue;
		for (const sel of selectors.split(',')) {
			const last = sel.trim().split(/[\s>+~]+/).pop() ?? '';
			if (/^h[2-6](?![\w-])/.test(last)) n++;
			for (const c of last.matchAll(/\.([\w-]+)/g)) upperClasses.add(c[1]);
		}
	}
	// The micro-labels that are direct children of an element.
	const childLabels = (el: Node): number =>
		(el.fragment?.nodes ?? []).filter((c) => {
			const child = c as Node;
			return child.type === 'RegularElement' && staticClasses(child).includes('section-label');
		}).length;
	const visit = (node: unknown): void => {
		if (Array.isArray(node)) return node.forEach(visit);
		if (!node || typeof node !== 'object') return;
		const el = node as Node;
		if (el.type === 'RegularElement') {
			const own = staticClasses(el);
			const heading = HEADING.test(el.name ?? '');
			if (own.includes('section-title')) n++;
			else if (own.includes('section-label') && (heading || el.name === 'p')) n++;
			else if (heading && own.some((c) => upperClasses.has(c))) n++;
			// A head row with ONE micro-label is a card's heading; a row of
			// several is a grid's column captions, which is what the class is for.
			if (own.some((c) => HEAD_ROW.test(c)) && childLabels(el) === 1) n++;
		}
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value);
	};
	visit(root.fragment);
	return n;
}

const FIXTURES: { source: string; count: number; why: string }[] = [
	{ source: '<h2 class="section-title">x</h2>', count: 1, why: 'a section-title heading' },
	{ source: '<h2 class="section-title">x</h2><style>.section-title { margin: 0; }</style>', count: 2, why: 'the class and its rule' },
	{ source: '<h3 class="section-label">x</h3>', count: 1, why: 'the micro-label as a heading' },
	{ source: '<p class="section-label">x</p>', count: 1, why: 'the micro-label as a paragraph heading' },
	{ source: '<div class="card-head"><span class="section-label">x</span><a href="/">y</a></div>', count: 1, why: 'a card head' },
	{ source: '<header class="section-header"><span class="section-label">x</span></header>', count: 1, why: 'a header row' },
	{ source: '<label><span class="section-label">Name</span><input /></label>', count: 0, why: 'a field caption' },
	{ source: '<div class="stat"><span class="stat-label section-label">Distance</span></div>', count: 0, why: 'a stat caption' },
	{ source: '<div class="set-head"><span class="section-label">Reps</span><span class="section-label">Weight</span></div>', count: 0, why: 'a row of column captions' },
	{ source: '<header class="band-head"><p>Set 1</p><div class="target"><span class="section-label">Target</span></div></header>', count: 0, why: 'a stat caption deeper in a header' },
	{ source: '<h2 class="eyebrow">x</h2><style>.eyebrow { text-transform: uppercase; }</style>', count: 1, why: 'an h2 uppercased by its class' },
	{ source: '<span class="eyebrow">x</span><style>.eyebrow { text-transform: uppercase; }</style>', count: 0, why: 'an uppercased span is not a heading' },
	{ source: '<div class="card"><h2>x</h2></div><style>.card h2 { text-transform: uppercase; }</style>', count: 1, why: 'a rule uppercasing h2s' },
	{ source: '<style>.x :global { h2 { text-transform: uppercase; } }</style>', count: 1, why: 'a nested :global rule' },
	{ source: '<h2>x</h2><style>.card h2 { font-weight: 700; }</style>', count: 0, why: 'an ordinary heading rule' },
	{ source: '<style>/* .section-title { } */ .x { gap: 0; }</style>', count: 0, why: 'a CSS comment' },
	{ source: '<SectionHeader label="x" />', count: 0, why: 'the component' },
	{ source: '<div class="section-title-row"></div>', count: 0, why: 'a longer class name' },
];

test('the matcher counts hand-built section headings and spares look-alikes', () => {
	for (const f of FIXTURES) assert.equal(handBuiltSectionHeads(f.source), f.count, f.why);
});

function walk(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		if (SKIP_DIRS.has(entry.name)) continue;
		const path = join(dir, entry.name);
		if (entry.isDirectory()) walk(path, out);
		else if (entry.name.endsWith('.svelte')) out.push(path);
	}
	return out;
}

const counts = new Map<string, number>();
for (const path of walk(SRC)) {
	const rel = relative(SRC, path);
	if (rel === COMPONENT) continue;
	const n = handBuiltSectionHeads(readFileSync(path, 'utf8'));
	if (n > 0) counts.set(rel, n);
}

test('the component exists', () => {
	assert.ok(existsSync(join(SRC, COMPONENT)));
});

test('no hand-built section heading past the counts left', () => {
	const problems: string[] = [];
	for (const [file, n] of counts) {
		const allowed = LEFT[file] ?? 0;
		if (n > allowed) problems.push(`  src/${file}: ${n} hand-built section headings, ${allowed} allowed; render SectionHeader`);
	}
	for (const [file, allowed] of Object.entries(LEFT)) {
		const n = counts.get(file) ?? 0;
		if (n < allowed) problems.push(`  src/${file}: ${n} hand-built section headings, ${allowed} listed; lower LEFT`);
	}
	assert.deepEqual(problems, [], 'conventions.md § Web section headers:\n' + problems.join('\n'));
});
