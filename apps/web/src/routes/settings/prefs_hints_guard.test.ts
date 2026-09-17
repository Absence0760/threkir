// Every control on the preference pages carries a one-line plain explanation
// (issue #905 workstream 5, the Spoken-cues pattern #902 names as house style).
// A select, a number field or a toggle group points at its explanation with
// `aria-describedby`, so a screen reader announces it and the text sits under
// the control rather than inside its accessible name. A checkbox carries the
// explanation inside its own label as a `.hint`, as the cue toggles always did.
// A control added without one fails here, in every page the split produced.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { en } from '../../lib/i18n/locales/en';

const SETTINGS_DIR = dirname(fileURLToPath(import.meta.url));
const PAGES = ['display', 'recording', 'training', 'body', 'privacy', 'notifications'];

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
	for (const m of source.matchAll(/<(input|select)\b|<div\b[^>]*role="group"/g)) {
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
		if (labelEnd >= 0 && source.slice(control.at, labelEnd).includes('class="hint"')) return null;
	}
	return 'has neither aria-describedby nor a .hint inside its label';
}

for (const page of PAGES) {
	test(`every control on /settings/${page} has a plain explanation`, () => {
		const source = readFileSync(join(SETTINGS_DIR, page, '+page.svelte'), 'utf8');
		const found = controls(source);
		assert.ok(found.length > 0, `found no controls on /settings/${page} — the scan stopped matching`);
		const missing = found
			.map((c) => ({ c, why: explained(source, c) }))
			.filter((x) => x.why !== null)
			.map((x) => `${x.c.tag.replace(/\s+/g, ' ').slice(0, 90)} — ${x.why}`);
		assert.deepEqual(missing, [], `/settings/${page} has controls with no explanation`);
	});
}

test('every hint a preference page renders is real, non-empty English copy', () => {
	const enRecord = en as Record<string, string>;
	for (const page of PAGES) {
		const source = readFileSync(join(SETTINGS_DIR, page, '+page.svelte'), 'utf8');
		for (const m of source.matchAll(/class="hint"[^>]*>\{m\('([\w.]+)'/g)) {
			assert.ok(enRecord[m[1]]?.trim(), `/settings/${page} renders ${m[1]}, which en does not define`);
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
