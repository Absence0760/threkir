// Unit tests for the training engine. Run with `node --test` — no external
// test runner needed. The engine is pure TS with no browser or SvelteKit
// deps so Node 20+ can execute it directly via tsx / ts-node, or via the
// compiled output if we add vitest later.
//
// Invocation example (from apps/web):
//   npx tsx --test src/lib/training/training.test.ts
//
// Or if you prefer raw Node once this is transpiled:
//   node --test src/lib/training.test.js
//
// Adding a test runner is a tooling question the user hasn't decided — these
// are written to the stdlib `node:test` API so any runner will pick them up.

import { test } from 'node:test';
import assert from 'node:assert/strict';

// Relative import without extension so SvelteKit's svelte-check (which runs
// under `noUncheckedSideEffectImports` / no-extension TS config) is happy.
// `tsx --test` resolves this to training.ts at runtime.
import {
	vdotFromRace,
	riegelPredict,
	predictionConfidence,
	pacesFromGoalPace,
	resolveTrainingPaces,
	resolveTrainingPacesWithMeta,
	phaseFor,
	generatePlan,
	peakVolumeKm,
	mileageFraction,
	isMastersAge,
	defaultPlanWeeks,
	walkRunDefaultWeeks,
	GOAL_DISTANCES_M,
	formatISO,
	fmtHms,
	isWorkoutCompleted,
	isWorkoutSkipped,
	longRunDistance,
	isUltraDistance,
	parseISO,
	ultraLongRunCapSec,
	ultraMarathonEquivalentSec,
	ultraTaperWeeks,
	ULTRA_PRESETS,
	ULTRA_MAX_WEEKLY_RAMP,
	type GeneratedPlan,
	type WorkoutStructure
} from './training';

// ─────────────────────── walk-run kind + structure (#22) ───────────────────────

test('generatePlan: a no-anchor 5k plan ramps gentler than an anchored one (#23)', () => {
	const base = {
		goalEvent: 'distance_5k' as const,
		startDate: '2026-06-01',
		daysPerWeek: 4
	};
	const anchored = generatePlan({ ...base, recent5kSec: 22 * 60 });
	const noAnchor = generatePlan(base);
	const weekVol = (p: typeof anchored, i: number) =>
		p.weeks[i].workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
	const activeDays = (p: typeof anchored, i: number) =>
		p.weeks[i].workouts.filter((w) => w.kind !== 'rest').length;
	// Week 1 must honour daysPerWeek — the old limitToDays missed 'recovery'
	// fillers, so a 4-day plan ran 6 days and stacked floored recoveries.
	assert.equal(activeDays(noAnchor, 0), 4);
	// No-anchor peak scaling makes its week-1 lower than the anchored plan's,
	// and beginner-sane for a no-info 5k (< 15 km vs the old ~20 km).
	assert.ok(weekVol(noAnchor, 0) < weekVol(anchored, 0));
	assert.ok(weekVol(noAnchor, 0) < 15_000, `week1=${weekVol(noAnchor, 0)}`);
});

test('generatePlan(beginnerWalkRun): every session is a walk_run workout', () => {
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		beginnerWalkRun: true
	});
	// Default 9-week C25K progression.
	assert.equal(plan.weeks.length, 9);
	const allWorkouts = plan.weeks.flatMap((w) => w.workouts);
	const sessions = allWorkouts.filter((w) => w.kind !== 'rest');
	assert.ok(sessions.length > 0);
	assert.ok(sessions.every((w) => w.kind === 'walk_run'));
	// 3 run days per week.
	assert.equal(sessions.length, 9 * 3);
	// Week 1 session: timed run/walk repeats with a 'walk' recovery.
	const wk1 = plan.weeks[0].workouts.find((w) => w.kind === 'walk_run')!;
	assert.equal(wk1.structure?.repeats?.recovery_pace, 'walk');
	assert.equal(wk1.structure?.repeats?.duration_s, 60);
	assert.equal(wk1.structure?.repeats?.recovery_duration_s, 90);
	assert.equal(wk1.structure?.repeats?.count, 8);
	// Graduation week: a single continuous run, no recovery interval.
	const wk9 = plan.weeks[8].workouts.find((w) => w.kind === 'walk_run')!;
	assert.equal(wk9.structure?.repeats?.count, 1);
	assert.equal(wk9.structure?.repeats?.recovery_duration_s, undefined);
	// #273: the final week is a graduation, not a race — a beginner walk-run
	// plan has no goal race, so labelling it 'race' ("Race week") misleads.
	assert.equal(plan.weeks[8].phase, 'graduation');
	assert.equal(plan.weeks[0].phase, 'build');
});

// Persona round-5 runner-new: a default 5k beginner plan arrives with
// weeks=8 (defaultPlanWeeks('distance_5k')) against a 9-stage progression.
// Without the engine floor, week index 8 — the single continuous-run
// graduation week — was silently dropped.
test('walkRunDefaultWeeks: matches the full progression length', () => {
	// 9-stage C25K table → 9-week default for a beginner plan.
	assert.equal(walkRunDefaultWeeks(), 9);
});

test('generatePlan(beginnerWalkRun, weeks=8): keeps the graduation week (off-by-one fix)', () => {
	// Simulate the old PlanEditor path that forced weeks=defaultPlanWeeks('distance_5k')=8.
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		weeks: 8,
		beginnerWalkRun: true
	});
	// Floored up to the full progression so graduation isn't truncated.
	assert.equal(plan.weeks.length, 9);
	const wkLast = plan.weeks[plan.weeks.length - 1].workouts.find((w) => w.kind === 'walk_run')!;
	assert.equal(wkLast.structure?.repeats?.count, 1);
	assert.equal(wkLast.structure?.repeats?.recovery_duration_s, undefined);
	assert.match(wkLast.notes ?? '', /Graduation week/);
});

// Persona round-5 runner-comeback: when the engine can't derive paces from a
// recent race or a goal time it falls back to a conservative 10:00/km. The
// plan must flag that so the wizard can disclose it rather than presenting a
// placeholder as a real prescription.
test('generatePlan: pacesAreFallback is true with no anchor, false with an anchor', () => {
	const noAnchor = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-06-01',
		daysPerWeek: 3
	});
	assert.equal(noAnchor.pacesAreFallback, true);

	const withGoal = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		goalTimeSec: 45 * 60
	});
	assert.equal(withGoal.pacesAreFallback, false);

	const withRecent = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-06-01',
		daysPerWeek: 3,
		recent5kSec: 24 * 60
	});
	assert.equal(withRecent.pacesAreFallback, false);
	// The fallback paces are still usable — the plan generates either way.
	assert.ok(noAnchor.paces.easy > 0 && noAnchor.weeks.length > 0);
});

test('WorkoutStructure: a time-based walk-run rep block is well-typed', () => {
	// Compile-time check that duration_s / recovery_duration_s / recovery_pace
	// 'walk' are accepted; the assertion just confirms the shape round-trips.
	const s: WorkoutStructure = {
		repeats: {
			count: 8,
			duration_s: 60,
			pace_sec_per_km: 420,
			recovery_duration_s: 90,
			recovery_pace: 'walk'
		}
	};
	assert.equal(s.repeats?.recovery_pace, 'walk');
	assert.equal(s.repeats?.duration_s, 60);
});

// ─────────────────────── VDOT ───────────────────────

