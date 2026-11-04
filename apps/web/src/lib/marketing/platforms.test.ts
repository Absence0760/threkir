import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { en } from '../i18n/locales/en';
import { interpolate } from '../i18n/interpolate';
import { CATALOGUE_LOADERS } from '../i18n/catalogues';
import { SUPPORTED_LOCALES } from '../i18n/locale';
import {
	isLive,
	PLATFORMS,
	platformsNote,
	platformStatusLabelKey,
	platformStoreHref,
	type Platform,
	type Translate,
} from './platforms';

const tEn: Translate = (key, params) => interpolate(en[key], params, 'en');

function byName(name: string): Platform {
	const p = PLATFORMS.find((x) => x.name === name);
	assert.ok(p, `${name} missing from PLATFORMS`);
	return p;
}

test('Web, iOS and Apple Watch are live; Android and Wear OS wait on Play (#1225)', () => {
	assert.deepEqual(
		PLATFORMS.map((p) => p.name),
		['Web', 'Android', 'iOS', 'Wear OS', 'Apple Watch'],
	);
	for (const name of ['Web', 'iOS', 'Apple Watch']) assert.equal(isLive(byName(name)), true, name);
	for (const name of ['Android', 'Wear OS']) assert.equal(isLive(byName(name)), false, name);
});

test('the status label follows the status, not the platform', () => {
	assert.equal(platformStatusLabelKey({ name: 'X', status: 'live' }), 'landing.platformLive');
	assert.equal(platformStatusLabelKey({ name: 'X', status: 'testing' }), 'landing.platformInTesting');
	assert.equal(tEn(platformStatusLabelKey(byName('iOS'))), 'Live');
	assert.equal(tEn(platformStatusLabelKey(byName('Android'))), 'In testing');
});

test('a badge links only when the platform carries a store URL', () => {
	const url = 'https://apps.apple.com/app/id0000000000';
	assert.equal(platformStoreHref({ name: 'iOS', status: 'live', storeUrl: url }), url);
	assert.equal(platformStoreHref({ name: 'iOS', status: 'live' }), null);
	for (const p of PLATFORMS) {
		if (p.storeUrl === undefined) continue;
		assert.match(p.storeUrl, /^https:\/\//, `${p.name} store URL must be https`);
	}
});

test('the note names exactly the platforms still in testing', () => {
	assert.equal(
		platformsNote(PLATFORMS, 'en', tEn),
		'Android and Wear OS are in internal testing and not in the app stores yet. Start on another platform now and your account will be waiting when they land.',
	);
	assert.equal(
		platformsNote([{ name: 'Android', status: 'testing' }, { name: 'iOS', status: 'live' }], 'en', tEn),
		'Android is in internal testing and not in the app stores yet. Start on another platform now and your account will be waiting when it lands.',
	);
});

test('no note once every platform is live', () => {
	const allLive = PLATFORMS.map((p) => ({ ...p, status: 'live' as const }));
	assert.equal(platformsNote(allLive, 'en', tEn), null);
});

test('every locale renders the note with every testing platform and no leftover ICU', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const t: Translate = (key, params) => interpolate(dict[key], params, loc);
		for (const set of [PLATFORMS, [{ name: 'Android', status: 'testing' } as const]]) {
			const note = platformsNote(set, loc, t);
			assert.ok(note, `${loc}: no note`);
			for (const p of set.filter((x) => x.status === 'testing')) {
				assert.ok(note.includes(p.name), `${loc}: note omits ${p.name}`);
			}
			assert.doesNotMatch(note, /[{}]|plural/, `${loc}: unresolved placeholder in "${note}"`);
		}
	}
});

test('the landing page reads the registry instead of hard-coding a status', () => {
	const page = readFileSync(new URL('../../routes/+page.svelte', import.meta.url), 'utf-8');
	assert.match(page, /#lib\/marketing\/platforms\.ts/);
	assert.doesNotMatch(page, /live:\s*(true|false)/);
	assert.doesNotMatch(page, /m\('landing\.platformsNote'\)/);
});
