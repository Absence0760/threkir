import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { messages as fr } from './locales/fr';

// French separates three senses of "race" (decisions § 2538, § 2555): a listed
// or planned race is « épreuve », the club-hosted live race « course », racing
// in general « compétition ». « course » alone is also a run, so the strings
// that name a race beside runs, or name racing in general, must not fall back
// to it. A pacing plan is « stratégie d'allure », the name the run page gives
// it. Each surface is pinned here because the
// phone, Wear OS and Apple Watch catalogues are separate files that drifted
// apart before (#1374).

const REPO_ROOT = resolve(import.meta.dirname, '..', '..', '..', '..', '..');
const WEB = fr as Record<string, string>;
const PHONE = JSON.parse(readFileSync(join(REPO_ROOT, 'apps/mobile_android/lib/l10n/app_fr.arb'), 'utf8')) as Record<string, unknown>;
const WEAR_XML = readFileSync(join(REPO_ROOT, 'apps/watch_wear/android/app/src/main/res/values-fr/strings.xml'), 'utf8');
const XCSTRINGS = JSON.parse(readFileSync(join(REPO_ROOT, 'apps/watch_ios/WatchApp/Localizable.xcstrings'), 'utf8')) as {
	strings: Record<string, { localizations?: Record<string, { stringUnit?: { value?: string } }> }>;
};
const HELP_FR = join(REPO_ROOT, 'apps/web/src/lib/help/translations/fr');

function wear(name: string): string | undefined {
	return WEAR_XML.match(new RegExp(`<string name="${name}">([^<]*)</string>`))?.[1];
}

function appleWatch(key: string): string | undefined {
	return XCSTRINGS.strings[key]?.localizations?.fr?.stringUnit?.value;
}

function phone(key: string): string | undefined {
	const v = PHONE[key];
	return typeof v === 'string' ? v : undefined;
}

// Racing in general is never « course », and a pacing plan is never
// « stratégie de course ». « le jour de la course » stays legal: the host guide
// says it of a live race.
const FORBIDDEN = [/stratégie de course/iu, /pas une course\b/iu];

function offenders(entries: [string, string][]): string[] {
	return entries.filter(([, v]) => FORBIDDEN.some((re) => re.test(v))).map(([k, v]) => `${k}: ${v}`);
}

test('the race workout kind is « Épreuve » on every surface', () => {
	assert.deepEqual(
		{ web: WEB['workoutKind.race'], phone: phone('workoutKindRace'), wear: wear('workout_kind_race'), appleWatch: appleWatch('workoutKind.race') },
		{ web: 'Épreuve', phone: 'Épreuve', wear: 'Épreuve', appleWatch: 'Épreuve' },
	);
});

test('the race workout short label abbreviates « Épreuve », the same on every surface', () => {
	const shorts = { web: WEB['workoutKindShort.race'], phone: phone('workoutKindShortRace'), wear: wear('workout_kind_short_race') };
	for (const [surface, value] of Object.entries(shorts)) {
		assert.ok(value !== undefined && value.length <= 5 && 'Épreuve'.startsWith(value.replace(/\.$/, '')), `${surface}: ${value}`);
	}
	assert.equal(new Set(Object.values(shorts)).size, 1, JSON.stringify(shorts));
});

test('the share card names the race the run finished « Épreuve »', () => {
	assert.equal(WEB['runShare.kindRace'], 'Épreuve');
	assert.equal(phone('shareCardKindRace'), 'Épreuve');
});

test('the help category for races is « Compétitions », not the runs word', () => {
	assert.equal(WEB['help.categoryRaces'], 'Compétitions');
	assert.equal(phone('helpCategoryRaces'), 'Compétitions');
});

test('a pacing plan is « stratégie d’allure » on both surfaces', () => {
	assert.equal(phone('runRaceStrategy'), "Stratégie d'allure");
	assert.equal(phone('runDetailStrategyTitle'), "Stratégie d'allure");
	assert.equal(WEB['runDetail.strategyTitle'], "Stratégie d'allure");
});

test('fr web catalogue: no « stratégie de course » or « pas une course »', () => {
	assert.deepEqual(offenders(Object.entries(WEB)), []);
});

test('fr phone catalogue: no « stratégie de course » or « pas une course »', () => {
	const entries = Object.entries(PHONE).filter((e): e is [string, string] => !e[0].startsWith('@') && typeof e[1] === 'string');
	assert.deepEqual(offenders(entries), []);
});

test('fr help guides: no « stratégie de course » or « pas une course »', () => {
	const entries = readdirSync(HELP_FR).map((f): [string, string] => [f, readFileSync(join(HELP_FR, f), 'utf8')]);
	assert.deepEqual(offenders(entries), []);
});

test('the guard catches the slips it exists for', () => {
	assert.equal(offenders([['x', 'Retirer la stratégie de course']]).length, 1);
	assert.equal(offenders([['x', "C'est un contre-la-montre, pas une course."]]).length, 1);
	assert.equal(offenders([['x', "Retirer la stratégie d'allure"]]).length, 0);
	assert.equal(offenders([['x', 'pas une compétition']]).length, 0);
	assert.equal(offenders([['x', 'Prochaine séance difficile dans ~1 jour de course facile.']]).length, 0);
});
