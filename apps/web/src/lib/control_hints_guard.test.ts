// Every control on a swept surface carries a one-line plain explanation
// (issue #905 workstream 5, the Spoken-cues pattern #902 names as house style).
// A select, a number field or a toggle group points at its explanation with
// `aria-describedby`, so a screen reader announces it and the text sits under
// the control rather than inside its accessible name. A checkbox carries the
// explanation inside its own label as a `.hint` / `.field-hint`, as the cue
// toggles always did. A control added without one fails here.
//
// SURFACES is the sweep's boundary, not the app's: the six preference pages
// came from #919, the plan-and-run path from the workstream-5 sweep. A surface
// not listed has not been swept — adding one to this list is how the sweep
// grows, and the test then names every control on it that owes an explanation.
//
// A `<textarea>` is deliberately not a control here: its label plus its
// placeholder is already the whole story on a free-text field, and demanding a
// line under each one adds the density #905 exists to remove.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { en } from './i18n/locales/en';
import { stripSvelteComments } from './core/strip_comments';

const SRC = join(dirname(fileURLToPath(import.meta.url)), '..');

const SETTINGS_PAGES = ['display', 'recording', 'training', 'body', 'privacy', 'notifications'];

const SURFACES: Array<{ name: string; file: string }> = [
	...SETTINGS_PAGES.map((page) => ({
		name: `/settings/${page}`,
		file: `routes/settings/${page}/+page.svelte`,
	})),
	{ name: '/plans/new', file: 'routes/plans/new/+page.svelte' },
	{ name: 'PlanEditor', file: 'lib/components/PlanEditor.svelte' },
	{ name: 'PlanMetaEditor', file: 'lib/components/PlanMetaEditor.svelte' },
	{ name: 'RunEditor', file: 'lib/components/RunEditor.svelte' },
	{ name: 'ClubEditor', file: 'lib/components/ClubEditor.svelte' },
	{ name: 'EventEditor', file: 'lib/components/EventEditor.svelte' },
	{ name: 'RaceListingEditor', file: 'lib/components/RaceListingEditor.svelte' },
	{ name: 'ChallengeEditor', file: 'lib/components/ChallengeEditor.svelte' },
	{ name: 'FundraiserEditor', file: 'lib/components/FundraiserEditor.svelte' },
];

/// The opening tag starting at `start`, read up to the `>` that closes it
/// rather than one inside an attribute expression (`onchange={() => …}`).
function openingTag(source: string, start: number): string {
	let depth = 0;
	for (let i = start; i < source.length; i++) {
		const c = source[i];
		if (c === '{') depth++;
		else if (c === '}') depth--;
		else if (c === '>' && depth === 0) return source.slice(start, i + 1);
	}
	throw new Error(`unterminated tag at ${start}`);
}

interface Control {
	tag: string;
	at: number;
}

function controls(source: string): Control[] {
	const found: Control[] = [];
	for (const m of source.matchAll(/<(input|select)\b|<div\b[^>]*role="(?:radio)?group"/g)) {
		found.push({ tag: openingTag(source, m.index!), at: m.index! });
	}
	return found;
}

function explained(source: string, control: Control): string | null {
	const described = control.tag.match(/aria-describedby="([^"]+)"/);
	if (described) {
		for (const id of described[1].split(/\s+/)) {
			if (!source.includes(`id="${id}"`)) return `aria-describedby names "${id}", which no element has`;
		}
		return null;
	}
	if (/type="checkbox"/.test(control.tag)) {
		const labelEnd = source.indexOf('</label>', control.at);
		const inLabel = labelEnd >= 0 ? source.slice(control.at, labelEnd) : '';
		if (inLabel.includes('class="hint"') || inLabel.includes('class="field-hint"')) return null;
	}
	return 'has neither aria-describedby nor a .hint inside its label';
}

function read(file: string): string {
	return readFileSync(join(SRC, file), 'utf8');
}

for (const surface of SURFACES) {
	test(`every control on ${surface.name} has a plain explanation`, () => {
		const source = read(surface.file);
		const found = controls(stripSvelteComments(source));
		assert.ok(found.length > 0, `found no controls on ${surface.name} — the scan stopped matching`);
		const missing = found
			.map((c) => ({ c, why: explained(source, c) }))
			.filter((x) => x.why !== null)
			.map((x) => `${x.c.tag.replace(/\s+/g, ' ').slice(0, 90)} — ${x.why}`);
		assert.deepEqual(missing, [], `${surface.name} has controls with no explanation`);
	});
}

test('every hint a swept surface renders is real, non-empty English copy', () => {
	const enRecord = en as Record<string, string>;
	for (const surface of SURFACES) {
		const source = read(surface.file);
		for (const m of source.matchAll(/class="[^"]*hint[^"]*"[^>]*>\s*\{[mt]\('([\w.]+)'/g)) {
			assert.ok(
				enRecord[m[1]]?.trim(),
				`${surface.name} renders ${m[1]}, which en does not define`
			);
		}
	}
});

// "No acronym without its expansion" (#905 workstream 6): the units and
// abbreviations these pages print as labels are spelled out in the hint copy
// directly under them.
test('the abbreviations the preference labels use are spelled out in their hints', () => {
	const expansions: Array<[key: keyof typeof en, needle: RegExp]> = [
		['prefs.restingHrHint', /heart rate \(HR\).*beats per minute \(bpm\)/],
		['prefs.paceFormatHint', /\(min\/km\).*\(min\/mi\).*\(km\/h\).*\(mph\)/],
		['prefs.weightUnitHint', /kilograms \(kg\).*pounds \(lbs\)/],
		['prefs.heightHint', /centimetres \(cm\)/],
		['prefs.coachPersonalityHint', /artificial intelligence \(AI\)/],
		['prefs.zonesUpperBoundDesc', /beats per minute \(bpm\)/],
		['prefs.fluidPerHourHint', /Millilitres/],
		['prefs.carbsPerHourHint', /Grams/],
	];
	for (const [key, needle] of expansions) {
		assert.match(en[key], needle, `${key} no longer spells out its abbreviation`);
	}
});