test('vdotFromRace: a 20-minute 5k is close to VDOT 50', () => {
	const v = vdotFromRace(5000, 20 * 60);
	assert.ok(Math.abs(v - 49.8) < 1.5, `expected ~50, got ${v}`);
});

test('vdotFromRace: a 3:00 marathon is close to VDOT 54', () => {
	const v = vdotFromRace(42_195, 3 * 3600);
	assert.ok(Math.abs(v - 54.3) < 2, `expected ~54, got ${v}`);
});

test('vdotFromRace: slower runners get lower VDOT', () => {
	const fast = vdotFromRace(5000, 20 * 60);
	const slow = vdotFromRace(5000, 30 * 60);
	assert.ok(fast > slow, 'faster 5k must produce higher VDOT');
});

// ─────────────────────── Riegel ───────────────────────

test('riegelPredict: 20-min 5k projects to a ~41-42 min 10k', () => {
	const t10k = riegelPredict(5000, 20 * 60, 10_000);
	assert.ok(Math.abs(t10k - 41.7 * 60) < 60, `expected ~41:40, got ${t10k / 60} min`);
});

test('riegelPredict: identity for same distance', () => {
	assert.equal(riegelPredict(5000, 1234, 5000), 1234);
});

test('riegelPredict: longer target means longer predicted time', () => {
	const short = riegelPredict(5000, 1200, 5000);
	const long = riegelPredict(5000, 1200, 10_000);
	assert.ok(long > short);
});

// ─────────────────────── Pace multipliers ───────────────────────

test('pacesFromGoalPace: zones are ordered slow → fast', () => {
	const p = pacesFromGoalPace(240); // 4:00/km goal
	assert.ok(p.easy > p.marathon, 'easy slower than marathon');
	assert.ok(p.marathon > p.tempo, 'marathon slower than tempo');
	assert.ok(p.tempo > p.interval, 'tempo slower than interval');
	assert.ok(p.interval > p.repetition, 'interval slower than repetition');
});

test('pacesFromGoalPace: 4:00/km goal yields easy in 4:30-5:15 band', () => {
	const p = pacesFromGoalPace(240);
	assert.ok(p.easy >= 270 && p.easy <= 315, `easy out of band: ${p.easy}`);
});

// Persona-hunt Round 3 finding Woman #3 — gender calibration.
test('pacesFromGoalPace: omitting gender returns the existing (male-curve) values', () => {
	// Back-compat pin — every caller that doesn't pass gender must
	// see the unmodified output. A regression that hard-coded the
	// calibration would silently slow every existing user's prescribed
	// paces by 3%.
	const noGender = pacesFromGoalPace(240);
	const explicitNull = pacesFromGoalPace(240, null);
	const explicitMale = pacesFromGoalPace(240, 'male');
	assert.deepStrictEqual(noGender, explicitNull);
	assert.deepStrictEqual(noGender, explicitMale);
});

test('pacesFromGoalPace: female calibration shifts every band ~3% slower', () => {
	const male = pacesFromGoalPace(240);
	const female = pacesFromGoalPace(240, 'female');
	// Each band must be slower (higher seconds-per-km) for female.
	assert.ok(female.easy > male.easy, `female easy not slower: ${female.easy} vs ${male.easy}`);
	assert.ok(female.marathon > male.marathon);
	assert.ok(female.tempo > male.tempo);
	assert.ok(female.interval > male.interval);
	assert.ok(female.repetition > male.repetition);
	// And the shift must sit in the 2-5% range we documented — looser
	// pin to absorb integer rounding at the tighter bands. Use the
	// `easy` band (widest absolute, most stable under rounding).
	const ratio = female.easy / male.easy;
	assert.ok(
		ratio > 1.02 && ratio < 1.05,
		`female easy / male easy ratio out of 2-5% band: ${ratio}`
	);
});

test('pacesFromGoalPace: prefer_not_to_say falls back to the unmodified curve', () => {
	// We do not have a validated calibration without a stated sex;
	// applying a wrong adjustment is worse than no adjustment. Pin
	// the conservative default so a future contributor doesn't
	// silently fork this branch.
	const male = pacesFromGoalPace(240);
	const pnts = pacesFromGoalPace(240, 'prefer_not_to_say');
	assert.deepStrictEqual(pnts, male);
});

test('resolveTrainingPaces: a recent 5k beats a goal time as the anchor', () => {
	// Runner wants a sub-20 5k but their recent 5k is 25:00. Plan paces
	// should reflect current fitness, not the goal.
	const withRecent = resolveTrainingPaces({
		goalDistanceM: 5000,
		goalTimeSec: 19 * 60 + 59,
		recent5kSec: 25 * 60
	});
	const withGoalOnly = resolveTrainingPaces({
		goalDistanceM: 5000,
		goalTimeSec: 19 * 60 + 59
	});
	assert.ok(
		withRecent.easy > withGoalOnly.easy,
		'recent-5k anchor should yield slower (safer) easy pace'
	);
});

test('resolveTrainingPaces: fall-back produces a valid pace set', () => {
	const p = resolveTrainingPaces({ goalDistanceM: 10_000 });
	assert.ok(p.easy > 0 && p.interval > 0);
});

test('resolveTrainingPaces: a degenerate goal distance falls back instead of a non-finite pace (twin parity)', () => {
	// A 0 m goal distance divided every anchor to Infinity, which each band
	// rounded to and `fmtPace` printed as "Infinity:NaN/km". Same table as
	// training_test.dart.
	const fallback = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000 });
	const cases: Array<{ goalDistanceM: number; goalTimeSec?: number; recent5kSec?: number }> = [
		{ goalDistanceM: 0, goalTimeSec: 1200 },
		{ goalDistanceM: 0, recent5kSec: 1200 },
		{ goalDistanceM: -5000, goalTimeSec: 1200 },
		{ goalDistanceM: Number.NaN, goalTimeSec: 1200 },
	];
	for (const input of cases) {
		const got = resolveTrainingPacesWithMeta(input);
		const label = JSON.stringify(input);
		assert.equal(got.isFallback, true, label);
		assert.equal(got.goalPaceSecPerKm, 600, label);
		assert.deepEqual(got.paces, fallback.paces, label);
	}
});

test('resolveTrainingPaces: a real goal time or recent 5K is an anchor, not the fallback (twin parity)', () => {
	// The degenerate-pace guard sits after the anchor branches; a usable
	// anchor must still come through it unchanged. Same cases as
	// training_test.dart and training_paces.rs.
	const goal = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000, goalTimeSec: 2400 });
	assert.equal(goal.isFallback, false);
	assert.equal(goal.goalPaceSecPerKm, 240);
	assert.deepEqual(goal.paces, pacesFromGoalPace(240));

	const recent = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000, recent5kSec: 1200 });
	assert.equal(recent.isFallback, false);
	assert.ok(Math.abs(recent.goalPaceSecPerKm - riegelPredict(5000, 1200, 10_000) / 10) < 1e-9);
	assert.deepEqual(recent.paces, pacesFromGoalPace(recent.goalPaceSecPerKm));
});

test('resolveTrainingPaces: a zero recent5kSec/goalTimeSec is treated as no anchor (twin parity)', () => {
	// A 0 anchor is "no usable time", not a real one. Web's JS truthiness already
	// fell through to the conservative fallback; the Dart twin used `!= null` and
	// ran Riegel on 0 → every pace 0 + fallback flag suppressed. Pin the
	// canonical contract on both: 0 → fallback pace set, isFallback true.
	const zeroRecent = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000, recent5kSec: 0 });
	assert.equal(zeroRecent.isFallback, true);
	assert.ok(zeroRecent.paces.easy > 0 && zeroRecent.paces.interval > 0);

	const zeroGoal = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000, goalTimeSec: 0 });
	assert.equal(zeroGoal.isFallback, true);
	assert.ok(zeroGoal.paces.easy > 0);

	// Same numbers as the no-arg fallback.
	const fallback = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000 });
	assert.equal(zeroRecent.paces.easy, fallback.paces.easy);
});

