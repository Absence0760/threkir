// The official library plans (issue #1190, decisions § 2446) are built by the
// app's own generator, not written by hand: each committed
// scripts/official/catalogue/plans/<slug>.json carries the `preset` it was
// generated from, and this test fails when its weeks are no longer what
// generatePlan builds from that preset, or when a value is one the database
// would refuse. A generator change therefore reaches the official library
// only through a reviewed regeneration:
//
//   OFFICIAL_PLANS_WRITE=1 pnpm -C apps/web exec tsx --test src/lib/training/official_plan_catalogue.test.ts
//
// The projection is the library copy's (decisions § 2340): no paces, notes,
// race names or HR targets, a duration beside a distance dropped, on the
// reference week of 2001-01-01. One deliberate difference: a timed walk-run
// session keeps its time and drops its distance, because the distance is an
// estimate from the fallback pace while the timed intervals are the
// prescription. The graduation 5K, whose run is a distance, keeps its
// distance.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { Constants } from '../database.types';
import { generatePlan, minDaysPerWeek, type GoalEvent } from './training';

const DIR = resolve('../../scripts/official/catalogue/plans');
const START = '2001-01-01';

interface Preset {
	goalEvent: GoalEvent;
	weeks: number;
	daysPerWeek: number;
	beginnerWalkRun?: boolean;
}

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };

const dayOf = (iso: string) => Math.round((Date.parse(`${iso}T00:00:00Z`) - Date.parse(`${START}T00:00:00Z`)) / 86_400_000);

function redactStructure(value: Json): Json {
	if (Array.isArray(value)) return value.map(redactStructure);
	if (value === null || typeof value !== 'object') return value;
	const out: { [key: string]: Json } = {};
	for (const [key, v] of Object.entries(value)) {
		if (key === 'pace_sec_per_km') continue;
		if (key === 'duration_s' && 'distance_m' in value) continue;
		if (key === 'recovery_duration_s' && 'recovery_distance_m' in value) continue;
		out[key] = redactStructure(v);
	}
	return out;
}

function build(slug: string, name: string, preset: Preset) {
	const plan = generatePlan({
		goalEvent: preset.goalEvent,
		startDate: START,
		daysPerWeek: preset.daysPerWeek,
		weeks: preset.weeks,
		beginnerWalkRun: preset.beginnerWalkRun,
	});
	assert.ok(preset.daysPerWeek >= minDaysPerWeek(plan.weeks), `${slug}: days_per_week is below what its weeks need`);
	return {
		slug,
		name,
		preset,
		goal_event: preset.goalEvent,
		goal_distance_m: plan.goalDistanceM,
		days_per_week: preset.daysPerWeek,
		source: 'generated',
		end_day: dayOf(plan.endDate),
		weeks: plan.weeks.map((w) => ({
			week_index: w.week_index,
			phase: w.phase,
			target_volume_m: Math.round(w.target_volume_m * 100) / 100,
			workouts: w.workouts.map((wo) => {
				const timed =
					wo.kind === 'walk_run' && wo.target_duration_seconds != null && wo.structure?.repeats?.distance_m == null;
				const out: Record<string, Json> = { day: dayOf(wo.scheduled_date), kind: wo.kind };
				if (timed) out.target_duration_seconds = wo.target_duration_seconds;
				else if (wo.target_distance_m != null) out.target_distance_m = Math.round(wo.target_distance_m * 100) / 100;
				else if (wo.target_duration_seconds != null && wo.kind !== 'race') out.target_duration_seconds = wo.target_duration_seconds;
				if (wo.structure) out.structure = redactStructure(wo.structure as unknown as Json);
				return out;
			}),
		})),
	};
}

const files = readdirSync(DIR).filter((f) => f.endsWith('.json')).sort();

test('the official plan catalogue is not empty', () => {
	assert.ok(files.length > 0, `no plans under ${DIR}`);
});

for (const file of files) {
	const committed = JSON.parse(readFileSync(resolve(DIR, file), 'utf8'));

	test(`${file}: its weeks are what the generator builds from its preset`, () => {
		const built = build(committed.slug, committed.name, committed.preset);
		if (process.env.OFFICIAL_PLANS_WRITE === '1') {
			writeFileSync(resolve(DIR, file), `${JSON.stringify(built, null, '\t')}\n`);
			return;
		}
		assert.deepEqual(committed, built, `regenerate with OFFICIAL_PLANS_WRITE=1 (see this file's header)`);
	});

	test(`${file}: every value is one the database accepts`, () => {
		assert.equal(`${committed.slug}.json`, file);
		assert.ok(Constants.public.Enums.goal_event.includes(committed.goal_event));
		assert.ok(committed.name.length >= 1 && committed.name.length <= 120);
		for (const w of committed.weeks) {
			assert.ok(Constants.public.Enums.plan_phase.includes(w.phase), `phase ${w.phase}`);
			const days = new Set<number>();
			for (const wo of w.workouts) {
				assert.ok(Constants.public.Enums.workout_kind.includes(wo.kind), `kind ${wo.kind}`);
				assert.ok(wo.day >= 0 && wo.day <= committed.end_day, `day ${wo.day} inside the plan`);
				assert.ok(!days.has(wo.day), `one workout per day in week ${w.week_index}`);
				days.add(wo.day);
				assert.ok(!('target_distance_m' in wo && 'target_duration_seconds' in wo), 'never a pace by the back door');
				assert.ok(!JSON.stringify(wo.structure ?? null).includes('pace_sec_per_km'), 'no absolute pace');
			}
		}
	});
}
