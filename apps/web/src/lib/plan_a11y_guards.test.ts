import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';

// #1186 round 2: the plan screens read about forty icon ligatures aloud
// ("arrow_back", "chevron_right", "event_upcoming") beside text that already
// said the same thing, the wizard's week rows opened and closed without saying
// so, and the plans list nested its Abandon / Delete buttons inside the card's
// link, an interactive element inside another.

const WEB = resolve('.');
const PLAN_ROUTES = resolve('src/routes/plans');
const PLAN_COMPONENTS = ['src/lib/components/PlanEditor.svelte', 'src/lib/components/WorkoutEditor.svelte'];

function svelteFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) svelteFiles(full, out);
		else if (full.endsWith('.svelte')) out.push(full);
	}
	return out;
}

const files = [...svelteFiles(PLAN_ROUTES), ...PLAN_COMPONENTS.map((f) => resolve(f))];

test('the scan reaches the plan screens', () => {
	const rel = files.map((f) => relative(WEB, f));
	for (const expected of [
		'src/routes/plans/+page.svelte',
		'src/routes/plans/[id]/+page.svelte',
		'src/routes/plans/[id]/workouts/[wid]/+page.svelte',
		'src/routes/plans/new/+page.svelte',
		'src/lib/components/PlanEditor.svelte',
	]) {
		assert.ok(rel.includes(expected), `${expected} is not scanned`);
	}
});

test('every icon on the plan screens is hidden from assistive technology', () => {
	const offenders: string[] = [];
	let icons = 0;
	for (const file of files) {
		const src = readFileSync(file, 'utf-8');
		for (const mo of src.matchAll(/<span\b[^>]*\bclass="[^"]*\bmaterial-symbols\b[^"]*"[^>]*>/g)) {
			icons++;
			if (!/aria-hidden="true"/.test(mo[0])) {
				const line = src.slice(0, mo.index).split('\n').length;
				offenders.push(`${relative(WEB, file)}:${line}`);
			}
		}
	}
	assert.ok(icons > 40, `expected the plan screens' icons, found ${icons}`);
	assert.deepEqual(offenders, [], 'an icon ligature without aria-hidden is read aloud as its name');
});

test('no plan-list card nests a button inside its link', () => {
	const src = readFileSync(resolve('src/routes/plans/+page.svelte'), 'utf-8');
	assert.match(src, /<a class="card-link" href="\/plans\/\{p\.id\}">/);
	for (const mo of src.matchAll(/<a\b[\s\S]*?<\/a>/g)) {
		assert.doesNotMatch(mo[0], /<button\b/, 'a <button> inside an <a>');
	}
});

test("the wizard's week rows say whether they are open", () => {
	const src = readFileSync(resolve('src/lib/components/PlanEditor.svelte'), 'utf-8');
	const row = /<button[^>]*class="week-row"[\s\S]*?>/.exec(src);
	assert.ok(row, 'the week row button is gone; update this guard');
	assert.match(row[0], /aria-expanded=\{expandedWeek === weekIdx\}/);
	assert.match(row[0], /aria-controls="plan-editor-week-\{weekIdx\}"/);
	assert.match(src, /class="week-editor" id="plan-editor-week-\{weekIdx\}"/);
});
