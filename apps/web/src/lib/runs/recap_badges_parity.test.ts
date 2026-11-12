import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// The year-in-review trophy grid is built twice: here and in the mobile
// app's recap.dart. Neither is a registered parity pair, so nothing else
// notices when a threshold, id or label moves on one side only, and the same
// year then earns different badges on web and phone.

const read = (rel: string) => readFileSync(fileURLToPath(new URL(rel, import.meta.url)), 'utf8');

/** [condition, id, icon, label] per tier, whitespace- and syntax-normalised. */
function tiers(src: string, re: RegExp): string[][] {
	return [...src.matchAll(re)].map((m) =>
		[m[1], m[2], m[3], m[4]].map((s) =>
			s
				.replace(/!\.compareTo\('(\d\d:\d\d)'\) < 0/g, " < '$1'")
				.replace(/!\.compareTo\('(\d\d:\d\d)'\) >= 0/g, " >= '$1'")
				.replace(/\bi\.|\s+|!/g, ''),
		),
	);
}

test('web and mobile award the same recap badges at the same thresholds', () => {
	const web = tiers(
		read('./recap.ts'),
		/\{ when: (.+?), id: '([^']+)', icon: '([^']+)', label: '([^']+)'/g,
	);
	const dart = tiers(
		read('../../../../mobile_android/lib/recap.dart'),
		/_BadgeTier\((.+?), '([^']+)', '([^']+)', '([^']+)'/g,
	);
	assert.ok(web.length >= 20, `found ${web.length} web tiers`);
	assert.deepEqual(dart, web);
});
