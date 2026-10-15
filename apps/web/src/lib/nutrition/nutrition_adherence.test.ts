import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	CEILING_TOLERANCE,
	FLOOR_TOLERANCE,
	macroVerdict,
	nutritionAdherence,
	PARTIAL_LOG_FRACTION,
} from './nutrition_adherence';
import type { PrescribedDay } from './meal_plan';

function day(opts: Partial<PrescribedDay> = {}): PrescribedDay {
	return { calories: 2000, proteinG: 150, carbsG: 200, fatG: 70, isTrainingDay: false, ...opts };
}

function eaten(calories: number, proteinG: number, carbsG: number, fatG: number) {
	return { calories, proteinG, carbsG, fatG };
}

test('tolerances and the partial threshold are the published values', () => {
	assert.equal(CEILING_TOLERANCE, 0.1);
	assert.equal(FLOOR_TOLERANCE, 0.1);
	assert.equal(PARTIAL_LOG_FRACTION, 0.5);
});

test('a ceiling macro is met up to 10% over and over past it', () => {
	assert.equal(macroVerdict('calories', 2200, 2000), 'met');
	assert.equal(macroVerdict('calories', 2201, 2000), 'over');
	assert.equal(macroVerdict('fat', 40, 70), 'met');
});

test('a floor macro is met from 10% under and under below it', () => {
	assert.equal(macroVerdict('protein', 135, 150), 'met');
	assert.equal(macroVerdict('protein', 134, 150), 'under');
	assert.equal(macroVerdict('carbs', 400, 200), 'met');
});

test('a non-finite or negative actual counts as nothing eaten', () => {
	assert.equal(macroVerdict('protein', Number.NaN, 150), 'under');
	assert.equal(macroVerdict('calories', -50, 2000), 'met');
});

test('nutritionAdherence returns null without a prescription', () => {
	assert.equal(nutritionAdherence(null, eaten(1800, 150, 200, 60)), null);
	assert.equal(nutritionAdherence(day({ calories: 0 }), eaten(1800, 150, 200, 60)), null);
});

test('a day inside every band is on_target', () => {
	const a = nutritionAdherence(day(), eaten(1950, 152, 190, 72));
	assert.equal(a?.verdict, 'on_target');
	assert.deepEqual(
		a?.perMacro.map((m) => [m.kind, m.verdict]),
		[
			['calories', 'met'],
			['protein', 'met'],
			['carbs', 'met'],
			['fat', 'met'],
		],
	);
});

test('an off_target day names which macro missed and in which direction', () => {
	const a = nutritionAdherence(day(), eaten(2100, 110, 210, 95));
	assert.equal(a?.verdict, 'off_target');
	assert.deepEqual(
		a?.perMacro.filter((m) => m.verdict !== 'met').map((m) => [m.kind, m.verdict, m.actual, m.target]),
		[
			['protein', 'under', 110, 150],
			['fat', 'over', 95, 70],
		],
	);
});

test('a day under half the prescribed calories is partial, however it splits', () => {
	const a = nutritionAdherence(day(), eaten(999, 150, 200, 10));
	assert.equal(a?.verdict, 'partial');
	assert.equal(nutritionAdherence(day(), eaten(1000, 150, 200, 10))?.verdict, 'on_target');
});

test('an empty day is partial', () => {
	assert.equal(nutritionAdherence(day(), eaten(0, 0, 0, 0))?.verdict, 'partial');
});

test('a kcal-only plan is judged on calories alone', () => {
	const a = nutritionAdherence(
		day({ proteinG: null, carbsG: null, fatG: null }),
		eaten(1900, 20, 400, 120),
	);
	assert.equal(a?.verdict, 'on_target');
	assert.deepEqual(a?.perMacro.map((m) => m.kind), ['calories']);
});

test('an over-the-ceiling calorie day is off_target even with the macros met', () => {
	assert.equal(nutritionAdherence(day(), eaten(2300, 160, 220, 70))?.verdict, 'off_target');
});

test('a negative consumed total is read as zero, never propagated', () => {
	const a = nutritionAdherence(day(), eaten(-50, 150, 200, 70));
	assert.equal(a?.verdict, 'partial');
	assert.equal(a?.perMacro[0].actual, 0);
});