test('resolveTrainingPaces: marathon-only goal time yields valid pace set', () => {
	const p = resolveTrainingPaces({ goalDistanceM: 42195, goalTimeSec: 4 * 3600 });
	// 4h marathon = 341 s/km goal pace. Easy should be ~416, tempo ~330.
	assert.ok(p.easy > 350 && p.easy < 500, `easy out of range: ${p.easy}`);
	assert.ok(p.tempo < p.marathon, 'tempo must be faster than marathon');
});

// ─────────────────────── Phases ───────────────────────

test('phaseFor: a 16-week plan is ~30/40/20/10 base/build/peak/taper', () => {
	const counts = { base: 0, build: 0, peak: 0, taper: 0, race: 0, graduation: 0 };
	for (let i = 0; i < 16; i++) counts[phaseFor(i, 16)]++;
	assert.equal(counts.race, 1, 'race week is last');
	assert.ok(counts.base >= 4 && counts.base <= 5);
	assert.ok(counts.build >= 6 && counts.build <= 7);
	assert.ok(counts.peak >= 2 && counts.peak <= 4);
	assert.ok(counts.taper >= 1 && counts.taper <= 2);
});

test('phaseFor: final week is always race', () => {
	for (const total of [4, 8, 12, 16, 20]) {
		assert.equal(phaseFor(total - 1, total), 'race');
	}
});

test('phaseFor: every total from the editor floor up seats a taper and sums exact', () => {
	const order = ['base', 'build', 'peak', 'taper', 'race'];
	// 4 is the plan editor's `min` on the free-text total-weeks override.
	for (let total = 4; total <= 30; total++) {
		const seq = Array.from({ length: total }, (_, i) => phaseFor(i, total));
		assert.equal(seq.length, total, `total ${total}: every week must land in a phase`);
		for (let i = 1; i < seq.length; i++) {
			assert.ok(
				order.indexOf(seq[i]) >= order.indexOf(seq[i - 1]),
				`total ${total}: phases must not run backwards (${seq.join(',')})`
			);
		}
		assert.equal(seq.filter((p) => p === 'race').length, 1, `total ${total}: one race week`);
		assert.ok(seq.includes('taper'), `total ${total}: taper starved (${seq.join(',')})`);
		// Four phases need four non-race weeks; below that one must go empty, and
		// the taper asserted above is never the one dropped.
		if (total >= 5) {
			for (const phase of ['base', 'build', 'peak'] as const) {
				assert.ok(seq.includes(phase), `total ${total}: ${phase} starved (${seq.join(',')})`);
			}
		}
	}
});

test('phaseFor: a 10-week plan tapers instead of peaking into race week', () => {
	// 10 and 5 floored to exactly the non-race block (3+4+2 and 1+2+1), so the
	// taper got nothing and the 100 %-volume peak week sat against race day.
	assert.equal(phaseFor(8, 10), 'taper');
	assert.equal(phaseFor(3, 5), 'taper');
});

// ─────────────────────── Plan generation ───────────────────────

test('generatePlan: produces the requested number of weeks', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 4,
		goalTimeSec: 90 * 60
	});
	assert.equal(plan.weeks.length, defaultPlanWeeks('distance_half'));
});

test('generatePlan: a 4-day plan has exactly 3 runs + 1 long per week in base', () => {
	const plan = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-05-03',
		daysPerWeek: 4,
		goalTimeSec: 45 * 60
	});
	const w0 = plan.weeks[0];
	const active = w0.workouts.filter((w) => w.kind !== 'rest');
	assert.equal(active.length, 4);
	assert.ok(active.some((w) => w.kind === 'long'));
});

// Persona-hunt finding Intermediate #4: 3-day plans used to be all
// long-run + easy with no quality work in any phase — basically just
// a mileage log, not a training plan. Drop the qualityA gate from
// >=4 to >=3 so 3-day plans get one tempo/interval per week (the
// phase picks which).
test('generatePlan: a 3-day plan in base phase still includes a tempo workout', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 3,
		goalTimeSec: 105 * 60
	});
	const baseWeek = plan.weeks.find((w) => w.phase === 'base');
	assert.ok(baseWeek, 'plan should have a base-phase week');
	const kinds = new Set(baseWeek!.workouts.map((w) => w.kind));
	const active = baseWeek!.workouts.filter((w) => w.kind !== 'rest');
	assert.equal(active.length, 3, '3-day plan has 3 active days');
	assert.ok(kinds.has('long'), '3-day plan must include the long run');
	assert.ok(
		kinds.has('tempo') || kinds.has('interval'),
		'3-day plan in base phase must include at least one tempo/interval — ' +
			'pre-fix it was all easy + long, not a training plan'
	);
});

test('generatePlan: a 3-day plan in build phase includes intervals', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 3,
		goalTimeSec: 4 * 3600
	});
	const buildWeek = plan.weeks.find((w) => w.phase === 'build');
	assert.ok(buildWeek, 'plan should have a build-phase week');
	const kinds = new Set(buildWeek!.workouts.map((w) => w.kind));
	assert.ok(
		kinds.has('interval'),
		'3-day build phase must include the interval workout'
	);
});

test('generatePlan: taper weeks have lower volume than peak', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		goalTimeSec: 4 * 3600
	});
	const peakWeek = plan.weeks.find((w) => w.phase === 'peak')!;
	const taperWeek = plan.weeks.find((w) => w.phase === 'taper')!;
	assert.ok(
		peakWeek.target_volume_m > taperWeek.target_volume_m,
		`taper (${taperWeek.target_volume_m}) should be below peak (${peakWeek.target_volume_m})`
	);
});

// #326: the race week reserved a quality-day slot from daysPerWeek that the
// race phase never fills, and it costed the Sunday slot as a nominal long run
// while actually emitting the full race distance — so the week ballooned back
// up toward peak volume (a half race week was ~98% of the peak week). The race
// itself is the week's volume; any shakeout must stay inside a light budget.
test('generatePlan: race week volume stays a light shakeout above the race (#326)', () => {
	for (const cfg of [
		{ goalEvent: 'distance_half' as const, daysPerWeek: 5, goalTimeSec: 90 * 60 },
		{ goalEvent: 'distance_full' as const, daysPerWeek: 7, goalTimeSec: 4 * 3600 }
	]) {
		const plan = generatePlan({ ...cfg, startDate: '2026-08-01' });
		const raceWeek = plan.weeks[plan.weeks.length - 1];
		assert.equal(raceWeek.phase, 'race');
		assert.ok(
			raceWeek.target_volume_m <= plan.goalDistanceM * 1.15,
			`race week ${raceWeek.target_volume_m}m must be <= goal*1.15 ` +
				`(${plan.goalDistanceM * 1.15}m) for ${cfg.goalEvent} ${cfg.daysPerWeek}d`
		);
		assert.ok(
			raceWeek.target_volume_m >= plan.goalDistanceM,
			'race week volume still includes the full race distance'
		);
	}
});

