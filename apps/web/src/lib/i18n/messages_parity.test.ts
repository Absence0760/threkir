import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { en } from './locales/en';
import { SUPPORTED_LOCALES, type Locale } from './locale';
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

// Every translated locale quotes with its own typographic marks, which its
// glossary (.claude/agents/i18n/languages/<loc>.md) sets, so a straight `"` in
// one of its messages is a slip -- 68 of them shipped across pt-BR, pt-PT, de,
// es and fr before this guard. A straight double quote is never ICU syntax (ICU
// escapes with the apostrophe), so every one in a message value is a quotation
// mark. Typed on the locale, so a new locale cannot ship without naming its
// marks here. English is left out: its catalogue quotes with the straight pair
// throughout. Checked on the loaded value, which sees through the literal's own
// delimiters and `\"` escapes. The mobile twin is in
// apps/mobile_android/test/architecture_guards_test.dart.
const QUOTATION_MARKS: Record<Exclude<Locale, 'en'>, string> = {
	de: '„…“',
	fr: '« … »',
	es: '«…»',
	ja: '「…」',
	'pt-PT': '“…”',
	'pt-BR': '“…”',
};

for (const loc of SUPPORTED_LOCALES) {
	if (loc === 'en') continue;
	test(`${loc}: no message quotes with a straight double quote`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const straight = Object.keys(dict).filter((key) => dict[key].includes('"'));
		assert.deepEqual(
			straight,
			[],
			`${loc} quotes with a straight " in these messages; its glossary uses ${QUOTATION_MARKS[loc]}`,
		);
	});
}

