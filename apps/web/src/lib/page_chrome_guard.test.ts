import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { parse } from 'svelte/compiler';

// A list's search is `AppSearchField` inside `FilterBar`, and a page's title
// block is `PageHeader` (conventions.md § Web lists — FilterBar,
// AppSearchField and PageHeader; issue #1374). Before them, ten files built
// their own `type="search"` input in about five styles, some with no clear
// button, and twenty routes copied a `.page-header` block whose kicker, title
// size and subtitle drifted page by page. This fails on a new copy of either:
// an `<input type="search">` or a `.page-header` class (in markup or a style
// rule) in any `.svelte` file other than the components.
//
// An ALLOW entry is a file that cannot move yet, with the reason. The list may
// only shrink: an entry whose file no longer needs the exemption fails, so a
// reason cannot outlive the code it excused.

const SRC = resolve(new URL('.', import.meta.url).pathname, '..');
const COMPONENTS = new Set([
	'lib/components/AppSearchField.svelte',
	'lib/components/FilterBar.svelte',
	'lib/components/PageHeader.svelte',
]);
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

type Kind = 'search' | 'page-header' | 'h1';

const ALLOW: { file: string; kind: Kind; why: string }[] = [
	{
		file: 'lib/components/help/HelpSearchForm.svelte',
		kind: 'search',
		why: 'a GET form submitted with its own button (`name="q"`), not a live list filter',
	},
	...h1Allow(
		'the marketing landing and comparison pages: a hero headline, not an app title block',
		['routes/+page.svelte', 'routes/compare/+page.svelte'],
	),
	...h1Allow('a public /learn article or index, styled as long-form prose under the learn chrome', [
		'routes/learn/+page.svelte',
		'routes/learn/[slug]/+page.svelte',
		'routes/learn/category/[category]/+page.svelte',
	]),
	...h1Allow('a legal document: the h1 opens `.legal-page` prose with its lead and last-updated line', [
		'routes/cookie-notice/+page.svelte',
		'routes/delete-account/+page.svelte',
		'routes/health-data-notice/+page.svelte',
		'routes/privacy/+page.svelte',
		'routes/terms/+page.svelte',
	]),
	...h1Allow('a public /share card: the h1 sits inside the shared entity card, not the app shell', [
		'routes/share/badge/[id]/+page.svelte',
		'routes/share/challenge/[id]/+page.svelte',
		'routes/share/club/[slug]/+page.svelte',
		'routes/share/course/[region]/[park]/[course]/+page.svelte',
		'routes/share/event/[id]/+page.svelte',
		'routes/share/event/[id]/results/+page.svelte',
		'routes/share/plan/[id]/+page.svelte',
		'routes/share/profile/[id]/+page.svelte',
		'routes/share/race/[id]/+page.svelte',
		'routes/share/route/[id]/+page.svelte',
		'routes/share/run/[id]/+page.svelte',
		'routes/share/session/[id]/+page.svelte',
		'routes/share/workout/[id]/+page.svelte',
	]),
	...h1Allow('an auth, onboarding or token-link card: one centred card per state, outside the app chrome', [
		'routes/auth/confirm-age/+page.svelte',
		'routes/auth/reset/+page.svelte',
		'routes/login/+page.svelte',
		'routes/onboarding/+page.svelte',
		'routes/challenges/join/[token]/+page.svelte',
		'routes/clubs/join/[token]/+page.svelte',
		'routes/coaching/accept/[token]/+page.svelte',
		'routes/club-verification/confirm/+page.svelte',
		'routes/safety/confirm/+page.svelte',
	]),
	...h1Allow('an entity hero: the h1 sits in a hero with a map, cover, stats, chips or a live state', [
		'routes/challenges/[id]/+page.svelte',
		'routes/clubs/[slug]/+page.svelte',
		'routes/clubs/[slug]/events/[id]/+page.svelte',
		'routes/guided/[id]/+page.svelte',
		'routes/live/[id]/+page.svelte',
		'routes/live/event/[id]/[instance]/+page.svelte',
		'routes/parks/[region]/[park]/+page.svelte',
		'routes/parks/[region]/[park]/[course]/+page.svelte',
		'routes/plans/[id]/+page.svelte',
		'routes/plans/[id]/workouts/[wid]/+page.svelte',
		'routes/races/[id]/+page.svelte',
		'routes/recap/[year]/+page.svelte',
		'routes/recap/[year]/[month]/+page.svelte',
		'routes/recap/share/[id]/+page.svelte',
		'routes/runs/[id]/+page.svelte',
		'routes/segments/[id]/+page.svelte',
		'routes/u/[id]/+page.svelte',
	]),
	{
		file: 'routes/guided/+page.svelte',
		kind: 'h1',
		why: 'a public, indexed library landing with a centred marketing hero (kicker, large headline, note pill)',
	},
	{
		file: 'routes/help/[id]/+page.svelte',
		kind: 'h1',
		why: "a help guide article: the h1 carries the guide's own `lang` inside the article with its badges",
	},
	{
		file: 'routes/routes/[id]/roadbook/+page.svelte',
		kind: 'h1',
		why: 'a printable roadbook: the header is part of the printed document and its actions are `no-print`',
	},
	{
		file: 'routes/routes/new/+page.svelte',
		kind: 'h1',
		why: "the route builder: the h1 heads the builder's sidebar panel beside the map, not a page column",
	},
	{
		file: 'routes/routes/[id]/+page.svelte',
		kind: 'h1',
		why: 'the route detail: its title row sits over the route map with stats and actions, and its load-failure and not-found states keep their own cards',
	},
];

