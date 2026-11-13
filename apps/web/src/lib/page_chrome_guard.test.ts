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

type Kind = 'search' | 'page-header';

const ALLOW: { file: string; kind: Kind; why: string }[] = [
	{
		file: 'lib/components/help/HelpSearchForm.svelte',
		kind: 'search',
		why: 'a GET form submitted with its own button (`name="q"`), not a live list filter',
	},
	{
		file: 'lib/components/SocialDiscover.svelte',
		kind: 'search',
		why: 'Social tab bodies move onto FilterBar with the Social hub work (#1374 batch 3), owned there',
	},
	{
		file: 'lib/components/SocialPeople.svelte',
		kind: 'search',
		why: 'Social tab bodies move onto FilterBar with the Social hub work (#1374 batch 3), owned there',
	},
	{
		file: 'routes/messages/+layout.svelte',
		kind: 'search',
		why: 'Messages moves into Social in #1374 batch 3, which owns its list controls',
	},
	{
		file: 'routes/segments/+page.svelte',
		kind: 'search',
		why: 'Segments folds into Routes (#1374 owner decision 1); that change owns the page',
	},
	{
		file: 'routes/segments/+page.svelte',
		kind: 'page-header',
		why: 'Segments folds into Routes (#1374 owner decision 1); that change owns the page',
	},
	{
		file: 'routes/routes/+page.svelte',
		kind: 'page-header',
		why: 'its tab strip is reordered by the Routes `Mine · Explore` change (#1374), which owns the header',
	},
];

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
}

test('the components exist', () => {
	for (const file of COMPONENTS) assert.ok(existsSync(join(SRC, file)), `${file} is what this guard steers toward`);
});

test('no file builds its own search input or copies the page-header block', () => {
	const allowed = new Set(ALLOW.map((a) => `${a.file}|${a.kind}`));
	const failures = [...offenders].filter((o) => !allowed.has(o)).map((o) => {
		const [file, kind] = o.split('|');
		return kind === 'search'
			? `  src/${file}: an <input type="search">; render AppSearchField (inside FilterBar for a list)`
			: `  src/${file}: a .page-header class; render PageHeader`;
	});
	assert.deepEqual(failures, [], 'conventions.md § Web lists — FilterBar, AppSearchField and PageHeader:\n' + failures.join('\n'));
});

test('every ALLOW entry still needs its exemption', () => {
	for (const { file, kind, why } of ALLOW) {
		assert.ok(why.trim().length > 0, `${file}: an exemption needs a reason`);
		assert.ok(offenders.has(`${file}|${kind}`), `${file} no longer has a hand-built ${kind}; drop its ALLOW entry`);
	}
});