// #326: base/taper weeks over-reserved the (empty) qualityB slot, dividing the
// easy budget over too few days and overshooting the week's own weeklyKm ramp
// target. Each training-load week's emitted volume must stay within its budget.
test('generatePlan: base/taper 5-day weeks do not exceed their weeklyKm target (#326)', () => {
	const cfg = { goalEvent: 'distance_half' as const, daysPerWeek: 5, goalTimeSec: 95 * 60 };
	const plan = generatePlan({ ...cfg, startDate: '2026-08-01' });
	const total = plan.weeks.length;
	const peakKm = peakVolumeKm(plan.goalDistanceM, cfg.daysPerWeek, true);
	// Each easy day's distance is rounded to a whole km, so the week can round up
	// by at most ~0.5 km per easy day above the exact budget. Allow that headroom
	// (well under the 25-70% overshoot the bug produced).
	const roundingHeadroomM = cfg.daysPerWeek * 500;
	for (const week of plan.weeks) {
		if (week.phase !== 'base' && week.phase !== 'taper') continue;
		const weeklyKm = Math.round(peakKm * mileageFraction(week.week_index, total, week.phase));
		assert.ok(
			week.target_volume_m <= weeklyKm * 1000 + roundingHeadroomM,
			`${week.phase} week ${week.week_index} volume ${week.target_volume_m}m ` +
				`exceeds its ${weeklyKm * 1000}m weeklyKm budget`
		);
	}
});

test('generatePlan: race week ends with a race-kind workout', () => {
	const plan = generatePlan({
		goalEvent: 'distance_5k',
		startDate: '2026-05-03',
		daysPerWeek: 4,
		goalTimeSec: 25 * 60
	});
	const raceWeek = plan.weeks[plan.weeks.length - 1];
	assert.equal(raceWeek.phase, 'race');
	assert.ok(raceWeek.workouts.some((w) => w.kind === 'race'));
});

test('generatePlan: builds interval structure for build-phase intervals', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 5,
		goalTimeSec: 95 * 60
	});
	const interval = plan.weeks
		.flatMap((w) => w.workouts)
		.find((w) => w.kind === 'interval');
	assert.ok(interval, 'expected at least one interval session');
	assert.ok(interval!.structure, 'interval must carry a structure');
	assert.ok(interval!.structure!.repeats, 'interval must have repeats');
	assert.ok((interval!.structure!.repeats!.count ?? 0) > 0);
});

test('generatePlan: no recent5k + no goal still produces a plan', () => {
	const plan = generatePlan({
		goalEvent: 'distance_10k',
		startDate: '2026-05-03',
		daysPerWeek: 3
	});
	assert.ok(plan.weeks.length > 0);
	assert.ok(plan.paces.easy > 0);
	assert.equal(plan.vdot, null);
});

test('generatePlan: weekly volume steps back every 4th week', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		recent5kSec: 22 * 60
	});
	// In base phase the 4th week (index 3) should be lower than the 3rd.
	// Guard against the edge where index 3 is already in taper for short plans.
	if (plan.weeks.length >= 5 && plan.weeks[3].phase !== 'taper') {
		assert.ok(
			plan.weeks[3].target_volume_m <= plan.weeks[2].target_volume_m,
			'step-back week should not exceed the week before it'
		);
	}
});

test('generatePlan: stated weekly volume equals the sum of emitted workout distances', () => {
	// The headline `target_volume_m` must match what the week actually
	// prescribes. Pre-fix it was `weeklyKm * 1000`, which overshot the
	// rounded/floored per-day distances by ~25-70% on small-volume plans.
	for (const goalEvent of ['distance_5k', 'distance_half'] as const) {
		for (const daysPerWeek of [3, 4, 5]) {
			const plan = generatePlan({
				goalEvent,
				startDate: '2026-05-03',
				daysPerWeek,
				goalTimeSec: goalEvent === 'distance_5k' ? 25 * 60 : 105 * 60
			});
			for (const week of plan.weeks) {
				const emitted = week.workouts.reduce(
					(s, w) => s + (w.target_distance_m ?? 0),
					0
				);
				assert.equal(
					week.target_volume_m,
					emitted,
					`${goalEvent} ${daysPerWeek}d week ${week.week_index}: stated ` +
						`${week.target_volume_m} should equal emitted ${emitted}`
				);
			}
		}
	}
});

test('generatePlan: a 7-day plan runs all 7 days (no hardcoded Monday rest)', () => {
	// Both wizards offer 3–7 days/week. Monday was hardwired as a rest day, so
	// a runner who picked 7 silently got a 6-day plan — the requested 7th day
	// vanished. A 7-day plan must have zero rest days; 6 days keeps exactly one.
	const seven = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 7,
		recent5kSec: 22 * 60,
		weeks: 12
	});
	// The race week is a deliberate exception: the race itself stands in for the
	// long run and dwarfs the light race-week budget, so shakeout days collapse
	// to what the remaining budget supports (#326) rather than padding the week
	// back up with filler runs. The "no hardcoded Monday rest" guarantee still
	// applies to every training-load week.
	for (const week of seven.weeks) {
		if (week.phase === 'race') continue;
		const active = week.workouts.filter((w) => w.kind !== 'rest').length;
		const rest = week.workouts.filter((w) => w.kind === 'rest').length;
		assert.equal(active, 7, `7-day week ${week.week_index} has ${active} active days`);
		assert.equal(rest, 0, `7-day week ${week.week_index} has ${rest} rest days`);
	}
	const six = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-05-03',
		daysPerWeek: 6,
		recent5kSec: 22 * 60,
		weeks: 12
	});
	for (const week of six.weeks) {
		if (week.phase === 'race') continue;
		const active = week.workouts.filter((w) => w.kind !== 'rest').length;
		assert.equal(active, 6, `6-day week ${week.week_index} has ${active} active days`);
	}
});

test('GOAL_DISTANCES_M: half marathon is within 1m of 21.0975km', () => {
	assert.equal(GOAL_DISTANCES_M.distance_half, 21097.5);
});

test('generatePlan: every generated workout has a kind (regression for the null-kind race-week bug)', () => {
	// Exercise every phase boundary the generator can hit — varying weeks
	// and days/week — so a race week or sparse-allocation phase can't
	// silently emit a kindless workout the way the old quality-slot code did.
	for (const [goal, weeks] of [
		['distance_5k', 8],
		['distance_10k', 12],
		['distance_half', 16],
		['distance_full', 32]
	] as const) {
		for (const dpw of [3, 4, 5, 6, 7]) {
			const plan = generatePlan({
				goalEvent: goal,
				startDate: '2026-03-30',
				daysPerWeek: dpw,
				goalTimeSec: 3 * 3600,
				recent5kSec: 22 * 60,
				weeks
			});
			for (const w of plan.weeks) {
				for (const wo of w.workouts) {
					assert.ok(
						wo.kind,
						`null kind in ${goal} ${weeks}w × ${dpw}/wk at week ${w.week_index} ${wo.scheduled_date}`
					);
					assert.ok(wo.scheduled_date, 'scheduled_date missing');
				}
			}
		}
	}
});

// Regression: period-summary prev/next was using `toISOString().slice(0,10)`,
// which rolls the date back a day in any positive-offset zone before
// midnight local. `formatISO` builds yyyy-mm-dd from local components so the
// week-shift always lands on the same wall-clock day.
test('formatISO: returns local-tz components, not UTC', () => {
	// 2025-12-15 at 00:30 local — in any UTC+1..+12 zone, toISOString() would
	// return 2025-12-14. formatISO must stay on the 15th.
	const d = new Date(2025, 11, 15, 0, 30, 0, 0);
	assert.equal(formatISO(d), '2025-12-15');
});