function h1Allow(why: string, files: string[]): { file: string; kind: Kind; why: string }[] {
	return files.map((file) => ({ file, kind: 'h1' as const, why }));
}

// `type="search"` on an input element. Svelte's parser finds the elements, so
// a string in a script or a comment cannot trip it.
function searchInputs(source: string): number {
	let n = 0;
	const visit = (node: unknown): void => {
		if (Array.isArray(node)) return node.forEach(visit);
		if (!node || typeof node !== 'object') return;
		const el = node as {
			type?: string;
			name?: string;
			attributes?: { type?: string; name?: string; value?: unknown }[];
		};
		if (el.type === 'RegularElement' && el.name === 'input') {
			for (const a of el.attributes ?? []) {
				if (a.type !== 'Attribute' || a.name !== 'type') continue;
				const parts = Array.isArray(a.value) ? a.value : [a.value];
				const text = parts
					.map((p) => (p && typeof p === 'object' && 'data' in p ? String((p as { data: unknown }).data) : ''))
					.join('');
				if (text === 'search') n++;
			}
		}
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value);
	};
	visit(parse(source, { modern: true }).fragment);
	return n;
}

// A raw `<h1>` element whose static class list does not include
// `visually-hidden` (an accessible name for a page whose visual title is its
// toolbar). PageHeader's h1 lives in the component, so a route rendering
// `<PageHeader>` has none of its own.
function rawH1s(source: string): number {
	let n = 0;
	const visit = (node: unknown): void => {
		if (Array.isArray(node)) return node.forEach(visit);
		if (!node || typeof node !== 'object') return;
		const el = node as { type?: string; name?: string; attributes?: { type?: string; name?: string; value?: unknown }[] };
		if (el.type === 'RegularElement' && el.name === 'h1') {
			const cls = (el.attributes ?? []).find((a) => a.type === 'Attribute' && a.name === 'class');
			const parts = cls ? (Array.isArray(cls.value) ? cls.value : [cls.value]) : [];
			const text = parts
				.map((p) => (p && typeof p === 'object' && 'data' in p ? String((p as { data: unknown }).data) : ''))
				.join('');
			if (!text.split(/\s+/).includes('visually-hidden')) n++;
		}
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value);
	};
	visit(parse(source, { modern: true }).fragment);
	return n;
}

