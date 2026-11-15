import { test } from 'node:test';
import assert from 'node:assert/strict';
import { en } from './locales/en';
import { messages as de } from './locales/de';
import { messages as es } from './locales/es';
import { messages as fr } from './locales/fr';
import { messages as ja } from './locales/ja';
import { messages as ptPT } from './locales/pt-PT';
import { messages as ptBR } from './locales/pt-BR';

// A link's "↗" or trailing "→" is decoration. Inside the translatable text a
// screen reader announces it ("Spectator view north east arrow"), so the
// component draws it as an aria-hidden icon instead (#1374). An arrow between
// two values ("{from} → {to}", a menu path) carries meaning and stays.

const CATALOGUES = { en, de, es, fr, ja, 'pt-PT': ptPT, 'pt-BR': ptBR } as Record<string, Record<string, string>>;
const DECORATIVE = /↗|\s[→➜]\s*$/u;

function offenders(entries: [string, string][]): string[] {
	return entries.filter(([, v]) => DECORATIVE.test(v)).map(([k, v]) => `${k}: ${v}`);
}

for (const [locale, messages] of Object.entries(CATALOGUES)) {
	test(`${locale}: no decorative arrow inside a message`, () => {
		assert.deepEqual(offenders(Object.entries(messages)), []);
	});
}

test('the guard catches the slips it exists for', () => {
	assert.equal(offenders([['x', 'Spectator view ↗']]).length, 1);
	assert.equal(offenders([['x', 'View {year} recap →']]).length, 1);
	assert.equal(offenders([['x', '{from} → {to} — ease off']]).length, 0);
	assert.equal(offenders([['x', 'Strava → Settings → My Account']]).length, 0);
});
