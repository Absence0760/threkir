// The `disclosure_level` setting's DEFAULT is a derivation, not a constant, and
// the two halves of that live in different files — the bag read here, the
// picker on /settings/display. An account that has never opened the control
// must come out of the plumbing at the level its goal and its history justify,
// and a value the helper does not recognise must come out there too rather than
// at some second default nobody wrote down.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { effective, type LoadedSettings, type PrefsBag } from './settings_overlay';
import {
	DISCLOSURE_FULL_RUNS,
	DISCLOSURE_LEVEL_KEY,
	DISCLOSURE_LEVELS,
	resolveDisclosureLevel,
} from './disclosure';
import { PRIMARY_GOAL_KEY } from './onboarding';

const SRC = join(dirname(fileURLToPath(import.meta.url)), '../..');
const DISPLAY_PAGE = join(SRC, 'routes/settings/display/+page.svelte');

function bag(universal: PrefsBag): LoadedSettings {
	return { universal, device: {} };
}

/// What every consumer does: read the two keys off the bag, hand them plus a
/// run count to the resolver.
function levelFor(settings: LoadedSettings, runCount: number) {
	return resolveDisclosureLevel(
		effective<string>(settings, DISCLOSURE_LEVEL_KEY),
		effective<string>(settings, PRIMARY_GOAL_KEY) ?? null,
		runCount,
	);
}

test('an account that never opened the control gets the level its answers imply', () => {
	assert.equal(levelFor(bag({ [PRIMARY_GOAL_KEY]: 'marathon' }), 0), 'full');
	assert.equal(levelFor(bag({ [PRIMARY_GOAL_KEY]: '10k' }), 0), 'standard');
	assert.equal(levelFor(bag({ [PRIMARY_GOAL_KEY]: 'general_fitness' }), 0), 'simple');
});

test('an account that skipped the goal step is judged on its history alone', () => {
	// The wizard's Skip writes nothing (decisions § 1650), so the commonest
	// bag has no goal in it at all — and a long-standing account must not be
	// folded up on the strength of a question it never answered.
	assert.equal(levelFor(bag({}), 0), 'simple');
	assert.equal(levelFor(bag({}), DISCLOSURE_FULL_RUNS), 'full');
	assert.equal(levelFor(bag({ [PRIMARY_GOAL_KEY]: null }), DISCLOSURE_FULL_RUNS), 'full');
});

test('a stored level beats the derivation in both directions', () => {
	const veteran = { [PRIMARY_GOAL_KEY]: 'marathon' };
	assert.equal(levelFor(bag({ ...veteran, [DISCLOSURE_LEVEL_KEY]: 'simple' }), 4000), 'simple');
	assert.equal(levelFor(bag({ [DISCLOSURE_LEVEL_KEY]: 'full' }), 0), 'full');
});

test('a value the helper does not recognise resolves to the derivation', () => {
	// Including the one the picker would write if Automatic were stored as a
	// fourth level rather than as the absence of the key.
	for (const stored of ['auto', 'basics', 'SIMPLE', 3, true]) {
		const settings = bag({ [DISCLOSURE_LEVEL_KEY]: stored, [PRIMARY_GOAL_KEY]: 'marathon' });
		assert.equal(levelFor(settings, 0), 'full', String(stored));
	}
});

test('the picker offers exactly the three levels plus Automatic', () => {
	const page = readFileSync(DISPLAY_PAGE, 'utf8');
	const from = page.indexOf('data-testid="disclosure-level-select"');
	assert.ok(from > 0, '/settings/display no longer carries the disclosure picker');
	const select = page.slice(from, page.indexOf('</select>', from));
	const values = [...select.matchAll(/<option value="([^"]+)"/g)].map((m) => m[1]);
	assert.deepEqual(values, ['auto', ...DISCLOSURE_LEVELS]);
});

test('Automatic clears the key rather than storing a fourth level', () => {
	// A stored 'auto' would resolve to the derivation anyway — but it would sit
	// in the bag, and in the Art 20 export, as a level that does not exist.
	const page = readFileSync(DISPLAY_PAGE, 'utf8');
	assert.match(page, /\[DISCLOSURE_LEVEL_KEY\]:[^}\n]*null/);
});
