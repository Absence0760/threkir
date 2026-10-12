// The HR-zone ranges are stated per rail (decisions § 1245: three spellings of
// the max-HR bound let one rail use a value the others ignored). These read the
// Dart twin's constants and legacy ladder off its source, so a bound moved on
// one side alone fails here, and pin the properties the zone chart relies on
// across the whole usable range rather than at a few spot values.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	MAX_HR_BPM_MAX,
	MAX_HR_BPM_MIN,
	RESTING_HR_BPM_MAX,
	RESTING_HR_BPM_MIN,
	TANAKA_AGE_MAX,
	TANAKA_AGE_MIN,
	isUsableMaxHrBpm,
	tanakaMaxHr,
	zoneCutoffsFromMaxHr,
} from './hr_zones';

const DART = readFileSync(
	resolve(dirname(fileURLToPath(import.meta.url)), '../../../../mobile_android/lib/hr_zones.dart'),
	'utf-8',
);

function dartInt(name: string): number {
	const m = new RegExp(`const int ${name} = (\\d+);`).exec(DART);
	assert.ok(m, `${name} is declared in hr_zones.dart`);
	return Number(m[1]);
}

test('the Dart twin declares the same max-HR, resting-HR and Tanaka age ranges', () => {
	assert.deepEqual(
		[
			dartInt('kMaxHrBpmMin'),
			dartInt('kMaxHrBpmMax'),
			dartInt('kRestingHrBpmMin'),
			dartInt('kRestingHrBpmMax'),
			dartInt('kTanakaAgeMin'),
			dartInt('kTanakaAgeMax'),
		],
		[MAX_HR_BPM_MIN, MAX_HR_BPM_MAX, RESTING_HR_BPM_MIN, RESTING_HR_BPM_MAX, TANAKA_AGE_MIN, TANAKA_AGE_MAX],
	);
});

test('the Dart legacy ladder is the web 190-bpm derivation, value for value', () => {
	const m = /cutoffs \?\? const \[([\d,\s]+)\]/.exec(DART);
	assert.ok(m, 'the Dart fallback ladder is a literal');
	assert.deepEqual(m[1].split(',').map((v) => Number(v.trim())), zoneCutoffsFromMaxHr(190));
});

test('every usable max HR gives five strictly rising cutoffs that end at the max', () => {
	for (let max = MAX_HR_BPM_MIN; max <= MAX_HR_BPM_MAX; max++) {
		const c = zoneCutoffsFromMaxHr(max);
		assert.equal(c[4], max, `max ${max}`);
		for (let i = 1; i < 5; i++) assert.ok(c[i] > c[i - 1], `max ${max}: Z${i} <= Z${i + 1}`);
	}
});

test('Tanaka never rises with age and always yields a max HR the readers will use', () => {
	let prev = Infinity;
	for (let age = TANAKA_AGE_MIN; age <= TANAKA_AGE_MAX; age++) {
		const max = tanakaMaxHr(age);
		assert.ok(max <= prev, `age ${age}`);
		assert.ok(isUsableMaxHrBpm(max), `age ${age} -> ${max} bpm`);
		prev = max;
	}
});
