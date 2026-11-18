import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { en } from './locales/en';
import { messages as de } from './locales/de';
import { messages as es } from './locales/es';
import { messages as fr } from './locales/fr';
import { messages as ja } from './locales/ja';
import { messages as ptPT } from './locales/pt-PT';
import { messages as ptBR } from './locales/pt-BR';
import { translatableStrings } from '../help/translate';
import type { Guide, GuideTranslation } from '../help/types';

// Every catalogue writes the one-character ellipsis "…" (U+2026), never three
// full stops, which can wrap between the dots and read as three sentences to
// a screen reader (decisions § 2539, widened to web in § 2556). The phone's
// ARBs and Dart literals are held to the same rule by l10n_parity_test.dart
// and ellipsis_literal_guard_test.dart.

const CATALOGUES = { en, de, es, fr, ja, 'pt-PT': ptPT, 'pt-BR': ptBR } as Record<string, Record<string, string>>;
const HELP_DIR = join(import.meta.dirname, '..', 'help');

function offenders(entries: [string, string][]): string[] {
	return entries.filter(([, v]) => v.includes('...')).map(([k, v]) => `${k}: ${v}`);
}

for (const [locale, messages] of Object.entries(CATALOGUES)) {
	test(`${locale}: an ellipsis is the single character, never three full stops`, () => {
		assert.deepEqual(offenders(Object.entries(messages)), []);
	});
}

const helpTexts: [string, string][] = [];
for (const file of readdirSync(join(HELP_DIR, 'guides')).filter((f) => f.endsWith('.ts'))) {
	const mod = (await import(pathToFileURL(join(HELP_DIR, 'guides', file)).href)) as { guide?: Guide };
	if (mod.guide) for (const [path, text] of translatableStrings(mod.guide)) helpTexts.push([`en/${mod.guide.id}#${path}`, text]);
}
for (const locale of Object.keys(CATALOGUES).filter((l) => l !== 'en')) {
	const dir = join(HELP_DIR, 'translations', locale);
	if (!existsSync(dir)) continue;
	for (const file of readdirSync(dir).filter((f) => f.endsWith('.ts'))) {
		const mod = (await import(pathToFileURL(join(dir, file)).href)) as { translation?: GuideTranslation };
		const t = mod.translation;
		if (t) for (const [path, text] of translatableStrings(t)) helpTexts.push([`${locale}/${t.id}#${path}`, text]);
	}
}

test('help guides and their translations: an ellipsis is the single character', () => {
	assert.ok(helpTexts.length > 100, 'the guide loader found the guides');
	assert.deepEqual(offenders(helpTexts), []);
});

test('the guard catches the slips it exists for', () => {
	assert.equal(offenders([['x', 'Loading...']]).length, 1);
	assert.equal(offenders([['x', '読み込み中...']]).length, 1);
	assert.equal(offenders([['x', 'Loading…']]).length, 0);
	assert.equal(offenders([['x', 'Wait. Then go.']]).length, 0);
});
