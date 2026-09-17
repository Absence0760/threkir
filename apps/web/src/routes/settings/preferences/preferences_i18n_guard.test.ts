// Source-level guard: the preference pages are the highest-traffic settings
// save surfaces, and every save-failure / telemetry toast on them must route
// through the i18n `m()` layer like their sibling settings pages
// (settingsAccount.saveFailed, settingsGear.saveFailed). A regression to a
// hardcoded English literal ships a broken toast to every non-English user.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { en } from '../../../lib/i18n/locales/en';
import { VOICE_CUE_IDS } from '../../../lib/settings/voice_cues';

const __dirname = dirname(fileURLToPath(import.meta.url));
const read = (...parts: string[]) => readFileSync(resolve(__dirname, ...parts), 'utf-8');

const AUTOSAVE = read('../../../lib/settings/prefs_page.svelte.ts');
const PAGES = ['display', 'recording', 'training', 'body', 'privacy', 'notifications'].map(
	(name) => [name, read(`../${name}/+page.svelte`)] as const,
);
const PRIVACY = read('../privacy/+page.svelte');
const RECORDING = read('../recording/+page.svelte');

test('preference save-failure toasts use the i18n key, not a literal', () => {
	for (const [name, source] of [['prefs_page.svelte.ts', AUTOSAVE] as const, ...PAGES]) {
		assert.doesNotMatch(
			source,
			/showToast\(`(Couldn't save|Save failed):/,
			`${name}: a save-failure toast must use m('prefs.saveFailed', { error }) — a hardcoded literal ships untranslated to every non-English user.`,
		);
	}
	assert.match(
		AUTOSAVE,
		/m\('prefs\.saveFailed', \{ error:/,
		"The shared auto-save must route its save-failure toast through m('prefs.saveFailed').",
	);
});

test('the telemetry toggle toasts use i18n keys, not literals', () => {
	assert.doesNotMatch(
		PRIVACY,
		/'Error reporting (enabled|disabled)/,
		"Telemetry toggle toast must use m('prefs.telemetryEnabledToast') / m('prefs.telemetryDisabledToast').",
	);
	assert.match(PRIVACY, /m\('prefs\.telemetryEnabledToast'\)/);
	assert.match(PRIVACY, /m\('prefs\.telemetryDisabledToast'\)/);
});

test('the toast keys exist in the en catalogue with the right placeholder', () => {
	assert.equal(en['prefs.saveFailed'], "Couldn't save: {error}");
	assert.ok(en['prefs.telemetryEnabledToast']);
	assert.ok(en['prefs.telemetryDisabledToast']);
});

test('every voice cue toggle names a label + hint key that exists in en', () => {
	// `Record<VoiceCueId, …>` already makes a missing cue a compile error;
	// this pins the other half — that the MessageKeys it names resolve to
	// real, non-empty catalogue entries rather than an untranslated blank.
	const enRecord = en as Record<string, string>;
	const labels = RECORDING.match(/const VOICE_CUE_LABELS[\s\S]*?\n\t\};/);
	assert.ok(labels, 'VOICE_CUE_LABELS not found on the recording settings page');
	const keys = [...labels[0].matchAll(/'(prefs\.cue\.[\w.]+)'/g)].map((mt) => mt[1]);
	assert.equal(keys.length, VOICE_CUE_IDS.length * 2);
	for (const key of keys) {
		assert.ok(enRecord[key]?.trim(), `Missing en catalogue entry ${key}`);
	}
});
