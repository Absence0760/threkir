import { test } from 'node:test';
import assert from 'node:assert/strict';
import { messages as ja } from './locales/ja';

// A Japanese count takes no space between the number and its counter or unit
// word (ja locale guide): 「#件のラン」「{n}回連続」「約{minutes}分」「#日」, and no
// space before the number when the text in front of it is Japanese
// (「未読{n}件」). The catalogue mixed the two forms (#1374). A Latin unit keeps
// its space (「5.0 km」), and so does a Latin neighbour (「Pro 8回」).

const COUNTER = '(?:件|回|ポイント|文字|つ|点|人|名|分|秒|時間|個|枚|本|歳|位|周|セット|か所|種類|日|週間|か月|ヶ月|年)';
const NUMBER = '(?:\\d+(?:[.,]\\d+)?|#|\\{[a-zA-Z_]+\\})';
const SPACE_AFTER = new RegExp(`(?:\\d|#|\\})[ \\u00a0]${COUNTER}`, 'u');
const SPACE_BEFORE = new RegExp(`[ぁ-んァ-ヶ一-龥ー々、。：（「][ \\u00a0]${NUMBER}[ \\u00a0]?${COUNTER}`, 'u');

function offenders(entries: [string, string][]): string[] {
	return entries.filter(([, v]) => SPACE_AFTER.test(v) || SPACE_BEFORE.test(v)).map(([k, v]) => `${k}: ${v}`);
}

test('ja web catalogue: no space around a count with a counter or unit word', () => {
	assert.deepEqual(offenders(Object.entries(ja as Record<string, string>)), []);
});

test('the guard catches the slips it exists for', () => {
	assert.equal(offenders([['x', '{n, plural, other {# 件のキュー}}']]).length, 1);
	assert.equal(offenders([['x', '未読 {n}件']]).length, 1);
	assert.equal(offenders([['x', '約 {minutes} 分']]).length, 1);
	assert.equal(offenders([['x', '{n, plural, other {#件のキュー}}']]).length, 0);
	assert.equal(offenders([['x', '無料プラン: 1時間に2回まで、Pro: 8回まで']]).length, 0);
	assert.equal(offenders([['x', '5.0 km · 5:00 /km']]).length, 0);
});