test('formatISO: zero-pads single-digit month and day', () => {
	const d = new Date(2026, 0, 5, 12, 0, 0, 0);
	assert.equal(formatISO(d), '2026-01-05');
});

test('formatISO: shiftPeriod by 7 days lands on the same weekday', () => {
	const start = new Date(2025, 11, 15, 0, 0, 0, 0); // Mon
	const next = new Date(start);
	next.setDate(next.getDate() + 7);
	assert.equal(formatISO(next), '2025-12-22');
});

// ─────────────────────── isWorkoutCompleted ───────────────────────

test("isWorkoutCompleted: false when neither flag set", () => {
	assert.equal(isWorkoutCompleted({}), false);
	assert.equal(
		isWorkoutCompleted({ manually_completed: false, completed_run_id: null }),
		false
	);
});

test("isWorkoutCompleted: true when run is linked", () => {
	assert.equal(isWorkoutCompleted({ completed_run_id: "run-123" }), true);
});

test("isWorkoutCompleted: true when manually marked", () => {
	assert.equal(isWorkoutCompleted({ manually_completed: true }), true);
});

test("isWorkoutCompleted: true when both set", () => {
	assert.equal(
		isWorkoutCompleted({ manually_completed: true, completed_run_id: "run-1" }),
		true
	);
});

// ─────────────────────── isWorkoutSkipped ───────────────────────

test("isWorkoutSkipped: false when skipped_at absent or null", () => {
	assert.equal(isWorkoutSkipped({}), false);
	assert.equal(isWorkoutSkipped({ skipped_at: null }), false);
});

test("isWorkoutSkipped: true when skipped_at stamped", () => {
	assert.equal(isWorkoutSkipped({ skipped_at: "2026-06-13T10:00:00.000Z" }), true);
});

test("isWorkoutSkipped is independent of completion flags", () => {
	// The write layer keeps skip and done mutually exclusive, but the read
	// helper only inspects skipped_at — a row that somehow carried both
	// still reads as skipped here (defensive: the predicate is single-axis).
	// Bind to a variable so the extra completed_run_id field is allowed past
	// the object-literal excess-property check while the predicate stays
	// typed to its single-axis { skipped_at } contract.
	const bothFlags = { skipped_at: "2026-06-13T10:00:00.000Z", completed_run_id: "run-1" };
	assert.equal(isWorkoutSkipped(bothFlags), true);
});

// ─────────────────────── masters age-band calibration (#30) ───────────────────────

test('isMastersAge: boundary is 50 inclusive; null/undefined are not masters', () => {
	assert.equal(isMastersAge(49), false);
	assert.equal(isMastersAge(50), true);
	assert.equal(isMastersAge(72), true);
	assert.equal(isMastersAge(null), false);
	assert.equal(isMastersAge(undefined), false);
});

// Offset (in days) of a workout from its week's first slot (the long
// run / race on dow 0). workouts are pushed in dow order, so [0] is the
// week start.
function dayOffsetInWeek(week: { workouts: { scheduled_date: string; kind: string }[] }, kinds: string[]): number | null {
	const start = Date.parse(week.workouts[0].scheduled_date + 'T00:00:00Z');
	const q = week.workouts.find((w) => kinds.includes(w.kind));
	if (!q) return null;
	const at = Date.parse(q.scheduled_date + 'T00:00:00Z');
	return Math.round((at - start) / 86_400_000);
}

const QUALITY_KINDS = ['tempo', 'interval', 'marathon_pace'];

test('generatePlan: masters push the first quality day to 72h after the long run (Wed vs Tue)', () => {
	const base = {
		goalEvent: 'distance_half' as const,
		startDate: '2026-06-07', // a Sunday — long run lands on dow 0
		daysPerWeek: 5,
		goalTimeSec: 100 * 60
	};
	const standard = generatePlan(base);
	const masters = generatePlan({ ...base, age: 58 });

	// Find a build-phase week that actually allocated quality in both plans.
	const stdWeek = standard.weeks.find((w) => dayOffsetInWeek(w, QUALITY_KINDS) != null)!;
	const mstWeek = masters.weeks.find((w) => dayOffsetInWeek(w, QUALITY_KINDS) != null)!;
	assert.equal(dayOffsetInWeek(stdWeek, QUALITY_KINDS), 2, 'standard plan: first quality on Tue (48h)');
	assert.equal(dayOffsetInWeek(mstWeek, QUALITY_KINDS), 3, 'masters plan: first quality on Wed (72h)');
});

test('generatePlan: masters never schedule a quality day on the slot right after the long run', () => {
	const masters = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		recent5kSec: 24 * 60,
		age: 55
	});
	for (const week of masters.weeks) {
		const off = dayOffsetInWeek(week, QUALITY_KINDS);
		if (off != null) {
			assert.ok(off >= 3, `masters quality must be >=72h after long run, got ${off}d (week ${week.week_index})`);
		}
	}
});

test('generatePlan: masters step back volume every 3rd week, not every 4th', () => {
	const masters = generatePlan({
		goalEvent: 'distance_full',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		recent5kSec: 22 * 60,
		age: 60
	});
	// Week index 2 (3rd week) is the masters step-back. Guard against it
	// being pushed into taper on a short plan.
	if (masters.weeks.length >= 4 && masters.weeks[2].phase !== 'taper') {
		assert.ok(
			masters.weeks[2].target_volume_m <= masters.weeks[1].target_volume_m,
			'masters 3rd-week step-back should not exceed the 2nd week'
		);
		assert.match(masters.weeks[2].notes ?? '', /Step-back/);
	}
});

test('generatePlan: a sub-masters age leaves the standard Tue/Thu schedule intact', () => {
	const plan = generatePlan({
		goalEvent: 'distance_half',
		startDate: '2026-06-07',
		daysPerWeek: 5,
		goalTimeSec: 100 * 60,
		age: 34
	});
	const week = plan.weeks.find((w) => dayOffsetInWeek(w, QUALITY_KINDS) != null)!;
	assert.equal(dayOffsetInWeek(week, QUALITY_KINDS), 2);
});


// ─────────────────────── predictionConfidence ───────────────────────

const FIVE_K = 5000;
const TEN_K = 10000;
const MARATHON = 42195;

test('predictionConfidence: high when distance is close, effort recent, well-sampled', () => {
	const q = predictionConfidence({
		knownDistanceM: TEN_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 10,
		qualifyingRunCount: 5,
	});
	assert.equal(q.confidence, 'high');
	assert.equal(q.reason, 'similar');
});

test('predictionConfidence: low + extrapolated when projecting a marathon off a 5k', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: MARATHON,
		daysSinceBest: 5,
		qualifyingRunCount: 8,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'extrapolated');
});

test('predictionConfidence: moderate + stale when the only recent effort is weeks old', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 45,
		qualifyingRunCount: 4,
	});
	assert.equal(q.confidence, 'moderate');
	assert.equal(q.reason, 'stale');
});

test('predictionConfidence: moderate + limited when close + recent but thinly sampled', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 7,
		qualifyingRunCount: 1,
	});
	assert.equal(q.confidence, 'moderate');
	assert.equal(q.reason, 'limited');
});

