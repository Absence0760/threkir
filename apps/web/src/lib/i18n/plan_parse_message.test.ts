import { test } from 'node:test';
import assert from 'node:assert/strict';
import { planParseMessage } from './plan_parse_message';
import { PlanParseError, parsePlanMarkdown, type PlanParseCode } from '../training/plan_serialize';
import { interpolate } from './interpolate';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';
import type { MessageKey } from './messages';

const CODES: PlanParseCode[] = [
	'badDistance', 'badPace', 'duplicateColumn', 'missingColumn', 'raceNameTooLong',
	'badRacePriority', 'badGoalTime', 'badWeek', 'badDate', 'unknownKind',
	'raceFieldsOnNonRace', 'noRows', 'noGoalDistance', 'beforeStart', 'notJson',
	'noWorkoutsArray', 'badJsonShape', 'badTaperStamp',
];
const PARAMS = {
	cell: 'CELL', column: 'COLUMN', name: 'NAME', max: '120', date: '2026-07-05',
	kind: 'easy', start: '2026-07-06', value: 'VALUE',
};

async function translator(locale: (typeof SUPPORTED_LOCALES)[number]) {
	const cat = (await CATALOGUE_LOADERS[locale]()) as Record<string, string>;
	return (key: MessageKey, params?: Record<string, string | number>) => {
		const v = cat[key];
		assert.ok(v, `${locale} is missing ${key}`);
		return interpolate(v, params ?? {});
	};
}

test('every refusal code reads in every locale, never as the parser message', async () => {
	const en = await translator('en');
	for (const locale of SUPPORTED_LOCALES) {
		const t = await translator(locale);
		for (const code of CODES) {
			const e = new PlanParseError(code, PARAMS, 'English message');
			const text = planParseMessage(e, t);
			assert.ok(text, `${locale} ${code}`);
			assert.ok(!text.includes('English message'), `${locale} ${code} shows the parser message`);
			assert.ok(!/\{\w+\}/.test(text), `${locale} ${code} left a placeholder: ${text}`);
			if (locale !== 'en') assert.notEqual(text, planParseMessage(e, en), `${locale} ${code} is still English`);
		}
	}
});

test('a real refusal names the cell it could not read', async () => {
	const t = await translator('en');
	let thrown: unknown;
	try {
		parsePlanMarkdown(
			['| Week | Date | Type | Distance | Pace | Notes |', '| --- | --- | --- | --- | --- | --- |', '| 1 | 07/05/2026 | easy | 5 km | | |'].join('\n'),
		);
	} catch (e) {
		thrown = e;
	}
	assert.equal(planParseMessage(thrown, t), 'Couldn\'t read the date "07/05/2026". Use YYYY-MM-DD.');
	assert.equal(planParseMessage(new Error('not a parse refusal'), t), null);
});
