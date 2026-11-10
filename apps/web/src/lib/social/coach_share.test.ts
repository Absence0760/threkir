import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
	COACH_SHARE_MAX_CHARS,
	coachAnswerParagraphs,
	coachShareExcerpt,
	parseDmKind,
	parseSharedInline,
	parseSharedMarkdown,
} from './coach_share.ts';

function migration(): string {
	const dir = fileURLToPath(new URL('../../../../backend/supabase/migrations/', import.meta.url));
	const file = readdirSync(dir).find((f) => f.endsWith('_dm_coach_share.sql'));
	assert.ok(file, 'the dm_coach_share migration is missing — re-anchor');
	return readFileSync(dir + file, 'utf8');
}

test('the cap is the one share_coach_message enforces', () => {
	const m = migration().match(/char_length\(v_body\) > (\d+)/);
	assert.ok(m, 'the excerpt cap was not found in the migration — re-anchor');
	assert.equal(COACH_SHARE_MAX_CHARS, Number(m[1]));
});

test('the split is the one private.coach_answer_paragraphs uses', () => {
	const sql = migration();
	assert.ok(sql.includes(String.raw`E'\n[ \t]*\n'`), 'the split pattern moved — re-anchor');
	assert.ok(sql.includes(String.raw`E' \t\n\r'`), 'the trimmed characters moved — re-anchor');
});

test('splits on blank lines, trims, drops empty paragraphs (shared with coach_share_test.sql)', () => {
	assert.deepEqual(
		coachAnswerParagraphs('First para.\n\n\n  Second\nline  \n \t\nThird\r\n\r\nFourth\n\n'),
		['First para.', 'Second\nline', 'Third', 'Fourth'],
	);
	assert.deepEqual(coachAnswerParagraphs(''), []);
	assert.deepEqual(coachAnswerParagraphs('   \n\n  '), []);
	assert.deepEqual(coachAnswerParagraphs('One'), ['One']);
});

test('the excerpt keeps answer order, drops repeats and out-of-range picks', () => {
	const p = ['a', 'b', 'c'];
	assert.equal(coachShareExcerpt(p, [2, 0, 2]), 'a\n\nc');
	assert.equal(coachShareExcerpt(p, [-1, 3, 1.5]), '');
	assert.equal(coachShareExcerpt(p, [1]), 'b');
});

test('an unknown kind is drawn as text', () => {
	assert.equal(parseDmKind('coach_share'), 'coach_share');
	assert.equal(parseDmKind('text'), 'text');
	assert.equal(parseDmKind('ai_assisted'), 'ai_assisted');
	assert.equal(parseDmKind('ai_reply'), 'text');
	assert.equal(parseDmKind(null), 'text');
});

test('inline marks become styled spans and a link keeps only its text', () => {
	assert.deepEqual(parseSharedInline('Run **easy**, *slow* and `5x1k` — see [plan](/plans/x)'), [
		{ text: 'Run ', style: 'plain' },
		{ text: 'easy', style: 'bold' },
		{ text: ', ', style: 'plain' },
		{ text: 'slow', style: 'italic' },
		{ text: ' and ', style: 'plain' },
		{ text: '5x1k', style: 'code' },
		{ text: ' — see plan', style: 'plain' },
	]);
});

test('unclosed marks and markup stay literal text', () => {
	assert.deepEqual(parseSharedInline('**open and * star'), [{ text: '**open and * star', style: 'plain' }]);
	assert.deepEqual(parseSharedInline('<img src=x onerror=alert(1)>'), [
		{ text: '<img src=x onerror=alert(1)>', style: 'plain' },
	]);
	assert.deepEqual(parseSharedInline('[js](javascript:alert(1))'), [{ text: 'js)', style: 'plain' }]);
});

test('blocks: headings, bullets, numbered items and paragraphs with their line breaks', () => {
	assert.deepEqual(
		parseSharedMarkdown('## This week\nKeep it easy\nand short.\n\n- Mon: rest\n* Tue: 5 km\n2) Long run\n> quoted'),
		[
			{ type: 'heading', spans: [{ text: 'This week', style: 'plain' }] },
			{ type: 'paragraph', spans: [{ text: 'Keep it easy\nand short.', style: 'plain' }] },
			{ type: 'bullet', spans: [{ text: 'Mon: rest', style: 'plain' }] },
			{ type: 'bullet', spans: [{ text: 'Tue: 5 km', style: 'plain' }] },
			{ type: 'ordered', marker: '2.', spans: [{ text: 'Long run', style: 'plain' }] },
			{ type: 'paragraph', spans: [{ text: 'quoted', style: 'plain' }] },
		],
	);
	assert.deepEqual(parseSharedMarkdown(''), []);
});
