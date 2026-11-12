import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildFuelPlan,
	type FuelLegInput,
	DEFAULT_FLUID_PER_HOUR_ML,
	GEL_CARBS_G,
	HEAT_FLUID_FACTOR,
	WEIGHT_FLUID_MAX_ML,
	WEIGHT_FLUID_MIN_ML,
	WEIGHT_FLUID_REFERENCE_KG,
	weightFluidPerHourMl
} from './fuel_plan';

// start → aid (1h, refill) → cutoff (0.5h, no services) → finish (0.5h).
function legs(): FuelLegInput[] {
	return [
		{ projectedElapsedS: 0, legDistM: 0, services: [] },
		{ projectedElapsedS: 3600, legDistM: 8000, services: ['water', 'food'] },
		{ projectedElapsedS: 5400, legDistM: 4000, services: [] },
		{ projectedElapsedS: 7200, legDistM: 4000, services: [] }
	];
}

const OPTS = { carbsPerHourG: 60, fluidPerHourMl: 500 };

test('carbs + fluid scale with each leg duration', () => {
	const plan = buildFuelPlan(legs(), OPTS);
	// 1h leg → 60 g / 500 ml; the two 0.5h legs → 30 g / 250 ml each.
	assert.equal(plan.legs[1].carbsG, 60);
	assert.equal(plan.legs[1].fluidMl, 500);
	assert.equal(plan.legs[2].carbsG, 30);
	assert.equal(plan.legs[2].fluidMl, 250);
	assert.equal(plan.legs[3].carbsG, 30);
});

test('zero-duration leg (start) gets zero carbs + fluid', () => {
	const plan = buildFuelPlan(legs(), OPTS);
	assert.equal(plan.legs[0].carbsG, 0);
	assert.equal(plan.legs[0].fluidMl, 0);
});

test('heat factor bumps fluid but not carbs', () => {
	const base = buildFuelPlan(legs(), OPTS);
	const hot = buildFuelPlan(legs(), { ...OPTS, heatFactor: HEAT_FLUID_FACTOR });
	assert.equal(hot.legs[1].carbsG, base.legs[1].carbsG);
	assert.equal(hot.legs[1].fluidMl, base.legs[1].fluidMl * HEAT_FLUID_FACTOR);
});

test('carryToNextAid sums legs up to and including the next refill', () => {
	const plan = buildFuelPlan(legs(), OPTS);
	// Out of the start: only the leg arriving at the aid (the next refill).
	assert.deepEqual(plan.legs[0].carryToNextAid, { carbsG: 60, fluidMl: 500, gels: 3 });
	// Out of the aid: cutoff + finish legs (no further refill) → to the end.
	assert.deepEqual(plan.legs[1].carryToNextAid, { carbsG: 60, fluidMl: 500, gels: 3 });
});

test('carry is present only on the start + refill checkpoints', () => {
	const plan = buildFuelPlan(legs(), OPTS);
	assert.ok(plan.legs[0].carryToNextAid); // start
	assert.ok(plan.legs[1].carryToNextAid); // aid (refill)
	assert.equal(plan.legs[2].carryToNextAid, undefined); // cutoff, no services
	assert.equal(plan.legs[3].carryToNextAid, undefined); // finish
});

test('gel count is ceil(carbs / gelCarbsG)', () => {
	// 70 g/hr over the 1h leg out of the start → 70 g → ceil(70/25) = 3 gels.
	const plan = buildFuelPlan(legs(), { carbsPerHourG: 70, fluidPerHourMl: 500 });
	assert.equal(plan.legs[0].carryToNextAid?.carbsG, 70);
	assert.equal(plan.legs[0].carryToNextAid?.gels, Math.ceil(70 / GEL_CARBS_G));
});

test('totals equal the sum of the legs', () => {
	const plan = buildFuelPlan(legs(), OPTS);
	const sumCarbs = plan.legs.reduce((a, l) => a + l.carbsG, 0);
	const sumFluid = plan.legs.reduce((a, l) => a + l.fluidMl, 0);
	assert.equal(plan.totalCarbsG, sumCarbs);
	assert.equal(plan.totalFluidMl, sumFluid);
	assert.equal(plan.totalCarbsG, 120);
	assert.equal(plan.totalFluidMl, 1000);
});

test('kcal is estimated only when a bodyweight is supplied', () => {
	const without = buildFuelPlan(legs(), OPTS);
	assert.equal(without.legs[1].kcal, 0);
	const withWeight = buildFuelPlan(legs(), { ...OPTS, weightKg: 70 });
	// 1.036 kcal/kg/km × 70 kg × 8 km = 580.16
	assert.ok(Math.abs(withWeight.legs[1].kcal - 580.16) < 0.01);
});

test('non-positive intake rates clamp to zero', () => {
	const plan = buildFuelPlan(legs(), { carbsPerHourG: -10, fluidPerHourMl: -5 });
	assert.equal(plan.totalCarbsG, 0);
	assert.equal(plan.totalFluidMl, 0);
});

test('weight-based fluid is the default rate at the reference weight and scales with mass', () => {
	assert.equal(weightFluidPerHourMl(WEIGHT_FLUID_REFERENCE_KG), DEFAULT_FLUID_PER_HOUR_ML);
	// 500 × 90 / 70 = 642.9 → nearest 25 ml.
	assert.equal(weightFluidPerHourMl(90), 650);
	// 500 × 63 / 70 = 450.
	assert.equal(weightFluidPerHourMl(63), 450);
});

test('weight-based fluid is held to the 400-800 ml/h band', () => {
	assert.equal(weightFluidPerHourMl(50), WEIGHT_FLUID_MIN_ML);
	assert.equal(weightFluidPerHourMl(130), WEIGHT_FLUID_MAX_ML);
	assert.equal(weightFluidPerHourMl(20), WEIGHT_FLUID_MIN_ML);
	assert.equal(weightFluidPerHourMl(250), WEIGHT_FLUID_MAX_ML);
});

test('no usable weight gives no weight-based rate, so the flat rate stands', () => {
	for (const w of [null, undefined, 0, -70, 19.9, 250.1, NaN, Infinity]) {
		assert.equal(weightFluidPerHourMl(w), null, String(w));
	}
});
