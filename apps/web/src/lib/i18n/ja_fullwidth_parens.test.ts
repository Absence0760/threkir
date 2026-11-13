import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { messages as ja } from './locales/ja';

// Japanese text takes full-width parentheses （…） (ja locale guide). A
// half-width "(" right after Japanese text is a slip: "受取額(純額)" on the
// payouts page, quoted the same way in its help guide. A statute citation
// keeps its ASCII paragraph marks ("GDPR 第9条(2)(a)", "第9条2項(a)").

const HERE = dirname(fileURLToPath(import.meta.url));
const ARB = resolve(HERE, '../../../../mobile_android/lib/l10n/app_ja.arb');
const GUIDES = resolve(HERE, '../help/translations/ja');

const HALF_WIDTH_AFTER_JA = /[ぁ-んァ-ヶ一-龥ー々]\((?![0-9a-z]{1,2}\))/u;

function offenders(entries: [string, string][]): string[] {
	return entries.filter(([, v]) => HALF_WIDTH_AFTER_JA.test(v)).map(([k, v]) => `${k}: ${v}`);
}

test('ja web catalogue: no half-width parenthesis after Japanese text', () => {
	assert.deepEqual(offenders(Object.entries(ja as Record<string, string>)), []);
});

test('ja ARB: no half-width parenthesis after Japanese text', () => {
	const arb = JSON.parse(readFileSync(ARB, 'utf8')) as Record<string, unknown>;
	const strings = Object.entries(arb).filter((e): e is [string, string] => typeof e[1] === 'string');
	assert.deepEqual(offenders(strings), []);
});

test('ja help guides: no half-width parenthesis after Japanese text', () => {
	const lines = readdirSync(GUIDES)
		.filter((f) => f.endsWith('.ts'))
		.flatMap((f) => readFileSync(resolve(GUIDES, f), 'utf8').split('\n').map((l, i) => [`${f}:${i + 1}`, l] as [string, string]));
	assert.deepEqual(offenders(lines), []);
});

test('the guard catches the slip it exists for', () => {
	assert.equal(offenders([['x', '受取額(純額)']]).length, 1);
	assert.equal(offenders([['x', '受取額（純額）']]).length, 0);
	assert.equal(offenders([['x', 'GDPR 第9条(2)(a)']]).length, 0);
});
