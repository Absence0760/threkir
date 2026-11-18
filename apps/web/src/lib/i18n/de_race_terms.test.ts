import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CATALOGUE_LOADERS } from './catalogues';

// German names a race one way (decisions § 2554, the de glossary): a race as a
// thing (the plan's goal race, a race in the calendar, the workout kind) is
// « Rennen », and « Wettkampf- » survives only in the fixed compounds for the
// racing occasion (Wettkampftag, Wettkampfwoche, Wettkampftempo,
// Wettkampfverpflegung, Wettkampfdatum, Wettkampfdistanz, Wettkampfzeit). The
// plan detail screen read « Wettkampf » beside « Rennen », and the goal race
// was both « Zielwettkampf » and « Zielrennen ».

const HERE = dirname(fileURLToPath(import.meta.url));
const ARB = resolve(HERE, '../../../../mobile_android/lib/l10n/app_de.arb');
const HELP_DE = resolve(HERE, '../help/translations/de');
const LEARN = resolve(HERE, '../learn/guides');

const REJECTED: [RegExp, string][] = [
	[/(?<![\p{L}-])Wettk[aä]mpf(e|es|s|en)?(?![\p{L}-])/u, 'a race is « Rennen », never « Wettkampf » on its own'],
	[/Zielwettkampf/, 'the goal race is « Zielrennen »'],
	[/Wettkampf(ergebnis|strecke|zeile|liste|termin)/, '« Rennergebnis », « Rennstrecke », « Rennzeilen », « Wettkampfdatum »'],
	[/(?<!\p{Ll})Renn(tag|woche|distanz|tempo|verpflegung)/u, 'the racing occasion is « Wettkampftag », « Wettkampfwoche », « Wettkampfdistanz » …'],
];

function offenders(source: string, texts: Iterable<[string, string]>): string[] {
	const out: string[] = [];
	for (const [where, text] of texts) {
		for (const [re, why] of REJECTED) {
			if (re.test(text)) out.push(`${source} ${where}: ${why}: ${text.slice(0, 120)}`);
		}
	}
	return out;
}

test('de: the web catalogue and the phone ARB name a race one way', async () => {
	const web = (await CATALOGUE_LOADERS.de()) as Record<string, string>;
	const arb = JSON.parse(readFileSync(ARB, 'utf8')) as Record<string, string>;
	const arbMessages = Object.entries(arb).filter(([k]) => !k.startsWith('@'));
	assert.deepEqual(
		[...offenders('web', Object.entries(web)), ...offenders('arb', arbMessages)],
		[],
	);
	assert.equal(web['workoutKind.race'], 'Rennen');
	assert.equal(arb.workoutKindRace, web['workoutKind.race']);
});

test('de: the help and Learn guides name a race one way', () => {
	const files: [string, string][] = [
		...readdirSync(HELP_DE)
			.filter((f) => f.endsWith('.ts'))
			.map((f): [string, string] => [`help/${f}`, readFileSync(join(HELP_DE, f), 'utf8')]),
		...readdirSync(LEARN)
			.filter((f) => f.endsWith('.de.md'))
			.map((f): [string, string] => [`learn/${f}`, readFileSync(join(LEARN, f), 'utf8')]),
	];
	assert.ok(files.length > 10, `only ${files.length} German guides found — moved? Update this guard.`);
	const lines = files.flatMap(([f, text]) =>
		text.split('\n').map((line, i): [string, string] => [`${f}:${i + 1}`, line]),
	);
	assert.deepEqual(offenders('guide', lines), []);
});
