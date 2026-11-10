import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

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

function styleBlocks(source: string): string {
	return [...source.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n');
}

function markup(source: string): string {
	return source
		.replace(/<style[^>]*>[\s\S]*?<\/style>/g, '')
		.replace(/<script[^>]*>[\s\S]*?<\/script>/g, '')
		.replace(/<!--[\s\S]*?-->/g, '');
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
