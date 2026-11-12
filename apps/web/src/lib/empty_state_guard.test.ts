import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { parse } from 'svelte/compiler';

// A whole-surface "nothing here" state renders EmptyState.svelte
// (conventions.md § Web empty states). Before it existed, every page that
// needed one copied a page-local `.empty-card` rule, and the copies drifted:
// the five run-surface tabs alone had five looks, and three pages carried the
// class with no rule behind it at all, so their empty state rendered as bare
// unstyled text. This fails on a new copy in either form: a style rule for an
// `*empty-card` class, or markup that names one.
//
// An entry in ALLOW is a file that genuinely cannot use EmptyState yet, with
// the reason. The guard fails when an entry no longer needs the exemption, so
// a reason cannot outlive the code it excused.

const SRC = resolve(new URL('.', import.meta.url).pathname, '..');
const PRIMITIVE = 'lib/components/EmptyState.svelte';
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

const ALLOW: { file: string; why: string }[] = [];

// `.empty-card` or a prefixed variant (`.goals-empty-card`) used as a class
// in a selector that opens a rule. A longer class that merely contains the
// word (`.empty-cards`, `.empty-card-x`) is a different class.
const RULE = /\.((?:[\w-]*-)?empty-card)(?![\w-])[^{};]*\{/g;

// The same class named in markup: a static `class` attribute, a `class:`
// directive, or a string inside a `class={...}` expression.
const MARKUP = /(?:\bclass:((?:[\w-]*-)?empty-card)(?![\w-]))|(?:\bclass=["'{][^>]*?(?<![\w-])((?:[\w-]*-)?empty-card)(?![\w-]))/g;

function stripComments(css: string): string {
	return css.replace(/\/\*[\s\S]*?\*\//g, '');
}

type Span = { start: number; end: number };
type Parts = { css: Span[]; hidden: Span[] };

// Svelte's own parser says where the style sheets, scripts and comments are,
// so a `</script>` inside a string or a tag split across a comment cannot
// fool it the way a regex stripper can.
function parts(source: string): Parts {
	const root = parse(source, { modern: true });
	const out: Parts = { css: [], hidden: [] };
	if (root.css) {
		out.css.push(root.css.content);
		out.hidden.push(root.css);
	}
	for (const script of [root.instance, root.module]) if (script) out.hidden.push(script);
	const visit = (node: unknown): void => {
		if (Array.isArray(node)) return node.forEach(visit);
		if (!node || typeof node !== 'object') return;
		const n = node as { type?: string; name?: string; start: number; end: number; fragment?: { nodes: unknown[] } };
		if (n.type === 'Comment') return void out.hidden.push(n);
		if (n.type === 'RegularElement' && (n.name === 'style' || n.name === 'script')) {
			const body = n.fragment?.nodes ?? [];
			if (n.name === 'style' && body.length > 0) {
				out.css.push({ start: (body[0] as Span).start, end: (body[body.length - 1] as Span).end });
			}
			return void out.hidden.push(n);
		}
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value);
	};
	visit(root.fragment);
	return out;
}

function styleBlocks(source: string): string {
	return parts(source).css.map((s) => source.slice(s.start, s.end)).join('\n');
}

// Blanks rather than deletes, so nothing outside a hidden span moves or joins.
function markup(source: string): string {
	const chars = source.split('');
	for (const { start, end } of parts(source).hidden) {
		for (let i = start; i < end; i++) if (chars[i] !== '\n') chars[i] = ' ';
	}
	return chars.join('');
}

function ruleHits(source: string): string[] {
	return [...stripComments(styleBlocks(source)).matchAll(RULE)].map((m) => m[1]);
}

function markupHits(source: string): string[] {
	return [...markup(source).matchAll(MARKUP)].map((m) => m[1] ?? m[2]);
}

const FIXTURES: { source: string; rules: string[]; markup: string[]; why: string }[] = [
	{ source: '<style>.empty-card { display: flex; }</style>', rules: ['empty-card'], markup: [], why: 'the plain rule' },
	{ source: '<style>.empty-card h3 { margin: 0; }</style>', rules: ['empty-card'], markup: [], why: 'a descendant rule' },
	{ source: '<style>.a,\n\t.goals-empty-card { gap: 0; }</style>', rules: ['goals-empty-card'], markup: [], why: 'a prefixed class in a selector list' },
	{ source: '<style>@media (max-width: 1px) { .empty-card { gap: 0; } }</style>', rules: ['empty-card'], markup: [], why: 'inside a media query' },
	{ source: '<div class="card empty-card">x</div>', rules: [], markup: ['empty-card'], why: 'the class in static markup' },
	{ source: '<div class:goals-empty-card={on}>x</div>', rules: [], markup: ['goals-empty-card'], why: 'a class directive' },
	{ source: "<div class={on ? 'empty-card' : ''}>x</div>", rules: [], markup: ['empty-card'], why: 'a class expression' },
	{ source: '<style>/* the old .empty-card { } shape */ .x { gap: 0; }</style>', rules: [], markup: [], why: 'a comment naming the class' },
	{ source: '<style>.empty-cards { gap: 0; } .empty-card-row { gap: 0; }</style>', rules: [], markup: [], why: 'a longer class name is another class' },
	{ source: '<div class="empty-state">x</div><p>empty-card</p>', rules: [], markup: [], why: 'the word outside a class attribute' },
	{ source: '<!-- <div class="empty-card"> --><div class="x"></div>', rules: [], markup: [], why: 'an HTML comment' },
	{ source: '<script>const s = "<div class=\\"empty-card\\">";</script><div class="x"></div>', rules: [], markup: [], why: 'a string inside the script' },
	{ source: '<svelte:head><style>.empty-card { gap: 0; }</style></svelte:head>', rules: ['empty-card'], markup: [], why: 'a style element nested in markup' },
];

test('the empty-card matchers flag rules and markup and spare comments and longer names', () => {
	for (const f of FIXTURES) {
		assert.deepEqual(ruleHits(f.source), f.rules, `rules: ${f.why}`);
		assert.deepEqual(markupHits(f.source), f.markup, `markup: ${f.why}`);
	}
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

const offenders = new Map<string, string[]>();
for (const path of walk(SRC)) {
	const rel = relative(SRC, path);
	if (rel === PRIMITIVE) continue;
	const source = readFileSync(path, 'utf8');
	const hits = [
		...ruleHits(source).map((c) => `defines .${c}`),
		...markupHits(source).map((c) => `uses class "${c}"`),
	];
	if (hits.length > 0) offenders.set(rel, hits);
}

test('the shared primitive exists', () => {
	assert.ok(existsSync(join(SRC, PRIMITIVE)), `${PRIMITIVE} is the primitive this guard steers toward`);
});

test('no page or component hand-rolls an empty-card instead of rendering EmptyState', () => {
	const allowed = new Set(ALLOW.map((a) => a.file));
	const failures = [...offenders]
		.filter(([file]) => !allowed.has(file))
		.map(([file, hits]) => `  src/${file}: ${hits.join(', ')}`);
	assert.deepEqual(
		failures,
		[],
		'Render <EmptyState> from #lib/components/EmptyState.svelte for a whole-surface empty, ' +
			'filtered-empty or failed-read state, and delete the local rule (conventions.md § Web empty states):\n' +
			failures.join('\n'),
	);
});

test('every ALLOW entry still needs its exemption', () => {
	for (const { file, why } of ALLOW) {
		assert.ok(why.trim().length > 0, `${file}: an exemption needs a reason`);
		assert.ok(offenders.has(file), `${file} no longer defines or uses an empty-card class; drop its ALLOW entry`);
	}
});
