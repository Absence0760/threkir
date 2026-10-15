import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	FUEL_MAX_CARBS_PER_HOUR_G,
	FUEL_MAX_DURATION_S,
	FUEL_MAX_FLUID_PER_HOUR_ML,
	FUEL_MIN_DURATION_S,
	parseClockDurationS,
	parseFuelDurationS,
	parseFuelHandoff,
	parseFuelRate,
} from './fuel_params';

test('a plain rate within the ceiling is read and rounded to a whole unit', () => {
	assert.equal(parseFuelRate('70', FUEL_MAX_CARBS_PER_HOUR_G), 70);
	assert.equal(parseFuelRate('0', FUEL_MAX_CARBS_PER_HOUR_G), 0);
	assert.equal(parseFuelRate('62.6', FUEL_MAX_CARBS_PER_HOUR_G), 63);
	assert.equal(parseFuelRate(String(FUEL_MAX_FLUID_PER_HOUR_ML), FUEL_MAX_FLUID_PER_HOUR_ML), 3000);
});

test('a rate above the ceiling is dropped, not clamped to the edge', () => {
	assert.equal(parseFuelRate('201', FUEL_MAX_CARBS_PER_HOUR_G), null);
	assert.equal(parseFuelRate('9000', FUEL_MAX_FLUID_PER_HOUR_ML), null);
	assert.equal(parseFuelRate('200.6', FUEL_MAX_CARBS_PER_HOUR_G), null);
});

test('a rate that is not a plain non-negative decimal is dropped', () => {
	for (const raw of ['-10', '1e3', '0x40', ' 60', '60 ', '', 'NaN', 'Infinity', '60g', '+60', '6,5']) {
		assert.equal(parseFuelRate(raw, FUEL_MAX_FLUID_PER_HOUR_ML), null, JSON.stringify(raw));
	}
	assert.equal(parseFuelRate(null, FUEL_MAX_CARBS_PER_HOUR_G), null);
	assert.equal(parseFuelRate(undefined, FUEL_MAX_CARBS_PER_HOUR_G), null);
});

test('a duration is whole seconds inside the ten-minute to seven-day window', () => {
	assert.equal(parseFuelDurationS('9000'), 9000);
	assert.equal(parseFuelDurationS(String(FUEL_MIN_DURATION_S)), FUEL_MIN_DURATION_S);
	assert.equal(parseFuelDurationS(String(FUEL_MAX_DURATION_S)), FUEL_MAX_DURATION_S);
	assert.equal(parseFuelDurationS(String(FUEL_MIN_DURATION_S - 1)), null);
	assert.equal(parseFuelDurationS(String(FUEL_MAX_DURATION_S + 1)), null);
	for (const raw of ['90.5', '-9000', '1e4', '', 'two hours', null, undefined]) {
		assert.equal(parseFuelDurationS(raw), null, JSON.stringify(raw));
	}
});

test('a typed clock duration reads H:MM and H:MM:SS and refuses anything else', () => {
	assert.equal(parseClockDurationS('2:30'), 9000);
	assert.equal(parseClockDurationS('2:30:15'), 9015);
	assert.equal(parseClockDurationS(' 0:45 '), 2700);
	for (const raw of ['2', '2:60', '2:30:60', 'a:30', '2:-5', '1:2:3:4', '']) {
		assert.equal(parseClockDurationS(raw), null, JSON.stringify(raw));
	}
});

test('parseFuelHandoff validates each parameter on its own', () => {
	const ok = parseFuelHandoff(new URLSearchParams('duration=9000&carbs=70&fluid=600&heat=1'));
	assert.deepEqual(ok, { durationS: 9000, carbsPerHourG: 70, fluidPerHourMl: 600, heat: true });
	// One bad value does not poison the others.
	const mixed = parseFuelHandoff(new URLSearchParams('duration=9000&carbs=900&fluid=abc&heat=yes'));
	assert.deepEqual(mixed, { durationS: 9000, carbsPerHourG: null, fluidPerHourMl: null, heat: false });
	assert.deepEqual(parseFuelHandoff(new URLSearchParams('')), {
		durationS: null,
		carbsPerHourG: null,
		fluidPerHourMl: null,
		heat: false,
	});
});