test('predictionConfidence: moderate + extrapolated for a meaningful but not extreme gap', () => {
	// 5k → half marathon is ~4.2x — past the close band but within the
	// moderate factor<=3? No: 21097/5000 = 4.2 > 4 → far → low.
	// Use 10k → half (2.1x) to land in the moderate-extrapolated band.
	const q = predictionConfidence({
		knownDistanceM: TEN_K,
		targetDistanceM: 21097,
		daysSinceBest: 10,
		qualifyingRunCount: 5,
	});
	assert.equal(q.confidence, 'moderate');
	assert.equal(q.reason, 'extrapolated');
});

test('predictionConfidence: low + stale when the anchoring effort is over two months old', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 75,
		qualifyingRunCount: 4,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'stale');
});

test('predictionConfidence: low + limited with no qualifying runs', () => {
	const q = predictionConfidence({
		knownDistanceM: FIVE_K,
		targetDistanceM: FIVE_K,
		daysSinceBest: 5,
		qualifyingRunCount: 0,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'limited');
});

test('predictionConfidence: a >60d anchor stays low even when the distance gap is also far', () => {
	// A close+stale(75d) anchor is already graded low/stale (test above). Adding
	// a second degrading factor (a far distance gap) must NOT improve confidence
	// to moderate — a two-month-old effort is too stale to anchor at all,
	// regardless of the extrapolation distance. Guards against a confidence
	// inversion where a doubly-bad prediction outranks a singly-bad one.
	const q = predictionConfidence({
		knownDistanceM: TEN_K,
		targetDistanceM: 21097, // 2.1x — past the close band, within the 4x cap
		daysSinceBest: 75,
		qualifyingRunCount: 5,
	});
	assert.equal(q.confidence, 'low');
	assert.equal(q.reason, 'stale');
});

test('fmtHms — zero/null/negative render the em-dash placeholder', () => {
	assert.equal(fmtHms(0), '—');
	assert.equal(fmtHms(null), '—');
	assert.equal(fmtHms(undefined), '—');
	// A negative is truthy in JS; the <= 0 guard must still placeholder it.
	assert.equal(fmtHms(-90), '—');
	// Infinity is truthy and > 0 too, and printed "Infinity:NaN:NaN". The Dart
	// twin takes an `int?`, which cannot hold either of these.
	assert.equal(fmtHms(Number.POSITIVE_INFINITY), '—');
	assert.equal(fmtHms(Number.NaN), '—');
});

test('fmtHms — formats a positive duration', () => {
	assert.equal(fmtHms(90), '1:30');
	assert.equal(fmtHms(3661), '1:01:01');
});

test('generatePlan: a zero anchor is treated as no anchor (no Infinity vdot)', () => {
	const base = {
		goalEvent: 'distance_5k' as const,
		startDate: '2026-06-01',
		daysPerWeek: 4
	};
	const zero = generatePlan({ ...base, recent5kSec: 0 });
	const noAnchor = generatePlan(base);
	assert.equal(zero.vdot, null);
	const weekVol = (p: typeof zero, i: number) =>
		p.weeks[i].workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0);
	// A zero anchor scales volume identically to no anchor (0.6× peak).
	assert.equal(weekVol(zero, 0), weekVol(noAnchor, 0));
});

test('longRunDistance: flat 33% of weekly volume (rounded), 0 → 0', () => {
	const wk = (weeklyKm: number) =>
		({ weeklyKm }) as unknown as Parameters<typeof longRunDistance>[0];
	assert.equal(longRunDistance(wk(60)), 20); // round(19.8)
	assert.equal(longRunDistance(wk(50)), 17); // round(16.5)
	assert.equal(longRunDistance(wk(0)), 0);
});

test('the race workout is prescribed at the goal pace, at every distance', () => {
	// The generator used to hand `generateWeek` a goal pace reconstructed from
	// the derived `marathon` band: `paces.marathon * (goalDistanceM >= 21_000 ?
	// 1 : 0.95)`. Since that band is `goalPace * 1.06`, the 0.95 roughly undid
	// it on 5K/10K plans but the `1` left half + marathon plans prescribing the
	// race 6% slower than the runner's goal — a 3:30 marathon plan whose race
	// workout implied a 3:42 finish.
	const cases: Array<[string, number, number]> = [
		['distance_5k', 1_200, 5_000],
		['distance_10k', 2_700, 10_000],
		['distance_half', 6_300, 21_097],
		['distance_full', 12_600, 42_195]
	];
	for (const [goalEvent, goalTimeSec, distanceM] of cases) {
		const plan = generatePlan({
			goalEvent: goalEvent as Parameters<typeof generatePlan>[0]['goalEvent'],
			goalTimeSec,
			startDate: '2026-01-05',
			daysPerWeek: 5,
			weeks: 16
		});
		const goalPace = goalTimeSec / (distanceM / 1000);
		const race = plan.weeks.flatMap((w) => w.workouts).find((w) => w.kind === 'race');
		assert.ok(race, `${goalEvent} generates a race workout`);
		assert.ok(race!.target_pace_sec_per_km !== null, `${goalEvent} race carries a pace`);
		// Within a second per km — the only slack is integer sec/km rounding.
		assert.ok(
			Math.abs(race!.target_pace_sec_per_km! - goalPace) <= 1,
			`${goalEvent}: race pace ${race!.target_pace_sec_per_km} should be goal pace ${goalPace.toFixed(1)}`
		);
	}
});

test('marathon_pace sessions are prescribed at the goal pace, not the training band', () => {
	const plan = generatePlan({
		goalEvent: 'distance_full',
		goalTimeSec: 12_600,
		startDate: '2026-01-05',
		daysPerWeek: 5,
		weeks: 16
	});
	const goalPace = 12_600 / 42.195;
	const mp = plan.weeks.flatMap((w) => w.workouts).filter((w) => w.kind === 'marathon_pace');
	assert.ok(mp.length > 0, 'a marathon plan schedules marathon-pace work');
	for (const w of mp) {
		assert.ok(
			Math.abs(w.target_pace_sec_per_km! - goalPace) <= 1,
			`marathon_pace ${w.target_pace_sec_per_km} should be goal pace ${goalPace.toFixed(1)}`
		);
		// The structure the mobile workout runner executes must agree with the
		// headline target — they are read by different surfaces.
		const steady = (w.structure as { steady?: { pace_sec_per_km?: number } } | null)?.steady;
		assert.equal(steady?.pace_sec_per_km, w.target_pace_sec_per_km);
	}
});

test('a 10K plan keeps marathon_pace on the training band, not the goal pace', () => {
	// The other side of the same branch: on a short-distance goal this session
	// is steady aerobic work at marathon *effort*, which is legitimately slower
	// than goal pace. Pinning it stops the fix above from over-reaching.
	const plan = generatePlan({
		goalEvent: 'distance_10k',
		goalTimeSec: 2_700,
		startDate: '2026-01-05',
		daysPerWeek: 5,
		weeks: 16
	});
	const { paces } = resolveTrainingPacesWithMeta({ goalDistanceM: 10_000, goalTimeSec: 2_700 });
	const mp = plan.weeks.flatMap((w) => w.workouts).filter((w) => w.kind === 'marathon_pace');
	assert.ok(mp.length > 0);
	for (const w of mp) {
		assert.equal(w.target_pace_sec_per_km, paces.marathon);
		assert.ok(w.target_pace_sec_per_km! > 270, 'slower than the 10K goal pace');
	}
});

