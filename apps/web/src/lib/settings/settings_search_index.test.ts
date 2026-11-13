import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { en } from '../i18n/locales/en';
import type { MessageKey } from '../i18n/messages';
import { BODY_METRICS_PAGE, PREFERENCES_PAGES } from './preferences_ia';
import { SETTINGS_SEARCH_INDEX, searchSettings } from './settings_search';

// The settings search index is hand-kept beside pages that render their own
// markup (settings_search.ts). These keep the two from drifting apart.

const ROUTES = resolve(new URL('.', import.meta.url).pathname, '../../routes/settings');
const english = en as Record<string, string>;
const t = (k: MessageKey) => english[k];
const pageSource = (href: string) => readFileSync(resolve(ROUTES, href.replace('/settings/', ''), '+page.svelte'), 'utf8');
const all = new Set(SETTINGS_SEARCH_INDEX.map((p) => p.href));

test('every settings nav entry has an index entry, and nothing else does', () => {
	const layout = readFileSync(resolve(ROUTES, '+layout.svelte'), 'utf8');
	const nav = new Set([
		...[...layout.matchAll(/href: '(\/settings\/[a-z-]+)'/g)].map((m) => m[1]),
		BODY_METRICS_PAGE.href,
		...PREFERENCES_PAGES.map((p) => p.href),
	]);
	assert.deepEqual([...all].sort(), [...nav].sort());
});

test('every indexed title is a live string its page still reads', () => {
	const stale: string[] = [];
	for (const page of SETTINGS_SEARCH_INDEX) {
		const src = pageSource(page.href);
		for (const key of page.rows) {
			if (!Object.hasOwn(english, key) || !src.includes(`'${key}'`)) stale.push(`${page.href}: ${key}`);
		}
		assert.ok(Object.hasOwn(english, page.label), `${page.href}: label ${page.label}`);
	}
	assert.deepEqual(stale, [], 'Drop or fix the index entry: its page no longer shows that title.');
});

test("every section heading a page draws is in that page's index entry", () => {
	const missing: string[] = [];
	for (const page of SETTINGS_SEARCH_INDEX) {
		const src = pageSource(page.href);
		for (const m of src.matchAll(/<h2[^>]*>\s*\{[a-z]+\('([^']+)'\)\}/g)) {
			if (!page.rows.includes(m[1] as MessageKey)) missing.push(`${page.href}: ${m[1]}`);
		}
	}
	assert.deepEqual(missing, [], 'A new settings section is a search result: add its heading to settings_search.ts.');
});

test('search folds case and accents, names the page, and lists the page itself', () => {
	const hits = searchSettings('HEART', t, all);
	assert.ok(hits.some((h) => h.href === '/settings/training' && h.title === english['prefs.heartRateZonesHeading']));
	assert.ok(hits.every((h) => h.where.length > 0));
	const self = searchSettings(english['settingsLayout.tabGear'], t, all);
	assert.equal(self[0].href, '/settings/gear');
	assert.equal(self[0].title, self[0].where);
});

test('a blank query finds nothing, and a hidden page is never offered', () => {
	assert.deepEqual(searchSettings('   ', t, all), []);
	const withoutTraining = new Set([...all].filter((h) => h !== '/settings/training'));
	assert.ok(searchSettings('zones', t, all).length > 0);
	assert.ok(searchSettings('zones', t, withoutTraining).every((h) => h.href !== '/settings/training'));
});

test('a title on one page is listed once', () => {
	const hits = searchSettings(english['prefs.messagesHeading'], t, all);
	const keys = hits.map((h) => `${h.href}|${h.title}`);
	assert.equal(new Set(keys).size, keys.length);
});
