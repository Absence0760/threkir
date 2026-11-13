import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { parse } from 'svelte/compiler';

// A card in a list is `ListCard` (conventions.md § Web list cards; issue
// #1374), the twin of ui_kit's `ListCard`. Before it, every list styled its
// own tappable card — `.card-elevated workout-row`, `.routine-row`,
// `.plan-row`, `a.card` — each with its own padding, title size, hover and
// focus ring. This counts, per file, the links and buttons inside an
// `{#each}` whose class names a card or a row (`card`, `card-elevated`,
// `*-card`, `*-row`): a list item drawn by hand. The counts may only shrink: a
// file over its count fails, and so does one under it until the entry is
// lowered or removed.

const SRC = resolve(new URL('.', import.meta.url).pathname, '..');
const COMPONENT = 'lib/components/ListCard.svelte';
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

/// Hand-built list cards left to migrate.
const LEFT: Record<string, number> = {
	'lib/components/GymRoutineHistory.svelte': 1,
	'lib/components/PeriodSummary.svelte': 1,
	'lib/components/PlanEditor.svelte': 1,
	'lib/components/RouteHeatmap.svelte': 1,
	'lib/components/RunSegmentEfforts.svelte': 2,
	'lib/components/SegmentsPanel.svelte': 1,
	'lib/components/SocialClubs.svelte': 1,
	'lib/components/SocialDiscover.svelte': 1,
	'lib/components/SocialPeople.svelte': 2,
	'lib/components/TimelineDayList.svelte': 1,
	'routes/clubs/[slug]/+page.svelte': 2,
	'routes/dashboard/+page.svelte': 3,
	'routes/guided/+page.svelte': 1,
	'routes/gym/records/+page.svelte': 1,
	'routes/help/+page.svelte': 1,
	'routes/messages/+layout.svelte': 1,
	'routes/messages/coach/+page.svelte': 1,
	'routes/onboarding/+page.svelte': 2,
	'routes/parks/[region]/[park]/+page.svelte': 1,
	'routes/races/[id]/+page.svelte': 1,
	'routes/routes/+page.svelte': 1,
	'routes/u/[id]/+page.svelte': 1,
};

const CARD_CLASS = /^(card|card-elevated|[\w-]+-(card|row))$/;

type Node = {
	type?: string;
	name?: string;
	attributes?: { type?: string; name?: string; value?: unknown }[];
};

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

function handBuiltCards(source: string): number {
	let n = 0;
	const visit = (node: unknown, inEach: boolean): void => {
		if (Array.isArray(node)) return node.forEach((c) => visit(c, inEach));
		if (!node || typeof node !== 'object') return;
		const el = node as Node;
		const each = inEach || el.type === 'EachBlock';
		if (
			each &&
			el.type === 'RegularElement' &&
			(el.name === 'a' || el.name === 'button') &&
			staticClasses(el).some((c) => CARD_CLASS.test(c))
		) {
			n++;
		}
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value, each);
	};
	visit(parse(source, { modern: true }).fragment, false);
	return n;
}

const FIXTURES: { source: string; count: number; why: string }[] = [
	{ source: '{#each xs as x}<a class="card" href="/x">{x}</a>{/each}', count: 1, why: 'a card link in a list' },
	{ source: '{#each xs as x}<li><a class="card-elevated workout-row" href="/x">{x}</a></li>{/each}', count: 1, why: 'nested in an li' },
	{ source: '{#each xs as x}<button class="run-card" onclick={f}>{x}</button>{/each}', count: 1, why: 'a card button' },
	{ source: '<a class="card" href="/x">x</a>', count: 0, why: 'one card, not a list' },
	{ source: '{#each xs as x}<a class="btn" href="/x">{x}</a>{/each}', count: 0, why: 'a button-styled link' },
	{ source: '{#each xs as x}<div class="card">{x}</div>{/each}', count: 0, why: 'a panel, not a tap target' },
	{ source: '{#each xs as x}<ListCard href="/x" title={x} />{/each}', count: 0, why: 'the component' },
	{ source: '{#each xs as x}<a class="cardigan" href="/x">{x}</a>{/each}', count: 0, why: 'a longer class name' },
];

test('the matcher counts a hand-built list card and spares look-alikes', () => {
	for (const f of FIXTURES) assert.equal(handBuiltCards(f.source), f.count, f.why);
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
	const n = handBuiltCards(readFileSync(path, 'utf8'));
	if (n > 0) counts.set(rel, n);
}

test('the component exists', () => {
	assert.ok(existsSync(join(SRC, COMPONENT)));
});

test('no hand-built list card past the counts left', () => {
	const problems: string[] = [];
	for (const [file, n] of counts) {
		const allowed = LEFT[file] ?? 0;
		if (n > allowed) problems.push(`  src/${file}: ${n} hand-built list cards, ${allowed} allowed; render ListCard`);
	}
	for (const [file, allowed] of Object.entries(LEFT)) {
		const n = counts.get(file) ?? 0;
		if (n < allowed) problems.push(`  src/${file}: ${n} hand-built list cards, ${allowed} listed; lower LEFT`);
	}
	assert.deepEqual(problems, [], 'conventions.md § Web list cards:\n' + problems.join('\n'));
});
