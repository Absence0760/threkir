import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { parse } from 'svelte/compiler';

// A settings-style row is `ListRow` (conventions.md § Web settings rows;
// issue #1374), the twin of ui_kit's `ListRow`: a nav row, a value row or a
// switch. Before it, every preference page drew its own `label.checkbox-row`
// — a bare checkbox announced as a checkbox for a setting that applies at
// once, its explanation folded into its name — and a nav list drew its own
// link with a hand-placed chevron.
//
// This counts, per file:
//   - a `<label>` whose class is `checkbox-row`, `switch-row` or `toggle-row`
//     around a checkbox (a hand-built toggle row);
//   - a checkbox given `role="switch"` by hand;
//   - a link or button in a list item that draws its own `chevron_right`
//     (a hand-built nav row).
// A LEFT entry is a file whose rows are not settings rows, with the reason;
// the counts may only shrink, and an entry under its count fails until it is
// lowered or removed.

const SRC = resolve(new URL('.', import.meta.url).pathname, '..');
const COMPONENT = 'lib/components/ListRow.svelte';
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

const FORM = 'a field of an editor form, saved with the form, not a setting applied at once';

const LEFT: Record<string, { count: number; why: string }> = {
	'lib/components/CheckpointManager.svelte': { count: 1, why: FORM },
	'lib/components/ClubEditor.svelte': { count: 1, why: FORM },
	'lib/components/FoodLogEditor.svelte': { count: 1, why: 'a food search result with brand, source tag and a kcal figure: a picker card row ListRow has no slot for' },
	'lib/components/GymEditor.svelte': { count: 1, why: FORM },
	'lib/components/MealPlanEditor.svelte': { count: 1, why: FORM },
	'lib/components/RaceStartModeFields.svelte': { count: 1, why: FORM },
	'lib/components/RouteMarkerEditor.svelte': { count: 2, why: 'the snap option and the aid-station services are fields of the marker draft, saved with it' },
	'lib/components/SessionPlanEditor.svelte': { count: 1, why: FORM },
	'routes/clubs/[slug]/events/[id]/board/+page.svelte': { count: 2, why: 'the medical-hold and health-consent ticks are fields of the weigh-in form, saved with it' },
	'routes/fundraisers/[id]/+page.svelte': { count: 1, why: 'the anonymous-donation tick is a field of the donation form' },
};

type Attr = { type?: string; name?: string; value?: unknown };
type Node = { type?: string; name?: string; data?: string; attributes?: Attr[]; fragment?: { nodes?: unknown[] } };

function attrText(el: Node, name: string): string | null {
	for (const a of el.attributes ?? []) {
		if (a.type !== 'Attribute' || a.name !== name) continue;
		if (a.value === true) return '';
		const parts = Array.isArray(a.value) ? a.value : [a.value];
		return parts.map((p) => (p && typeof p === 'object' && 'data' in p ? String((p as { data: unknown }).data) : ' ')).join('');
	}
	return null;
}

const classes = (el: Node): string[] => (attrText(el, 'class') ?? '').split(/\s+/).filter(Boolean);

function some(node: unknown, pred: (el: Node) => boolean): boolean {
	if (Array.isArray(node)) return node.some((c) => some(c, pred));
	if (!node || typeof node !== 'object') return false;
	const el = node as Node;
	if (pred(el)) return true;
	return Object.entries(node).some(([key, value]) => key !== 'metadata' && some(value, pred));
}

const isCheckbox = (el: Node): boolean =>
	el.type === 'RegularElement' && el.name === 'input' && attrText(el, 'type') === 'checkbox';
const isChevron = (el: Node): boolean =>
	el.type === 'RegularElement' &&
	classes(el).includes('material-symbols') &&
	(el.fragment?.nodes ?? []).some((c) => (c as Node).type === 'Text' && (c as Node).data?.trim() === 'chevron_right');

function handBuiltRows(source: string): number {
	let n = 0;
	const visit = (node: unknown, inLi: boolean): void => {
		if (Array.isArray(node)) return node.forEach((c) => visit(c, inLi));
		if (!node || typeof node !== 'object') return;
		const el = node as Node;
		let li = inLi;
		if (el.type === 'RegularElement') {
			if (el.name === 'label' && classes(el).some((c) => /^(checkbox|switch|toggle)-row$/.test(c)) && some(el.fragment, isCheckbox)) n++;
			if (isCheckbox(el) && attrText(el, 'role') === 'switch') n++;
			if (inLi && (el.name === 'a' || el.name === 'button') && some(el.fragment, isChevron)) n++;
			if (el.name === 'li') li = true;
		}
		for (const [key, value] of Object.entries(node)) if (key !== 'metadata') visit(value, li);
	};
	visit(parse(source, { modern: true }).fragment, false);
	return n;
}

const FIXTURES: { source: string; count: number; why: string }[] = [
	{ source: '<label class="checkbox-row"><input type="checkbox" /><span>x</span></label>', count: 1, why: 'a hand-built toggle row' },
	{ source: '<label class="switch-row"><input type="checkbox" role="switch" /></label>', count: 2, why: 'a switch row and its hand-set role' },
	{ source: '<label class="consent-checkbox"><input type="checkbox" /> I agree</label>', count: 0, why: 'a consent tick is a checkbox' },
	{ source: '<div class="toggle-row" role="group"><button>km</button><button>mi</button></div>', count: 0, why: 'a segmented control' },
	{ source: '<ul><li><a href="/x">X<span class="material-symbols">chevron_right</span></a></li></ul>', count: 1, why: 'a hand-built nav row' },
	{ source: '<a href="/x">See all<span class="material-symbols">chevron_right</span></a>', count: 0, why: 'a see-all link, not a list row' },
	{ source: '<ul><li><a href="/x">X</a></li></ul>', count: 0, why: 'a plain list link' },
	{ source: '<ListRow kind="toggle" title="x" />', count: 0, why: 'the component' },
];

test('the matcher counts hand-built settings rows and spares look-alikes', () => {
	for (const f of FIXTURES) assert.equal(handBuiltRows(f.source), f.count, f.why);
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
	const n = handBuiltRows(readFileSync(path, 'utf8'));
	if (n > 0) counts.set(rel, n);
}

test('the component exists', () => {
	assert.ok(existsSync(join(SRC, COMPONENT)));
});

test('no hand-built settings row past the counts left', () => {
	const problems: string[] = [];
	for (const [file, n] of counts) {
		const allowed = LEFT[file]?.count ?? 0;
		if (n > allowed) problems.push(`  src/${file}: ${n} hand-built settings rows, ${allowed} allowed; render ListRow`);
	}
	for (const [file, { count, why }] of Object.entries(LEFT)) {
		assert.ok(why.trim().length > 0, `${file}: an entry needs a reason`);
		const n = counts.get(file) ?? 0;
		if (n < count) problems.push(`  src/${file}: ${n} hand-built settings rows, ${count} listed; lower LEFT`);
	}
	assert.deepEqual(problems, [], 'conventions.md § Web settings rows:\n' + problems.join('\n'));
});
