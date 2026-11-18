import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messages as ja } from './locales/ja';

// A Japanese count takes no space between the number and its counter or unit
// word (ja locale guide): 「#件のラン」「{n}回連続」「約{minutes}分」「#日」, and no
// space before the number when the text in front of it is Japanese
// (「未読{n}件」). The catalogue mixed the two forms (#1374). A Latin unit keeps
// its space (「5.0 km」), and so does a Latin neighbour (「Pro 8回」). The
// counter list matches the phone's guard in l10n_parity_test.dart, マイル and 月
// included.

const COUNTER = '(?:件|回|ポイント|マイル|文字|つ|点|人|名|分|秒|時間|個|枚|本|歳|位|周|セット|か所|種類|日|週間|か月|ヶ月|年|月)';
const NUMBER = '(?:\\d+(?:[.,]\\d+)?|#|\\{[a-zA-Z_]+\\})';
// A plural that opens on a count: 「支援者 {count, plural, other {#人}}」.
const PLURAL_COUNT = new RegExp(`[ぁ-んァ-ヶ一-龥ー々、。：（「][ \\u00a0]\\{[a-zA-Z_]+, plural, other \\{#[ \\u00a0]?${COUNTER}`, 'u');
const SPACE_AFTER = new RegExp(`(?:\\d|#|\\})[ \\u00a0]${COUNTER}`, 'u');
const SPACE_BEFORE = new RegExp(`[ぁ-んァ-ヶ一-龥ー々、。：（「][ \\u00a0]${NUMBER}[ \\u00a0]?${COUNTER}`, 'u');

// A place on a period's board takes の after the period: 「{season}年の{rank}位」
// 「{month}の{rank}位」. Run together, 「2027年3位」 reads as a date and
// 「11月 2位」 as two fragments.
const RANK_WITHOUT_NO = new RegExp(`(?:年|月|\\})[ \\u00a0]?${NUMBER}位`, 'u');

function offenders(entries: [string, string][]): string[] {
	return entries
		.filter(([, v]) => SPACE_AFTER.test(v) || SPACE_BEFORE.test(v) || PLURAL_COUNT.test(v) || RANK_WITHOUT_NO.test(v))
		.map(([k, v]) => `${k}: ${v}`);
}

test('ja web catalogue: no space around a count with a counter or unit word, and a period rank takes の', () => {
	assert.deepEqual(offenders(Object.entries(ja as Record<string, string>)), []);
});

test('the guard catches the slips it exists for', () => {
	assert.equal(offenders([['x', '{n, plural, other {# 件のキュー}}']]).length, 1);
	assert.equal(offenders([['x', '未読 {n}件']]).length, 1);
	assert.equal(offenders([['x', '約 {minutes} 分']]).length, 1);
	assert.equal(offenders([['x', '支援者 {count, plural, other {#人}}']]).length, 1);
	assert.equal(offenders([['x', '{n, plural, other {#件のキュー}}']]).length, 0);
	assert.equal(offenders([['x', '無料プラン: 1時間に2回まで、Pro: 8回まで']]).length, 0);
	assert.equal(offenders([['x', '5.0 km · 5:00 /km']]).length, 0);
	assert.equal(offenders([['x', '最初の {n} マイル']]).length, 1);
	assert.equal(offenders([['x', '最初の{n}マイル']]).length, 0);
	assert.equal(offenders([['x', '{season}年{rank}位']]).length, 1);
	assert.equal(offenders([['x', '{month} {rank}位']]).length, 1);
	assert.equal(offenders([['x', '{month}の{rank}位、{season}年の{seasonRank}位']]).length, 0);
});
