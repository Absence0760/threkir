import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { interpolate } from '../i18n/interpolate.ts';
import { CATALOGUE_LOADERS } from '../i18n/catalogues.ts';
import { SUPPORTED_LOCALES } from '../i18n/locale.ts';
import type { MessageKey } from '../i18n/messages.ts';
import { raceCourseSourceLabel, raceSourceLabel, type Translate } from './race_source.ts';

// Every value race_listings.provider and race_listings.course_source may hold
// (their CHECKs; check_constraint_unions.mjs pins the TS unions to them).
const PROVIDERS = ['runsignup', 'manual', 'chronotrack', 'raceresult', 'ultrasignup'] as const;
const COURSE_SOURCES = ['official', 'traced'] as const;

/** A lookup that echoes the key and its params, so a test reads which sentence was chosen. */
const echo: Translate = (key, params) => (params ? `${key} ${JSON.stringify(params)}` : key);

test('raceSourceLabel: every listing provider credits its brand, untranslated', () => {
	assert.equal(raceSourceLabel(echo, 'runsignup'), 'races.sourceProvider {"provider":"RunSignUp"}');
	assert.equal(raceSourceLabel(echo, 'ultrasignup'), 'races.sourceProvider {"provider":"UltraSignup"}');
	assert.equal(raceSourceLabel(echo, 'chronotrack'), 'races.sourceProvider {"provider":"ChronoTrack"}');
	assert.equal(raceSourceLabel(echo, 'raceresult'), 'races.sourceProvider {"provider":"RaceResult"}');
	// A provider listing names the provider even when a club claimed it.
	assert.equal(raceSourceLabel(echo, 'runsignup', 'Harriers'), 'races.sourceProvider {"provider":"RunSignUp"}');
});

test('raceSourceLabel: a manual listing credits the claiming club, else a runner', () => {
	assert.equal(raceSourceLabel(echo, 'manual', 'Harriers'), 'races.sourceClub {"club":"Harriers"}');
	assert.equal(raceSourceLabel(echo, 'manual', null), 'races.sourceManual');
	assert.equal(raceSourceLabel(echo, 'manual'), 'races.sourceManual');
	assert.equal(raceSourceLabel(echo, 'manual', ''), 'races.sourceManual');
});

test('raceSourceLabel: a provider outside the vocabulary falls back like a manual listing', () => {
	assert.equal(raceSourceLabel(echo, 'parkrun'), 'races.sourceManual');
	assert.equal(raceSourceLabel(echo, ''), 'races.sourceManual');
	assert.equal(raceSourceLabel(echo, 'RunSignUp'), 'races.sourceManual');
	assert.equal(raceSourceLabel(echo, 'parkrun', 'Harriers'), 'races.sourceClub {"club":"Harriers"}');
});

test('raceSourceLabel: an inherited object key is not a provider', () => {
	// The map was once indexed directly, so `toString` read as a brand and
	// interpolated a function into the sentence.
	for (const key of ['toString', 'constructor', '__proto__', 'hasOwnProperty']) {
		assert.equal(raceSourceLabel(echo, key), 'races.sourceManual', key);
	}
});

test('raceCourseSourceLabel: each course source names the club', () => {
	assert.equal(raceCourseSourceLabel(echo, 'official', 'Harriers'), 'raceCourse.sourceOfficial {"club":"Harriers"}');
	assert.equal(raceCourseSourceLabel(echo, 'traced', 'Harriers'), 'raceCourse.sourceTraced {"club":"Harriers"}');
});

test('raceCourseSourceLabel: no source or no club is no sentence', () => {
	assert.equal(raceCourseSourceLabel(echo, null, 'Harriers'), null);
	assert.equal(raceCourseSourceLabel(echo, 'official', null), null);
	assert.equal(raceCourseSourceLabel(echo, 'traced', ''), null);
	assert.equal(raceCourseSourceLabel(echo, null, null), null);
});

test('every label resolves to a filled sentence in every locale', async () => {
	for (const loc of SUPPORTED_LOCALES) {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const t: Translate = (key: MessageKey, params) => {
			assert.equal(typeof dict[key], 'string', `${loc}: ${key} missing`);
			return interpolate(dict[key], params, loc);
		};
		const lines = [
			...PROVIDERS.map((p) => raceSourceLabel(t, p, 'Harriers')),
			raceSourceLabel(t, 'manual', null),
			...COURSE_SOURCES.map((s) => raceCourseSourceLabel(t, s, 'Harriers')),
		];
		for (const line of lines) {
			assert.ok(line && line.trim().length > 0, `${loc}: empty label`);
			assert.doesNotMatch(line!, /[{}]/, `${loc}: unfilled placeholder in ${line}`);
		}
		for (const p of PROVIDERS.filter((p) => p !== 'manual')) {
			assert.notEqual(raceSourceLabel(t, p), raceSourceLabel(t, 'manual'), `${loc}: ${p} reads as manual`);
		}
		assert.notEqual(
			raceCourseSourceLabel(t, 'official', 'Harriers'),
			raceCourseSourceLabel(t, 'traced', 'Harriers'),
			`${loc}: official and traced read the same`,
		);
	}
});

test('the race page passes the catalogue lookup', () => {
	const src = readFileSync(resolve(import.meta.dirname, '../../routes/races/[id]/+page.svelte'), 'utf8');
	assert.match(src, /raceSourceLabel\(m, /);
	assert.match(src, /raceCourseSourceLabel\(m, /);
});
