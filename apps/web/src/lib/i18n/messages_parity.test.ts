import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { en } from './locales/en';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// `satisfies Messages` already enforces key parity at compile time; this
// guards it at runtime too and — by iterating SUPPORTED_LOCALES through
// the typed loader registry rather than a hard-coded list — guarantees
// that *every* shipped locale is loadable, complete, non-empty, and
// preserves the English {placeholder} set. Adding a locale to
// SUPPORTED_LOCALES (with its CATALOGUE_LOADERS entry) automatically
// brings it under this test; a forgotten/empty/placeholder-drifted
// catalogue fails here.

const enRecord = en as Record<string, string>;
const enKeys = Object.keys(en).sort();

function placeholders(s: string): string[] {
	return (s.match(/\{[a-zA-Z0-9_]+\}/g) ?? []).sort();
}

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: catalogue is loadable, complete, non-empty, placeholder-faithful`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		assert.deepEqual(Object.keys(dict).sort(), enKeys, `${loc} key set differs from en`);
		for (const key of enKeys) {
			assert.ok(dict[key].trim().length > 0, `${loc}.${key} is empty`);
			assert.deepEqual(
				placeholders(dict[key]),
				placeholders(enRecord[key]),
				`${loc}.${key} placeholder mismatch`,
			);
		}
	});
}

// A catalogue is an object literal, so a key written twice is not an error --
// the later wins and `Object.keys` reports it once, which means every
// assertion above passes while the shipped string is the stale one. That is
// not hypothetical: the landing hero shipped its OLD subhead this way, with a
// green parity suite, because a new copy deck was appended above the original
// key instead of replacing it. Source-level, because by the time the module
// has been evaluated the evidence is gone.
for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: no key is declared twice in the source`, async () => {
		const file = new URL(`./locales/${loc}.ts`, import.meta.url);
		const source = await readFile(file, 'utf-8');
		const seen = new Set<string>();
		const duplicated: string[] = [];
		for (const line of source.split('\n')) {
			const key = /^\t"([^"]+)": /.exec(line)?.[1] ?? /^\t'([^']+)': /.exec(line)?.[1];
			if (key === undefined) continue;
			if (seen.has(key)) duplicated.push(key);
			seen.add(key);
		}
		assert.deepEqual(
			duplicated,
			[],
			`${loc} declares these keys more than once; the last one silently wins, so ` +
				'the string you edited may not be the string that ships',
		);
	});
}