// The `.page-header` class opening a style rule.
const RULE = /\.page-header(?![\w-])[^{};]*\{/;
// The class in markup: a static class attribute, a class directive, or a
// string inside a `class={...}` expression.
const MARKUP = /\bclass:page-header(?![\w-])|\bclass=["'{][^>]*?(?<![\w-])page-header(?![\w-])/;

function pageHeaderHits(source: string): boolean {
	const root = parse(source, { modern: true });
	const css = root.css ? source.slice(root.css.content.start, root.css.content.end).replace(/\/\*[\s\S]*?\*\//g, '') : '';
	const chars = source.split('');
	const blank = (start: number, end: number) => {
		for (let i = start; i < end; i++) if (chars[i] !== '\n') chars[i] = ' ';
	};
	if (root.css) blank(root.css.start, root.css.end);
	for (const script of [root.instance, root.module]) if (script) blank(script.start, script.end);
	const visit = (node: unknown): void => {
		if (Array.isArray(node)) return node.forEach(visit);
		if (!node || typeof node !== 'object') return;
		const n = node as { type?: string; start: number; end: number };
		if (n.type === 'Comment') return blank(n.start, n.end);
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value);
	};
	visit(root.fragment);
	return RULE.test(css) || MARKUP.test(chars.join(''));
}

const FIXTURES: { source: string; search: number; header: boolean; why: string }[] = [
	{ source: '<input type="search" />', search: 1, header: false, why: 'a hand-built search input' },
	{ source: '<input bind:value={q} type="search" placeholder="x" />', search: 1, header: false, why: 'type after other attributes' },
	{ source: '<input type="text" />', search: 0, header: false, why: 'a text input' },
	{ source: '<AppSearchField label="x" />', search: 0, header: false, why: 'the component' },
	{ source: '<script>const s = \'<input type="search">\';</script>', search: 0, header: false, why: 'a string in a script' },
	{ source: '<!-- <input type="search"> --><p>x</p>', search: 0, header: false, why: 'an HTML comment' },
	{ source: '<header class="page-header"><h1>x</h1></header>', search: 0, header: true, why: 'the copied markup' },
	{ source: '<div class="a page-header"></div>', search: 0, header: true, why: 'among other classes' },
	{ source: '<style>.page-header h1 { margin: 0; }</style>', search: 0, header: true, why: 'a style rule' },
	{ source: '<div class="page-header-row"></div><style>.page-headers { gap: 0; }</style>', search: 0, header: false, why: 'a longer class name' },
	{ source: '<div data-testid="page-header"></div>', search: 0, header: false, why: 'a test id, not a class' },
	{ source: '<style>/* .page-header { } */ .x { gap: 0; }</style>', search: 0, header: false, why: 'a CSS comment' },
];

const H1_FIXTURES: { source: string; h1: number; why: string }[] = [
	{ source: '<h1>Runs</h1>', h1: 1, why: 'a bare h1' },
	{ source: '<header class="head"><h1>{title}</h1><p class="subtitle">x</p></header>', h1: 1, why: 'a hand-built title block' },
	{ source: '<h1 class="hero-title">x</h1>', h1: 1, why: 'an h1 with another class' },
	{ source: '{#if ok}<h1>a</h1>{:else}<h1>b</h1>{/if}', h1: 2, why: 'one per branch' },
	{ source: '<h1 class="visually-hidden">Runs</h1>', h1: 0, why: 'a visually hidden h1' },
	{ source: '<h1 class="x visually-hidden">Runs</h1>', h1: 0, why: 'visually hidden among other classes' },
	{ source: '<PageHeader title="Runs" />', h1: 0, why: 'the component' },
	{ source: '<h2>Runs</h2>', h1: 0, why: 'an h2' },
	{ source: '<!-- <h1>x</h1> --><p>x</p>', h1: 0, why: 'an HTML comment' },
	{ source: '<script>const s = \'<h1>x</h1>\';</script>', h1: 0, why: 'a string in a script' },
];

test('the h1 matcher flags a raw h1 and spares a visually hidden one or the component', () => {
	for (const f of H1_FIXTURES) assert.equal(rawH1s(f.source), f.h1, `h1: ${f.why}`);
});

test('the matchers flag a search input and a page-header class and spare look-alikes', () => {
	for (const f of FIXTURES) {
		assert.equal(searchInputs(f.source), f.search, `search: ${f.why}`);
		assert.equal(pageHeaderHits(f.source), f.header, `page-header: ${f.why}`);
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

const offenders = new Set<string>();
for (const path of walk(SRC)) {
	const rel = relative(SRC, path);
	if (COMPONENTS.has(rel)) continue;
	const source = readFileSync(path, 'utf8');
	if (searchInputs(source) > 0) offenders.add(`${rel}|search`);
	if (pageHeaderHits(source)) offenders.add(`${rel}|page-header`);
	if (/^routes\/(.+\/)?\+page\.svelte$/.test(rel) && rawH1s(source) > 0) offenders.add(`${rel}|h1`);
}

test('the components exist', () => {
	for (const file of COMPONENTS) assert.ok(existsSync(join(SRC, file)), `${file} is what this guard steers toward`);
});

test('no file builds its own search input, page-header block or route h1', () => {
	const allowed = new Set(ALLOW.map((a) => `${a.file}|${a.kind}`));
	const failures = [...offenders].filter((o) => !allowed.has(o)).map((o) => {
		const [file, kind] = o.split('|');
		if (kind === 'search') return `  src/${file}: an <input type="search">; render AppSearchField (inside FilterBar for a list)`;
		if (kind === 'h1') return `  src/${file}: a hand-built <h1> title block; render PageHeader`;
		return `  src/${file}: a .page-header class; render PageHeader`;
	});
	assert.deepEqual(failures, [], 'conventions.md § Web lists — FilterBar, AppSearchField and PageHeader:\n' + failures.join('\n'));
});

test('every ALLOW entry still needs its exemption', () => {
	assert.equal(new Set(ALLOW.map((a) => `${a.file}|${a.kind}`)).size, ALLOW.length, 'an ALLOW entry is listed twice');
	for (const { file, kind, why } of ALLOW) {
		assert.ok(why.trim().length > 0, `${file}: an exemption needs a reason`);
		assert.ok(offenders.has(`${file}|${kind}`), `${file} no longer has a hand-built ${kind}; drop its ALLOW entry`);
	}
});
