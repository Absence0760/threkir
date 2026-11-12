import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Every surface that turns the runner's age into a health inference reads the
// date through `healthUseDob` (decisions § 722). The rule is mechanical and
// the drift is silent — a new `.date_of_birth` read compiles, renders, and
// looks right, and nothing about it says it just spent the ungated child-safety
// record on an Art 9 purpose. So it is pinned here rather than remembered.
//
// This list is health-USE surfaces only. `/settings/body` and
// `/settings/account` read the column directly on purpose: they edit the age
// record itself, and gating the editor is what produced § 718's deadlock (a
// runner whose consent lapsed could neither save nor clear their own date).
const HEALTH_USE_SURFACES = [
	'../../routes/dashboard/+page.svelte',
	'../../routes/nutrition/+page.svelte',
	'../../routes/nutrition/targets/+page.svelte',
	'../training/plan_calibration.ts',
];

for (const rel of HEALTH_USE_SURFACES) {
	test(`${rel} takes the age for health use through healthUseDob`, () => {
		const src = readFileSync(resolve(import.meta.dirname, rel), 'utf8');
		assert.ok(
			src.includes('healthUseDob'),
			`${rel} derives age for a health inference — it must go through healthUseDob`,
		);
		assert.ok(
			!src.includes('date_of_birth'),
			`${rel} reads date_of_birth directly; the age record carries no consent term, ` +
				'so a health use must resolve it through healthUseDob instead',
		);
	});
}

// Every surface that builds a plan for the signed-in runner takes gender, age
// and `extra_recovery` from one loader, so a new plan surface cannot skip the
// masters recovery calibration (decisions § 93) or derive the age on its own.
const PLAN_BUILDING_SURFACES = [
	'../components/PlanEditor.svelte',
	'../components/SeasonPlanner.svelte',
	'../../routes/plans/+page.svelte',
	'../../routes/plans/new/+page.svelte',
];

for (const rel of PLAN_BUILDING_SURFACES) {
	test(`${rel} calibrates its plans through loadPlanCalibration`, () => {
		const src = readFileSync(resolve(import.meta.dirname, rel), 'utf8');
		assert.ok(src.includes('loadPlanCalibration('), `${rel} builds a plan without loadPlanCalibration`);
		assert.ok(!src.includes('ageFromDob'), `${rel} derives the age itself instead of through loadPlanCalibration`);
	});
}

// The fuelling plan's weight-based fluid rate is an Art 9 use of body weight
// (decisions § 1976). Each surface that offers it must hand the rate only a
// weight that has been through healthUseWeightKg, never the raw read.
const WEIGHT_FLUID_SURFACES = [
	'../../routes/routes/[id]/roadbook/+page.svelte',
	'../../routes/nutrition/fuel/+page.svelte',
];

for (const rel of WEIGHT_FLUID_SURFACES) {
	test(`${rel} feeds the fluid rate a weight only through healthUseWeightKg`, () => {
		const src = readFileSync(resolve(import.meta.dirname, rel), 'utf8');
		assert.match(src, /consentedWeightKg = healthUseWeightKg\(profileRes\.data, weight\)/);
		assert.match(src, /weightKg: consentedWeightKg/);
		assert.ok(!/weightKg: weight\b/.test(src), `${rel} passes the raw weight to the fluid rate`);
	});
}
