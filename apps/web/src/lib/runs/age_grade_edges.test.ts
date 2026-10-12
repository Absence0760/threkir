// Age-grade edges the hand-computed cases do not reach: the leap-day birthday,
// a timestamp's zone suffix, a fractional age, the 2 % tolerance boundary, the
// nearest-match tie-break between the two closest standards, and the
// integrity of the embedded USATF-MLDR table every grade is read from.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import {
	AGE_GRADE_DISTANCE_TOLERANCE,
	ageOnDate,
	computeAgeGrade,
	matchStandardDistance,
} from './age_grade';
import { AGE_GRADE_AGE_MAX, AGE_GRADE_AGE_MIN, AGE_GRADE_DISTANCES } from './age_grade_tables';

test('ageOnDate — a 29 February birthday turns over on 1 March in a common year', () => {
	assert.equal(ageOnDate('2000-02-29', '2025-02-28'), 24);
	assert.equal(ageOnDate('2000-02-29', '2025-03-01'), 25);
	assert.equal(ageOnDate('2000-02-29', '2024-02-29'), 24);
	assert.equal(ageOnDate('2000-02-29', '2024-02-28'), 23);
});

test('ageOnDate — only the leading calendar date is read, whatever zone suffix follows', () => {
	// Read as instants these are a day apart in the other direction; the
	// contract is the race-day DATE, so the suffixes must change nothing.
	assert.equal(ageOnDate('1990-06-15T23:59:59-12:00', '2026-06-15T00:00:00+14:00'), 36);
	assert.equal(ageOnDate('1990-06-15', '2026-06-14T23:59:59-12:00'), 35);
	// A date before birth is not an age.
	assert.equal(ageOnDate('2026-06-15', '2026-06-14'), null);
});

test('computeAgeGrade — a fractional age is refused rather than read off a neighbouring year', () => {
	assert.equal(computeAgeGrade({ distanceM: 5000, durationSec: 1200, age: 40.5, sex: 'male' }), null);
	assert.ok(computeAgeGrade({ distanceM: 5000, durationSec: 1200, age: 40, sex: 'male' }));
});

test('matchStandardDistance — the tolerance is inclusive at exactly 2 % and refuses just past it', () => {
	const at = 10_000 * (1 + AGE_GRADE_DISTANCE_TOLERANCE);
	assert.equal(matchStandardDistance(at)?.key, '10k');
	assert.equal(matchStandardDistance(10_000 * (1 - AGE_GRADE_DISTANCE_TOLERANCE))?.key, '10k');
	assert.equal(matchStandardDistance(at + 1), null);
});

test('matchStandardDistance — 8 km and 5 miles, 0.6 % apart, go to whichever is nearer', () => {
	assert.equal(matchStandardDistance(8010)?.key, '8k');
	assert.equal(matchStandardDistance(8040)?.key, '5mi');
	assert.equal(matchStandardDistance(8023)?.key, '8k');
});

test('the embedded table: every distance and sex covers ages 5-99 with factors in (0, 1]', () => {
	const span = AGE_GRADE_AGE_MAX - AGE_GRADE_AGE_MIN + 1;
	for (const d of AGE_GRADE_DISTANCES) {
		for (const sex of ['male', 'female'] as const) {
			assert.equal(d.factors[sex].length, span, `${d.key} ${sex}`);
			assert.ok(d.openStandardSec[sex] > 0, `${d.key} ${sex} open standard`);
			for (const f of d.factors[sex]) assert.ok(f > 0 && f <= 1, `${d.key} ${sex} factor ${f}`);
			// The youngest and oldest ages both grade.
			for (const age of [AGE_GRADE_AGE_MIN, AGE_GRADE_AGE_MAX]) {
				const r = computeAgeGrade({ distanceM: d.distanceM, durationSec: 3600, age, sex });
				assert.ok(r && Number.isFinite(r.percent) && r.percent > 0, `${d.key} ${sex} age ${age}`);
			}
		}
	}
	// Standards sorted by distance, so nearest-match never has to break a tie
	// between two entries for the same distance.
	const ds = AGE_GRADE_DISTANCES.map((d) => d.distanceM);
	assert.deepEqual(ds, [...ds].sort((a, b) => a - b));
	assert.equal(new Set(ds).size, ds.length);
});

test('the embedded table: an 80-year-old needs more time than a 30-year-old for the same grade', () => {
	for (const d of AGE_GRADE_DISTANCES) {
		for (const sex of ['male', 'female'] as const) {
			const f = d.factors[sex];
			assert.ok(f[80 - AGE_GRADE_AGE_MIN] < f[30 - AGE_GRADE_AGE_MIN], `${d.key} ${sex}`);
		}
	}
});
