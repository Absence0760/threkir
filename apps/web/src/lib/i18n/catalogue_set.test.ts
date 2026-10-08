// The loader/merge logic behind `store.svelte.ts` (decisions § 1802).
// Invocation: npx tsx --test src/lib/i18n/catalogue_set.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { CatalogueSet, holdsServerMarkup, type Catalogue } from './catalogue_set';

type L = 'en' | 'de';
type A = 'gym' | 'clubs';

const DATA: Record<L, Record<'core' | A, Catalogue>> = {
	en: { core: { 'nav.home': 'Home' }, gym: { 'gym.title': 'Gym' }, clubs: { 'clubs.title': 'Clubs' } },
	de: { core: { 'nav.home': 'Start' }, gym: { 'gym.title': 'Fitnessstudio' }, clubs: { 'clubs.title': 'Vereine' } },
};

/// A fetch the test resolves (or rejects) by hand, so ordering is explicit.
function deferred<T>() {
	let resolve!: (v: T) => void;
	let reject!: (e: unknown) => void;
	const promise = new Promise<T>((res, rej) => {
		resolve = res;
		reject = rej;
	});
	return { promise, resolve, reject };
}

function harness(opts: { manual?: boolean } = {}) {
	const emitted: { locale: L; dict: Catalogue }[] = [];
	const fetches: string[] = [];
	const pending = new Map<string, ReturnType<typeof deferred<Catalogue>>>();
	const failing = new Set<string>();
	const fetch = (id: string, value: Catalogue): Promise<Catalogue> => {
		fetches.push(id);
		if (failing.has(id)) return Promise.reject(new Error(`offline: ${id}`));
		if (!opts.manual) return Promise.resolve(value);
		const d = deferred<Catalogue>();
		pending.set(id, d);
		return d.promise;
	};
	const set = new CatalogueSet<L, A>({
		sources: {
			core: (l) => fetch(`${l}/core`, DATA[l].core),
			area: (l, a) => fetch(`${l}/${a}`, DATA[l][a]),
		},
		fallbackLocale: 'en',
		fallbackCore: DATA.en.core,
		onChange: (locale, dict) => emitted.push({ locale, dict }),
		onError: () => {},
	});
	const settle = (id: string) => {
		const d = pending.get(id);
		assert.ok(d, `no pending fetch for ${id}`);
		const [l, p] = id.split('/') as [L, 'core' | A];
		d.resolve(DATA[l][p]);
	};
	return { set, emitted, fetches, failing, settle, last: () => emitted.at(-1) };
}

test('an area loads into the dict alongside the core, in the current locale', async () => {
	const h = harness();
	await h.set.ensureAreas(['gym']);
	assert.deepEqual(h.last(), { locale: 'en', dict: { 'nav.home': 'Home', 'gym.title': 'Gym' } });
	assert.deepEqual(h.fetches, ['en/gym'], 'the English core is bundled, never fetched');
});

test('a route with no areas, or areas already loaded, fetches and emits nothing', async () => {
	const h = harness();
	await h.set.ensureAreas([]);
	await h.set.ensureAreas(['gym']);
	const before = h.emitted.length;
	await h.set.ensureAreas(['gym']);
	assert.equal(h.emitted.length, before);
	assert.deepEqual(h.fetches, ['en/gym']);
});

test('switching locale swaps core and every loaded area together', async () => {
	const h = harness();
	await h.set.ensureAreas(['gym', 'clubs']);
	assert.equal(await h.set.setLocale('de'), true);
	assert.deepEqual(h.last(), {
		locale: 'de',
		dict: { 'nav.home': 'Start', 'gym.title': 'Fitnessstudio', 'clubs.title': 'Vereine' },
	});
	assert.equal(h.set.locale, 'de');
});

test('after a switch, a new area loads in the new locale only', async () => {
	const h = harness();
	await h.set.setLocale('de');
	h.fetches.length = 0;
	await h.set.ensureAreas(['gym']);
	assert.deepEqual(h.fetches, ['de/gym'], 'a German reader never downloads the English area');
	assert.deepEqual(h.last()?.dict, { 'nav.home': 'Start', 'gym.title': 'Fitnessstudio' });
});