// The text of every `one {…}` branch of a `{var, plural, …}` block in `s`,
// brace-balanced so a branch may itself hold `{placeholder}` tokens.
function oneBranches(s: string): string[] {
	const out: string[] = [];
	const open = /\{\w+,\s*plural,/g;
	for (let m = open.exec(s); m; m = open.exec(s)) {
		let i = m.index + m[0].length;
		for (;;) {
			const label = /^\s*([^\s{}]+)\s*\{/.exec(s.slice(i));
			if (!label) break;
			const start = i + label[0].length;
			let depth = 1;
			let j = start;
			while (j < s.length && depth > 0) {
				if (s[j] === '{') depth++;
				else if (s[j] === '}') depth--;
				j++;
			}
			if (label[1] === 'one') out.push(s.slice(start, j - 1));
			i = j;
		}
	}
	return out;
}

// Every `{var, plural, …}` block in `s`: its variable, its branches by
// selector, and whether nothing but whitespace stands outside it.
function pluralBlocks(s: string): { arg: string; whole: boolean; branches: Record<string, string> }[] {
	const out: { arg: string; whole: boolean; branches: Record<string, string> }[] = [];
	const open = /\{(\w+),\s*plural,/g;
	for (let m = open.exec(s); m; m = open.exec(s)) {
		const branches: Record<string, string> = {};
		let i = m.index + m[0].length;
		for (;;) {
			const label = /^\s*([^\s{}]+)\s*\{/.exec(s.slice(i));
			if (!label) break;
			const start = i + label[0].length;
			let depth = 1;
			let j = start;
			while (j < s.length && depth > 0) {
				if (s[j] === '{') depth++;
				else if (s[j] === '}') depth--;
				j++;
			}
			branches[label[1]] = s.slice(start, j - 1);
			i = j;
		}
		const close = s.indexOf('}', i);
		const whole = s.slice(0, m.index).trim() === '' && close >= 0 && s.slice(close + 1).trim() === '';
		out.push({ arg: m[1], whole, branches });
	}
	return out;
}

// The variable of every plural that is the whole message, whose `one` branch
// names no count (`#` or `{var}`) and which has no `=0` / `zero` branch. That
// `one` branch is the sentence for exactly one ("Invitation envoyée"), so
// where `one` also takes 0 it is what 0 renders. A plural inside a longer
// sentence is agreement ("est en" / "sont en"), and the singular for 0 is
// what CLDR asks of fr and pt-BR, so it is not listed.
function countlessOne(s: string): string[] {
	return pluralBlocks(s)
		.filter(
			(b) =>
				b.whole &&
				'one' in b.branches &&
				!b.branches.one.includes('#') &&
				!b.branches.one.includes(`{${b.arg}}`) &&
				!('=0' in b.branches) &&
				!('zero' in b.branches),
		)
		.map((b) => b.arg);
}

// A `1` standing as a number of its own: not part of `10`, `1.5`, `1RM`.
const LITERAL_ONE = /(?<![\p{L}\p{N}.,])1(?![\p{L}\p{N}.,])/u;

// interpolate() picks a plural branch with Intl.PluralRules for the active
// locale, and in some locales CLDR's `one` covers counts other than 1 (fr and
// pt-BR take 0 too). A `one` branch that copies the English "1" then renders
// "1 …" for 0, which is how `filterBarFiltersCount` shipped "Filtres, 1 actif"
// with no filter on. Use `#` instead. Which locales are affected is derived
// from the rules, not listed. The mobile twin is in
// apps/mobile_android/test/l10n_parity_test.dart.
function oneCoversMoreThanOne(loc: string): boolean {
	const rules = new Intl.PluralRules(loc);
	return Array.from({ length: 101 }, (_, n) => n).some((n) => n !== 1 && rules.select(n) === 'one');
}

test('the one-branch scan reads plural one {} branches only', () => {
	assert.deepEqual(oneBranches('{n, plural, one {1 run} other {# runs}}'), ['1 run']);
	assert.deepEqual(oneBranches('{n, plural, =1 {x} one {{a} y} other {z}}'), ['{a} y']);
	assert.deepEqual(oneBranches('{k, select, one {1} other {2}}'), []);
	assert.ok(LITERAL_ONE.test('Filtres, 1 actif'));
	for (const ok of ['10 km', '1.5 km', '1RM', '# actif']) assert.ok(!LITERAL_ONE.test(ok), ok);
	assert.ok(oneCoversMoreThanOne('fr') && oneCoversMoreThanOne('pt-BR'));
	assert.ok(!oneCoversMoreThanOne('en') && !oneCoversMoreThanOne('de'));
});

test('the countless-one scan reads whole-message plurals only', () => {
	assert.deepEqual(countlessOne('{n, plural, one {Sent} other {# sent}}'), ['n']);
	assert.deepEqual(countlessOne(' {n, plural, one {Sent} other {# sent}} '), ['n']);
	for (const ok of [
		'{n, plural, one {# sent} other {# sent}}',
		'{n, plural, one {{n} sent} other {# sent}}',
		'{n, plural, =0 {None} one {Sent} other {# sent}}',
		'{n, plural, other {# sent}}',
		'{list} {n, plural, one {is} other {are}} in',
	])
		assert.deepEqual(countlessOne(ok), [], ok);
});

for (const loc of SUPPORTED_LOCALES) {
	if (!oneCoversMoreThanOne(loc)) continue;
	test(`${loc}: no plural one branch spells out a literal 1`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const offenders = Object.keys(dict)
			.filter((key) => oneBranches(dict[key]).some((b) => LITERAL_ONE.test(b)))
			.sort();
		assert.deepEqual(
			offenders,
			[],
			`${loc}: \`one\` also covers counts other than 1 here, so a literal 1 in it is wrong; use #`,
		);
	});

	// The same 0 reached without a digit: a whole-message plural whose `one`
	// branch is the sentence for exactly one. Put `#` in it, or give 0 its own
	// `=0 {…}` (interpolate() answers an exact match before the plural rule).
	test(`${loc}: no whole-message plural leaves 0 to a count-free one branch`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const offenders = Object.keys(dict)
			.flatMap((key) => countlessOne(dict[key]).map((arg) => `${key} (${arg})`))
			.sort();
		assert.deepEqual(
			offenders,
			[],
			`${loc}: \`one\` also covers 0 here, so a \`one\` branch with no # is what 0 renders; use # or add =0 {…}`,
		);
	});
}