test('the goal pace the bands derive from is returned, ungendered', () => {
	// The race is the runner's stated goal; the female calibration shapes
	// training zones, so it must not move the goal itself.
	const male = resolveTrainingPacesWithMeta({ goalDistanceM: 42_195, goalTimeSec: 12_600 });
	const female = resolveTrainingPacesWithMeta({
		goalDistanceM: 42_195,
		goalTimeSec: 12_600,
		gender: 'female'
	});
	assert.equal(male.goalPaceSecPerKm, female.goalPaceSecPerKm);
	assert.ok(Math.abs(male.goalPaceSecPerKm - 12_600 / 42.195) < 0.001);
	assert.notEqual(male.paces.easy, female.paces.easy, 'bands still calibrate');
});

// ─────────────────────── Ultra distances (#1181) ───────────────────────

const MI_100 = 160_934.4;

function ultraPlan(
	distanceM: number,
	opts: { goalTimeSec?: number | null; recent5kSec?: number | null; days?: number; weeks?: number; age?: number | null } = {}
): GeneratedPlan {
	return generatePlan({
		goalEvent: 'custom',
		goalDistanceM: distanceM,
		goalTimeSec: opts.goalTimeSec ?? null,
		recent5kSec: opts.recent5kSec ?? null,
		startDate: '2026-11-01',
		daysPerWeek: opts.days ?? 5,
		weeks: opts.weeks,
		age: opts.age ?? null
	});
}

const isStepBack = (w: GeneratedPlan['weeks'][number]) => (w.notes ?? '').startsWith('Step-back');

test('ultra: a distance past the marathon is an ultra, the marathon itself is not', () => {
	assert.equal(isUltraDistance(GOAL_DISTANCES_M.distance_full), false);
	assert.equal(isUltraDistance(42_196), true);
	assert.equal(isUltraDistance(Number.NaN), false);
	assert.equal(isUltraDistance(Number.POSITIVE_INFINITY), false);
	for (const p of ULTRA_PRESETS) assert.ok(isUltraDistance(p.distanceM), p.id);
	assert.deepEqual(
		ULTRA_PRESETS.map((p) => p.distanceM),
		[50_000, 56_000, 90_000, MI_100]
	);
});

test('ultra: default plan weeks scale with the distance, and a custom road distance keeps 12', () => {
	assert.equal(defaultPlanWeeks('custom', 50_000), 16);
	assert.equal(defaultPlanWeeks('custom', 56_000), 16);
	assert.equal(defaultPlanWeeks('custom', 70_000), 18);
	assert.equal(defaultPlanWeeks('custom', 87_700), 20);
	assert.equal(defaultPlanWeeks('custom', MI_100), 24);
	assert.equal(defaultPlanWeeks('custom', 30_000), 12);
	assert.equal(defaultPlanWeeks('custom'), 12);
	assert.equal(defaultPlanWeeks('distance_full', MI_100), 16, 'a named event ignores the distance');
	assert.equal(ultraPlan(56_000).weeks.length, 16);
	assert.equal(ultraPlan(MI_100).weeks.length, 24);
});

test('ultra: weekly volume never grows more than 10% over the previous build week', () => {
	for (const d of [...ULTRA_PRESETS.map((p) => p.distanceM), 43_000, 70_000, 250_000]) {
		for (const days of [3, 4, 5, 6, 7]) {
			for (const anchor of [{}, { goalTimeSec: Math.round(d * 0.42) }, { recent5kSec: 1_500 }]) {
				for (const age of [30, 55]) {
					for (const weeks of [undefined, 8, 12]) {
						const plan = ultraPlan(d, { ...anchor, days, age, weeks });
						let prev: number | null = null;
						for (const w of plan.weeks) {
							if (w.phase === 'taper' || w.phase === 'race') break;
							if (isStepBack(w)) continue;
							if (prev !== null) {
								assert.ok(
									w.target_volume_m <= prev * ULTRA_MAX_WEEKLY_RAMP + 1e-6,
									`${d} m, ${days} d/wk, week ${w.week_index}: ${prev} -> ${w.target_volume_m}`
								);
							}
							prev = w.target_volume_m;
						}
					}
				}
			}
		}
	}
});

test('ultra: no long run outlasts the time-on-feet cap', () => {
	assert.equal(ultraLongRunCapSec(50_000), 3.5 * 3600);
	assert.equal(ultraLongRunCapSec(56_000), 3.5 * 3600);
	assert.equal(ultraLongRunCapSec(70_000), 4 * 3600);
	assert.equal(ultraLongRunCapSec(90_000), 5 * 3600);
	assert.equal(ultraLongRunCapSec(MI_100), 6 * 3600);
	for (const d of [...ULTRA_PRESETS.map((p) => p.distanceM), 70_000]) {
		for (const days of [3, 5, 7]) {
			// A fast runner at 7 days pushes the long run hardest into its cap.
			const plan = ultraPlan(d, { recent5kSec: 1_080, days });
			const longs = plan.weeks.flatMap((w) => w.workouts).filter((w) => w.kind === 'long');
			assert.ok(longs.length > 0);
			for (const w of longs) {
				assert.ok(w.target_duration_seconds! <= ultraLongRunCapSec(d), `${d}: ${w.target_duration_seconds}`);
			}
		}
	}
	// The cap binds: a 32-hour 100-miler and a 7-hour 56 km runner both reach it.
	const longest = (plan: GeneratedPlan) =>
		Math.max(
			...plan.weeks.flatMap((w) => w.workouts).map((w) => (w.kind === 'long' ? w.target_duration_seconds! : 0))
		);
	assert.equal(longest(ultraPlan(MI_100, { goalTimeSec: 32 * 3600, days: 7 })), 6 * 3600);
	assert.equal(longest(ultraPlan(56_000, { goalTimeSec: 7 * 3600, days: 6 })), 3.5 * 3600);
});

test('ultra: long runs are time-on-feet targets with no pace, their distance the duration at easy pace', () => {
	const plan = ultraPlan(56_000, { goalTimeSec: 6 * 3600 });
	const longs = plan.weeks.flatMap((w) => w.workouts).filter((w) => w.kind === 'long');
	for (const w of longs) {
		assert.ok(w.target_duration_seconds! >= 3600);
		assert.equal(w.target_duration_seconds! % 900, 0, 'quarter-hour steps');
		assert.equal(w.target_pace_sec_per_km, null);
		assert.equal(w.target_pace_tolerance_sec, null);
		assert.equal(
			w.target_distance_m,
			Math.round((w.target_duration_seconds! / plan.paces.easy) * 10) * 100
		);
	}
});

test('ultra: 90 km and 100 mi plans carry back-to-back weekends; 50 km and 56 km do not', () => {
	const saturdayLongs = (plan: GeneratedPlan) =>
		plan.weeks.flatMap((w, i) =>
			w.workouts
				.filter((x) => x.kind === 'long' && x.scheduled_date !== w.workouts[0].scheduled_date)
				.map((x) => ({ week: i, workout: x }))
		);
	for (const d of [87_700, 90_000, MI_100]) {
		const plan = ultraPlan(d, { goalTimeSec: Math.round(d * 0.45), days: 5 });
		const b2b = saturdayLongs(plan);
		assert.ok(b2b.length >= 4, `${d}: ${b2b.length} back-to-back weekends`);
		for (const { week, workout } of b2b) {
			assert.equal(parseISO(workout.scheduled_date).getDay(), 6, 'Saturday');
			assert.ok(['build', 'peak'].includes(plan.weeks[week].phase));
			// The next day is the following week's Sunday long run.
			const sunday = plan.weeks[week + 1].workouts[0];
			assert.equal(sunday.kind, 'long');
			assert.ok(workout.target_duration_seconds! <= Math.floor((ultraLongRunCapSec(d) * 0.6) / 900) * 900);
		}
		for (const w of plan.weeks.filter((x) => x.phase === 'taper')) {
			assert.equal(w.workouts.filter((x) => x.kind === 'long').length, 1, 'no back-to-back in the taper');
		}
	}
	for (const d of [50_000, 56_000, 70_000]) {
		assert.equal(saturdayLongs(ultraPlan(d, { goalTimeSec: Math.round(d * 0.45) })).length, 0, `${d}`);
	}
});

