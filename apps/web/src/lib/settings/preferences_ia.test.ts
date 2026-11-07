// `npx tsx --test src/lib/settings/preferences_ia.test.ts`
//
// The preferences split (issue #905): every page the list names must exist
// and be labelled, and every old `#section` link already sent in an email
// must still land on a real page.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

import { en } from '../i18n/locales/en';
import {
	BODY_METRICS_PAGE,
	LEGACY_PREFERENCES_ANCHORS,
	PREFERENCES_PAGES,
	legacyPreferencesTarget,
} from './preferences_ia';

const routes = join(process.cwd(), 'src', 'routes');
const pageExists = (href: string) =>
	existsSync(join(routes, ...href.split('#')[0].split('/').filter(Boolean), '+page.svelte'));

const allPages = [...PREFERENCES_PAGES, BODY_METRICS_PAGE];

test('every preferences page is a real route with a unique href', () => {
	for (const p of allPages) assert.ok(pageExists(p.href), `${p.href} has no +page.svelte`);
	const hrefs = allPages.map((p) => p.href);
	assert.equal(new Set(hrefs).size, hrefs.length);
});

test('every page label and summary is an English catalogue key', () => {
	const keys = en as Record<string, string>;
	for (const p of allPages) {
		assert.ok(keys[p.label], `${p.href} label ${p.label}`);
		assert.ok(keys[p.summary], `${p.href} summary ${p.summary}`);
	}
});

test('every legacy anchor lands on a real page', () => {
	for (const [anchor, target] of Object.entries(LEGACY_PREFERENCES_ANCHORS)) {
		assert.ok(pageExists(target), `#${anchor} -> ${target}`);
		assert.match(target, /^\/settings\/[a-z-]+#[a-z-]+$/);
	}
});

test('legacyPreferencesTarget accepts the hash with or without its #', () => {
	assert.equal(legacyPreferencesTarget('#heart-rate-zones'), '/settings/training#heart-rate-zones');
	assert.equal(legacyPreferencesTarget('weekly-mileage-goal'), '/settings/training#weekly-distance-goal');
	assert.equal(legacyPreferencesTarget('#body-metrics'), '/settings/body#body-metrics');
});

test('an unknown hash, an empty hash, or an inherited key is no target', () => {
	assert.equal(legacyPreferencesTarget('#nope'), null);
	assert.equal(legacyPreferencesTarget(''), null);
	assert.equal(legacyPreferencesTarget('#'), null);
	assert.equal(legacyPreferencesTarget('#toString'), null);
	assert.equal(legacyPreferencesTarget('#__proto__'), null);
});
