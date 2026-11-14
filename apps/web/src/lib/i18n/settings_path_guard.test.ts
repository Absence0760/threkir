import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { en } from './locales/en';

// No string gives directions into the app's own settings (decisions § 2496).
// "Settings → Preferences → Training" and "Settings, Payouts" named places the
// settings split moved, and a runner cannot click prose. A string says what is
// wrong and a link or action beside it opens the page. Naming a page
// ("Units & display") is fine; reciting the way there is not. The mobile twin
// is apps/mobile_android/test/settings_path_guard_test.dart.
//
// The exemptions give directions inside another product. The map may only
// shrink: an entry whose string is gone or no longer gives a path fails.

const EXEMPT: Record<string, string> = {
	'settingsIntegrations.stravaBulkInfo': "steps inside Strava, whose own Settings these are",
	'settingsIntegrations.stravaBulkLink': "steps inside Strava, whose own Settings these are",
	'importRefusal.stravaZipTooLarge': "steps inside Strava, whose own Settings these are",
	'importRefusal.stravaZipNotAnExport': "steps inside Strava, whose own Settings these are",
	'help:import-your-history.ts': "steps inside Strava, whose own Settings these are",
};

/** "Settings → Gear", "Preferences › Training", "Settings, Payouts". */
const PATH = /\b(Settings|Preferences|You)\s*(→|›|»|>)\s*\S|\b(Settings|Preferences),\s+\p{Lu}/u;

const GUIDES = resolve('src/lib/help/guides');

function guideTexts(): Array<[string, string]> {
	return readdirSync(GUIDES)
		.filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'))
		.map((f) => [`help:${f}`, readFileSync(join(GUIDES, f), 'utf8')]);
}

test('the pattern catches a path and leaves ordinary prose alone', () => {
	for (const bad of ['Add some in Settings → Gear.', 'Open Settings, Payouts on the web.', 'from You › Settings'])
		assert.ok(PATH.test(bad), bad);
	for (const ok of ['You can change it any time in Settings.', 'Reconnect Strava in Settings, then try again.', 'Week {n}: {from} → {to}'])
		assert.ok(!PATH.test(ok), ok);
});

test('no English string or help guide recites a path into Settings', () => {
	const texts: Array<[string, string]> = [...Object.entries(en as Record<string, string>), ...guideTexts()];
	const offenders = texts.filter(([id, s]) => PATH.test(s) && !(id in EXEMPT)).map(([id]) => id);
	assert.deepEqual(
		offenders,
		[],
		'say what is wrong and put a link or toast action to the page beside the string; the string gives no directions',
	);
	const live = new Map(texts);
	const stale = Object.keys(EXEMPT).filter((id) => !live.has(id) || !PATH.test(live.get(id)!));
	assert.deepEqual(stale, [], 'a fixed or deleted string comes off the exemption list');
});
