import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// A park course or segment time is a Threkir time on public paths, never an
// event's result, so no string about one may call a time a record (decisions
// § 2460, memo reviews/legal-parkrun-park-courses.md). A season's fastest is
// "Fastest in {year}". A runner's own personal record is a different claim and
// lives outside these namespaces; the phrase is stripped before the check so a
// course string that mentions one still passes.

const HERE = dirname(fileURLToPath(import.meta.url));
const L10N = resolve(HERE, '../../../../mobile_android/lib/l10n');

const WEB_SCOPE = /^(parks\.|segments\.|shareCourse\.|races\.anyTime)/;
const ARB_SCOPE = /^(parks|segment|racesAnyTime|shareCourse|shareCardCourse)/;

const RECORD_WORD: Record<string, RegExp> = {
	en: /\brecords?\b/i,
	de: /rekord/i,
	fr: /\brecords?\b/i,
	es: /\br[ée]cords?\b/i,
	'pt-PT': /\brecordes?\b/i,
	'pt-BR': /\brecordes?\b/i,
	ja: /レコード|コース記録|年の記録|記録保持|最高記録/,
};

const PERSONAL_RECORD: Record<string, RegExp> = {
	en: /personal records?/gi,
	de: /persönliche[nrs]? rekord\w*/gi,
	fr: /records? personnels?/gi,
	es: /r[ée]cords? personal(es)?/gi,
	'pt-PT': /recordes? pessoa(l|is)/gi,
	'pt-BR': /recordes? pessoa(l|is)/gi,
	ja: /自己記録/g,
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

function offenders(locale: string, entries: [string, string][]): string[] {
	const word = RECORD_WORD[locale];
	const personal = PERSONAL_RECORD[locale];
	assert.ok(word && personal, `no record pattern for ${locale}`);
	return entries
		.filter(([, value]) => word.test(value.replace(personal, '')))
		.map(([key, value]) => `${key}: ${value}`);
}

test('every shipped locale and ARB has a record pattern', () => {
	for (const loc of SUPPORTED_LOCALES) assert.ok(RECORD_WORD[loc], `add ${loc} to RECORD_WORD`);
	const arbs = readdirSync(L10N).filter((f) => f.endsWith('.arb'));
	for (const f of arbs) assert.ok(ARB_LOCALE[f], `add ${f} to ARB_LOCALE`);
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: no park course or segment string calls a time a record`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const scoped = Object.entries(dict).filter(([k]) => WEB_SCOPE.test(k));
		assert.ok(scoped.length > 50, `${loc}: the scope matched only ${scoped.length} keys`);
		assert.deepEqual(offenders(loc, scoped), []);
	});
}

for (const [file, loc] of Object.entries(ARB_LOCALE)) {
	test(`${file}: no park course or segment string calls a time a record`, () => {
		const arb = JSON.parse(readFileSync(resolve(L10N, file), 'utf8')) as Record<string, unknown>;
		const scoped = Object.entries(arb).filter(
			(e): e is [string, string] => ARB_SCOPE.test(e[0]) && typeof e[1] === 'string',
		);
		assert.ok(scoped.length > 50, `${file}: the scope matched only ${scoped.length} keys`);
		assert.deepEqual(offenders(loc, scoped), []);
	});
}

test('the guard catches the wording it exists for', () => {
	assert.equal(offenders('en', [['races.anyTimeFastest', '{year} record: {time}']]).length, 1);
	assert.equal(offenders('en', [['parks.x', 'Course record']]).length, 1);
	assert.equal(offenders('en', [['parks.x', 'Your personal record still counts']]).length, 0);
	assert.equal(offenders('en', [['parks.x', 'Run it with Threkir recording']]).length, 0);
	assert.equal(offenders('de', [['parks.x', 'Streckenrekord']]).length, 1);
	assert.equal(offenders('ja', [['parks.x', '2026年の記録：24:31']]).length, 1);
});
