// The plan detail expanders are drawn in one order and open in one state on
// web and mobile (decisions § 2375). These read the Svelte page and the Dart
// screen off their source, so a section reordered, added or defaulted open on
// one platform alone fails here.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PLAN_DETAIL_DISCLOSURE_DEFAULTS, PLAN_DETAIL_DISCLOSURE_SCOPE } from './plan_detail_sections';

const HERE = dirname(fileURLToPath(import.meta.url));
const SVELTE = readFileSync(resolve(HERE, '../../routes/plans/[id]/+page.svelte'), 'utf-8');
const DART = readFileSync(
	resolve(HERE, '../../../../mobile_android/lib/screens/plan_detail_screen.dart'),
	'utf-8',
);

function dartDefaults(): [string, boolean][] {
	const block = /const DisclosureState kPlanDetailDisclosureDefaults = \{([^}]*)\};/.exec(DART);
	assert.ok(block, 'kPlanDetailDisclosureDefaults is declared in plan_detail_screen.dart');
	return [...block[1].matchAll(/'(\w+)':\s*(true|false)/g)].map((m) => [m[1], m[2] === 'true']);
}

test('every plan detail section starts shut', () => {
	for (const [key, open] of Object.entries(PLAN_DETAIL_DISCLOSURE_DEFAULTS)) {
		assert.equal(open, false, key);
	}
});

test('the Dart screen declares the same scope and defaults, key for key, in order', () => {
	assert.match(DART, new RegExp(`const String kPlanDetailDisclosureScope = '${PLAN_DETAIL_DISCLOSURE_SCOPE}';`));
	assert.deepEqual(dartDefaults(), Object.entries(PLAN_DETAIL_DISCLOSURE_DEFAULTS));
});

test('both platforms draw the sections in the declared order', () => {
	const order = Object.keys(PLAN_DETAIL_DISCLOSURE_DEFAULTS);
	const web = [...SVELTE.matchAll(/open=\{disclosure\.(\w+)\}/g)].map((m) => m[1]);
	assert.deepEqual(web, order, 'web +page.svelte');
	const dart = [...DART.matchAll(/^\s*section\(\s*'(\w+)'/gm)].map((m) => m[1]);
	assert.deepEqual(dart, order, 'plan_detail_screen.dart');
});

test('the page reads its defaults from the shared module, not a local copy', () => {
	assert.match(SVELTE, /const DISCLOSURE_DEFAULTS = PLAN_DETAIL_DISCLOSURE_DEFAULTS;/);
});