test('ultra: the taper runs 2 weeks below 80 km and 3 from 80 km, cutting volume each week', () => {
	assert.equal(ultraTaperWeeks(56_000, 16), 2);
	assert.equal(ultraTaperWeeks(90_000, 20), 3);
	assert.equal(ultraTaperWeeks(MI_100, 8), 1, 'a short plan keeps most of its weeks to build');
	assert.equal(ultraTaperWeeks(MI_100, 1), 0);
	for (const [d, taper] of [
		[56_000, 2],
		[MI_100, 3]
	] as const) {
		const plan = ultraPlan(d, { goalTimeSec: Math.round(d * 0.45) });
		const tapers = plan.weeks.filter((w) => w.phase === 'taper');
		assert.equal(tapers.length, taper, `${d}`);
		assert.equal(plan.weeks.at(-1)!.phase, 'race');
		const peak = Math.max(...plan.weeks.filter((w) => w.phase !== 'race').map((w) => w.target_volume_m));
		let prev = peak;
		for (const w of tapers) {
			assert.ok(w.target_volume_m < prev, `taper week ${w.week_index} comes down`);
			assert.ok(w.workouts.some((x) => x.kind === 'tempo'), 'some intensity stays');
			prev = w.target_volume_m;
		}
		assert.ok(tapers.at(-1)!.target_volume_m <= peak * 0.6, 'the last taper week is well under peak');
	}
});

test('ultra: a custom 70 km plan is an 18-week ultra plan with no back-to-backs', () => {
	const plan = ultraPlan(70_000, { goalTimeSec: 8 * 3600, days: 5 });
	assert.equal(plan.weeks.length, 18);
	assert.equal(plan.goalDistanceM, 70_000);
	const workouts = plan.weeks.flatMap((w) => w.workouts);
	assert.ok(workouts.every((w) => w.kind !== 'marathon_pace'), 'no goal pace to rehearse');
	assert.ok(workouts.filter((w) => w.kind === 'long').every((w) => w.target_duration_seconds! <= 4 * 3600));
	assert.equal(
		workouts.filter((w) => w.kind === 'long' && parseISO(w.scheduled_date).getDay() === 6).length,
		0
	);
	assert.equal(plan.weeks.filter((w) => w.phase === 'taper').length, 2);
});

test('ultra: the race day carries the goal time as its duration and no pace', () => {
	const withGoal = ultraPlan(90_000, { goalTimeSec: 11 * 3600 });
	const race = withGoal.weeks.at(-1)!.workouts[0];
	assert.equal(race.kind, 'race');
	assert.equal(race.target_distance_m, 90_000);
	assert.equal(race.target_duration_seconds, 11 * 3600);
	assert.equal(race.target_pace_sec_per_km, null);
	const noGoal = ultraPlan(90_000).weeks.at(-1)!.workouts[0];
	assert.equal(noGoal.target_duration_seconds, null);
});

test('ultra: training zones come from the marathon equivalent of the goal', () => {
	assert.equal(ultraMarathonEquivalentSec(24 * 3600, MI_100), 18_532);
	const plan = ultraPlan(MI_100, { goalTimeSec: 24 * 3600 });
	const expected = resolveTrainingPaces({ goalDistanceM: 42_195, goalTimeSec: 18_532 });
	assert.deepEqual(plan.paces, expected);
	assert.ok(plan.paces.tempo < 24 * 3600 / 160.9344, 'tempo is faster than the 100-mile race pace');
	assert.ok(Math.abs(plan.vdot! - vdotFromRace(42_195, 18_532)) < 1e-9);
	// A recent 5k anchors through the marathon too.
	const anchored = ultraPlan(MI_100, { recent5kSec: 1_500 });
	assert.deepEqual(anchored.paces, resolveTrainingPaces({ goalDistanceM: 42_195, recent5kSec: 1_500 }));
});

test('ultra: peak volume continues from the marathon and caps at 120 km', () => {
	assert.equal(peakVolumeKm(42_195, 5), peakVolumeKm(42_196, 5));
	assert.equal(peakVolumeKm(MI_100, 6), 120);
	assert.equal(peakVolumeKm(250_000, 6), 120);
	assert.ok(peakVolumeKm(90_000, 5) > peakVolumeKm(56_000, 5));
});

test('ultra: any distance from 5 km plans from a distance, a date and training days alone', () => {
	for (const d of [5_000, 12_345, 42_195, 43_000, 56_000, 87_700, 123_456, MI_100, 386_000]) {
		for (const days of [3, 4, 5, 6, 7]) {
			const plan = generatePlan({ goalEvent: 'custom', goalDistanceM: d, startDate: '2027-01-03', daysPerWeek: days });
			assert.equal(plan.goalDistanceM, d);
			assert.ok(plan.weeks.length >= 8);
			const all = plan.weeks.flatMap((w) => w.workouts);
			assert.equal(all.length, plan.weeks.length * 7);
			for (const w of all) {
				assert.ok(w.target_distance_m === null || (Number.isFinite(w.target_distance_m) && w.target_distance_m > 0));
			}
			assert.ok(all.filter((w) => w.kind !== 'rest').length <= plan.weeks.length * days);
			const race = plan.weeks.at(-1)!.workouts[0];
			assert.equal(race.kind, 'race');
			assert.equal(race.target_distance_m, d);
		}
	}
});

test('ultra: road plans are unchanged by the ultra branch', () => {
	// Captured from the generator before the ultra branch landed.
	const marathon = generatePlan({
		goalEvent: 'distance_full',
		goalTimeSec: 4 * 3600,
		startDate: '2026-11-01',
		daysPerWeek: 5
	});
	assert.deepEqual(
		marathon.weeks.map((w) => w.target_volume_m),
		[41000, 44000, 45000, 40000, 49000, 52000, 54000, 46000, 58000, 61000, 63000, 52000, 67000, 37000, 37000, 42195]
	);
	assert.equal(marathon.weeks[15].workouts[0].target_pace_sec_per_km, 341);
	const custom30k = generatePlan({
		goalEvent: 'custom',
		goalDistanceM: 30_000,
		recent5kSec: 1_500,
		startDate: '2026-11-01',
		daysPerWeek: 4
	});
	assert.deepEqual(
		custom30k.weeks.map((w) => w.target_volume_m),
		[27000, 29000, 30000, 27000, 33000, 36000, 38000, 33000, 42000, 24000, 24000, 30000]
	);
	// The marathon distance itself, entered as a custom goal, stays a road plan.
	const customMarathon = generatePlan({
		goalEvent: 'custom',
		goalDistanceM: 42_195,
		goalTimeSec: 4 * 3600,
		startDate: '2026-11-01',
		daysPerWeek: 5,
		weeks: 16
	});
	assert.deepEqual(customMarathon.weeks, marathon.weeks);
});
