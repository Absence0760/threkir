import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// An achievement badge or a recap names its distances and climbs as
// `{distance}` / `{elevation}`, filled in the reader's unit, so a miles reader
// never reads "Ran 42.2 km" or "5,000 m climbed". A number written next to a
// unit in one of these strings is a measure the reader cannot convert; this
// fails it on web and in every ARB.

const HERE = dirname(fileURLToPath(import.meta.url));
const L10N = resolve(HERE, '../../../../mobile_android/lib/l10n');

const WEB_SCOPE = /^(badges\.|recap\.)/;
const ARB_SCOPE = /^(badges|recap)/;

// A number followed by a length unit, abbreviated or spelled out. A unit word
// with no number before it is an idiom ("Serious mileage", « Kilometraje
// serio »), not a measure, and passes.
const UNIT_LITERAL =
	/\d[\d.,\s\u00a0\u202f]*(km|mi|m|ft|yd|kilomet\p{L}*|quil[oó]met\p{L}*|miles?|millas?|milhas?|meilen|metres?|meters?|metros?|mètres?|feet|höhenmeter|キロメートル|キロ|マイル|メートル|フィート)(?![a-zß-ÿ])/iu;

// Race names, not measures: a miles reader also calls the race a 5K.
const EXEMPT: Record<string, string> = {
	'badges.distanceSingle5k.label': 'the 5K race name ("First 5K"), which a miles reader also says',
	badgesDistanceSingle5kLabel: 'the 5K race name ("First 5K"), which a miles reader also says',
};

const ARB_LOCALE: Record<string, string> = {
	'app_en.arb': 'en',
	'app_de.arb': 'de',
	'app_fr.arb': 'fr',
	'app_es.arb': 'es',
	'app_pt.arb': 'pt-PT',
	'app_pt_BR.arb': 'pt-BR',
	'app_ja.arb': 'ja',
};

function offenders(entries: [string, string][]): string[] {
	return entries
		.filter(([key, value]) => !(key in EXEMPT) && UNIT_LITERAL.test(value))
		.map(([key, value]) => `${key}: ${value}`);
}

test('every ARB is checked', () => {
	const arbs = readdirSync(L10N).filter((f) => f.endsWith('.arb'));
	for (const f of arbs) assert.ok(ARB_LOCALE[f], `add ${f} to ARB_LOCALE`);
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: no badge or recap string hard-codes a unit`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const scoped = Object.entries(dict).filter(([k]) => WEB_SCOPE.test(k));
		assert.ok(scoped.length > 100, `${loc}: the scope matched only ${scoped.length} keys`);
		assert.deepEqual(offenders(scoped), []);
		for (const key of Object.keys(EXEMPT)) {
			if (key.includes('.')) assert.ok(key in dict, `${key} is exempt but no longer exists; drop it`);
		}
	});
}

for (const file of Object.keys(ARB_LOCALE)) {
	test(`${file}: no badge or recap string hard-codes a unit`, () => {
		const arb = JSON.parse(readFileSync(resolve(L10N, file), 'utf8')) as Record<string, unknown>;
		const scoped = Object.entries(arb).filter(
			(e): e is [string, string] => ARB_SCOPE.test(e[0]) && typeof e[1] === 'string',
		);
		assert.ok(scoped.length > 50, `${file}: the scope matched only ${scoped.length} keys`);
		assert.deepEqual(offenders(scoped), []);
		for (const key of Object.keys(EXEMPT)) {
			if (!key.includes('.')) assert.ok(key in arb, `${key} is exempt but no longer exists; drop it`);
		}
	});
}

test('the guard catches the wording it exists for', () => {
	assert.equal(offenders([['badges.x', 'Ran 42.2 km in a single run']]).length, 1);
	assert.equal(offenders([['recap.x', '5,000 m climbed']]).length, 1);
	assert.equal(offenders([['recap.x', '{meters} m climbed']]).length, 0);
	assert.equal(offenders([['badges.x', '1回のランで5km走破']]).length, 1);
	assert.equal(offenders([['badges.x', '5 000 km enregistrés']]).length, 1);
	assert.equal(offenders([['badges.x', 'Ran 3 miles']]).length, 1);
	assert.equal(offenders([['badges.x', 'Ran {distance} in a single run']]).length, 0);
	assert.equal(offenders([['recap.x', 'Active in 6 months']]).length, 0);
	assert.equal(offenders([['recap.x', '200 runs']]).length, 0);
	assert.equal(offenders([['recap.x', 'Kilometraje serio']]).length, 0);
	assert.equal(offenders([['recap.x', '5.000 Höhenmeter']]).length, 1);
});