test('a dict never mixes one locale core with another locale area', async () => {
	// The race this class exists for: a route asks for an area while a locale
	// switch is in flight. Whatever order the fetches land in, every emitted
	// dict is one language.
	const h = harness({ manual: true });
	const switching = h.set.setLocale('de');
	const navigating = h.set.ensureAreas(['gym']);
	h.settle('de/gym');
	h.settle('de/core');
	await Promise.all([switching, navigating]);
	for (const { locale, dict } of h.emitted) {
		const values = Object.values(dict);
		if (locale === 'de') assert.ok(!values.includes('Home') && !values.includes('Gym'), JSON.stringify(dict));
	}
	assert.deepEqual(h.last(), { locale: 'de', dict: { 'nav.home': 'Start', 'gym.title': 'Fitnessstudio' } });
});

test('an older, smaller compose landing late does not undo a newer one', async () => {
	const h = harness({ manual: true });
	const first = h.set.ensureAreas(['gym']);
	const second = h.set.ensureAreas(['clubs']);
	h.settle('en/clubs');
	await new Promise((r) => setTimeout(r, 0));
	// `gym` is shared by both composes, so settling it completes both in the
	// same tick, in whichever order the microtasks fall. The older one holds
	// only gym; it must not be the last word.
	h.settle('en/gym');
	await Promise.all([first, second]);
	assert.deepEqual(h.last()?.dict, { 'nav.home': 'Home', 'gym.title': 'Gym', 'clubs.title': 'Clubs' });
	for (const { dict } of h.emitted.slice(h.emitted.findIndex((e) => 'clubs.title' in e.dict))) {
		assert.ok('gym.title' in dict && 'clubs.title' in dict, 'no write after the full one may drop an area');
	}
});

test('a switch superseded by a newer one never writes', async () => {
	const h = harness({ manual: true });
	const toGerman = h.set.setLocale('de');
	const backToEnglish = h.set.setLocale('en');
	await backToEnglish;
	h.settle('de/core');
	await toGerman;
	assert.equal(h.last()?.locale, 'en');
	assert.equal(h.set.locale, 'en');
});

test('a core that fails to load keeps the current locale and reports false', async () => {
	const h = harness();
	await h.set.ensureAreas(['gym']);
	h.failing.add('de/core');
	assert.equal(await h.set.setLocale('de'), false);
	assert.equal(h.set.locale, 'en');
	assert.equal(h.last()?.locale, 'en');
	// The failure was not cached: the next attempt fetches again and succeeds.
	h.failing.delete('de/core');
	assert.equal(await h.set.setLocale('de'), true);
	assert.equal(h.last()?.dict['gym.title'], 'Fitnessstudio');
});

test('a translated area that fails falls back to its English sentences, never key names', async () => {
	const h = harness();
	await h.set.setLocale('de');
	h.failing.add('de/gym');
	await h.set.ensureAreas(['gym']);
	assert.deepEqual(h.last()?.dict, { 'nav.home': 'Start', 'gym.title': 'Gym' });
	// Once the network is back, a locale switch picks the translation up.
	h.failing.delete('de/gym');
	await h.set.setLocale('en');
	await h.set.setLocale('de');
	assert.equal(h.last()?.dict['gym.title'], 'Fitnessstudio');
});

test('an area that cannot load at all still resolves, leaving the rest of the dict intact', async () => {
	const h = harness();
	h.failing.add('en/gym');
	await h.set.ensureAreas(['gym', 'clubs']);
	assert.deepEqual(h.last()?.dict, { 'nav.home': 'Home', 'clubs.title': 'Clubs' });
});

test('setting the locale already shown is a no-op', async () => {
	const h = harness();
	assert.equal(await h.set.setLocale('en'), true);
	assert.equal(h.emitted.length, 0, 're-emitting would re-render every m() caller for nothing');
});

test('the SPA shell holds only its bootstrap script; server-rendered markup holds more', () => {
	const el = (tagName: string) => ({ tagName });
	assert.equal(holdsServerMarkup({ children: [el('SCRIPT')] }), false, 'the 200.html shell');
	assert.equal(holdsServerMarkup({ children: [el('DIV'), el('SCRIPT')] }), true, 'a prerendered page');
	assert.equal(holdsServerMarkup({ children: [] }), false);
	assert.equal(holdsServerMarkup(null), false);
});

test('app.html still wraps the body in the one div holdsServerMarkup reads', () => {
	// The store passes `body > div` to holdsServerMarkup. If app.html stops
	// wrapping `%sveltekit.body%` in a single div, the probe reads the wrong
	// element and every cold start falls back to an English first paint.
	const html = readFileSync(resolve('src/app.html'), 'utf-8');
	const body = /<body[^>]*>([\s\S]*)<\/body>/.exec(html)?.[1].trim() ?? '';
	assert.match(body, /^<div style="display: contents">%sveltekit\.body%<\/div>$/);
});
