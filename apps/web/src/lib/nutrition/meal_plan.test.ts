import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	activeAssignmentForDate,
	assignmentGoverns,
	assignmentsToEnd,
	dayBefore,
	GOAL_PHASES,
	goalPhaseToWeightGoal,
	planDraftFromTargets,
	prescribedTargets,
	stopFollowingAction,
	weightGoalToGoalPhase,
	type PlanAssignment,
	type PlanTargets,
} from './meal_plan';
import { GOAL_KCAL_DELTA, MIN_CALORIE_TARGET } from './nutrition_targets';

function plan(opts: Partial<PlanTargets> = {}): PlanTargets {
	return {
		targetCalories: 2200,
		targetProteinG: 140,
		targetCarbsG: 250,
		targetFatG: 70,
		trainingCalories: null,
		trainingCarbsG: null,
		...opts,
	};
}

function assignment(id: string, opts: Partial<PlanAssignment> = {}): PlanAssignment {
	return {
		id,
		planId: `plan-${id}`,
		startDate: '2027-03-01',
		endDate: null,
		status: 'active',
		createdAt: '2027-03-01T08:00:00Z',
		...opts,
	};
}

// ── prescribedTargets ───────────────────────────────────────────────────────

test('prescribedTargets returns the rest-day targets on a rest day', () => {
	assert.deepEqual(prescribedTargets(plan(), false), {
		calories: 2200,
		proteinG: 140,
		carbsG: 250,
		fatG: 70,
		isTrainingDay: false,
	});
});

test('prescribedTargets applies the training override to calories and carbs only', () => {
	const d = prescribedTargets(plan({ trainingCalories: 2600, trainingCarbsG: 340 }), true);
	assert.deepEqual(d, { calories: 2600, proteinG: 140, carbsG: 340, fatG: 70, isTrainingDay: true });
});

test('prescribedTargets ignores the training override on a rest day', () => {
	const d = prescribedTargets(plan({ trainingCalories: 2600, trainingCarbsG: 340 }), false);
	assert.equal(d?.calories, 2200);
	assert.equal(d?.carbsG, 250);
});

test('prescribedTargets falls back to rest-day values when a training day has no override', () => {
	const d = prescribedTargets(plan({ trainingCalories: 2600 }), true);
	assert.equal(d?.calories, 2600);
	assert.equal(d?.carbsG, 250);
});

test('prescribedTargets keeps a kcal-only plan kcal-only', () => {
	const d = prescribedTargets(
		plan({ targetProteinG: null, targetCarbsG: null, targetFatG: null }),
		false,
	);
	assert.deepEqual(d, { calories: 2200, proteinG: null, carbsG: null, fatG: null, isTrainingDay: false });
});

test('prescribedTargets clamps calories to the app soft floor', () => {
	assert.equal(prescribedTargets(plan({ targetCalories: 1050 }), false)?.calories, MIN_CALORIE_TARGET);
	assert.equal(
		prescribedTargets(plan({ trainingCalories: 1100 }), true)?.calories,
		MIN_CALORIE_TARGET,
	);
});

test('prescribedTargets rounds to whole kcal and grams', () => {
	const d = prescribedTargets(plan({ targetCalories: 2200.5, targetProteinG: 139.6, targetFatG: 70.4 }), false);
	assert.equal(d?.calories, 2201);
	assert.equal(d?.proteinG, 140);
	assert.equal(d?.fatG, 70);
});

test('prescribedTargets returns null for a non-finite calorie spine', () => {
	assert.equal(prescribedTargets(plan({ targetCalories: Number.NaN }), false), null);
	assert.equal(prescribedTargets(plan({ targetCalories: Number.POSITIVE_INFINITY }), false), null);
});

test('prescribedTargets treats a non-finite or negative macro as unprescribed', () => {
	const d = prescribedTargets(plan({ targetProteinG: Number.NaN, targetFatG: -5 }), false);
	assert.equal(d?.proteinG, null);
	assert.equal(d?.fatG, null);
	assert.equal(d?.carbsG, 250);
});

// ── assignmentGoverns / activeAssignmentForDate ─────────────────────────────

test('an open-ended active assignment governs from its start onward', () => {
	const a = assignment('a');
	assert.equal(assignmentGoverns(a, '2027-02-28'), false);
	assert.equal(assignmentGoverns(a, '2027-03-01'), true);
	assert.equal(assignmentGoverns(a, '2028-01-01'), true);
});

test('a bounded assignment governs its range inclusive, whatever its status', () => {
	const a = assignment('a', { endDate: '2027-03-10', status: 'ended' });
	assert.equal(assignmentGoverns(a, '2027-03-10'), true);
	assert.equal(assignmentGoverns(a, '2027-03-11'), false);
	assert.equal(assignmentGoverns({ ...a, status: 'active' }, '2027-03-05'), true);
});

test('an ended assignment with no end date governs nothing', () => {
	assert.equal(assignmentGoverns(assignment('a', { status: 'ended' }), '2027-03-05'), false);
});

test('activeAssignmentForDate returns null when nothing governs the day', () => {
	assert.equal(activeAssignmentForDate([], '2027-03-05'), null);
	assert.equal(activeAssignmentForDate([assignment('a')], '2027-02-01'), null);
});

test('activeAssignmentForDate lets the newest start date win an overlap', () => {
	const older = assignment('older', { startDate: '2027-03-01' });
	const newer = assignment('newer', { startDate: '2027-03-05', createdAt: '2027-02-01T00:00:00Z' });
	assert.equal(activeAssignmentForDate([newer, older], '2027-03-06')?.id, 'newer');
	assert.equal(activeAssignmentForDate([newer, older], '2027-03-04')?.id, 'older');
});

test('activeAssignmentForDate breaks a same-start tie on created_at, then id', () => {
	const a = assignment('a', { createdAt: '2027-03-01T08:00:00Z' });
	const b = assignment('b', { createdAt: '2027-03-01T09:00:00Z' });
	assert.equal(activeAssignmentForDate([b, a], '2027-03-02')?.id, 'b');
	const c = assignment('c', { createdAt: '2027-03-01T08:00:00Z' });
	assert.equal(activeAssignmentForDate([c, a], '2027-03-02')?.id, 'c');
});

// ── stopping and switching ──────────────────────────────────────────────────

test('dayBefore steps through month and year boundaries', () => {
	assert.equal(dayBefore('2027-03-01'), '2027-02-28');
	assert.equal(dayBefore('2028-03-01'), '2028-02-29');
	assert.equal(dayBefore('2027-01-01'), '2026-12-31');
});

test('stopFollowingAction closes an older assignment on yesterday', () => {
	assert.deepEqual(stopFollowingAction(assignment('a'), '2027-03-20'), {
		kind: 'end',
		endDate: '2027-03-19',
	});
});

test('stopFollowingAction deletes an assignment that started today or later', () => {
	assert.deepEqual(stopFollowingAction(assignment('a', { startDate: '2027-03-20' }), '2027-03-20'), {
		kind: 'delete',
	});
});

test('stopFollowingAction never extends an end date that already closed', () => {
	assert.deepEqual(
		stopFollowingAction(assignment('a', { endDate: '2027-03-10' }), '2027-03-20'),
		{ kind: 'end', endDate: '2027-03-10' },
	);
});

test('assignmentsToEnd keeps only active rows still reaching today', () => {
	const open = assignment('open');
	const reaching = assignment('reaching', { endDate: '2027-03-25' });
	const past = assignment('past', { endDate: '2027-03-10' });
	const ended = assignment('ended', { status: 'ended', endDate: '2027-03-25' });
	assert.deepEqual(
		assignmentsToEnd([open, reaching, past, ended], '2027-03-20').map((a) => a.id),
		['open', 'reaching'],
	);
});

// ── goal phase vocabulary ───────────────────────────────────────────────────

test('goalPhaseToWeightGoal maps every phase onto a GOAL_KCAL_DELTA key', () => {
	assert.deepEqual(
		GOAL_PHASES.map((p) => goalPhaseToWeightGoal(p)),
		['lose', 'maintain', 'gain', 'maintain'],
	);
	for (const p of GOAL_PHASES) assert.ok(goalPhaseToWeightGoal(p) in GOAL_KCAL_DELTA);
	assert.equal(goalPhaseToWeightGoal('bulk'), 'maintain');
});

test('weightGoalToGoalPhase is the inverse for the three weight goals', () => {
	assert.deepEqual(
		['lose', 'maintain', 'gain', 'recomp'].map((g) => weightGoalToGoalPhase(g)),
		['cut', 'maintain', 'build', 'maintain'],
	);
});

// ── planDraftFromTargets ────────────────────────────────────────────────────

test('planDraftFromTargets seeds the rest-day target, not the exercise-inflated one', () => {
	const input = {
		weightKg: 70,
		heightCm: 175,
		ageYears: 30,
		sex: 'male',
		activityLevel: 'moderate' as const,
		goal: 'lose' as const,
		exerciseKcal: 600,
	};
	const d = planDraftFromTargets(input);
	assert.deepEqual(d, {
		goalPhase: 'cut',
		targetCalories: 2060,
		targetProteinG: 126,
		targetCarbsG: 234,
		targetFatG: 69,
	});
});

test('planDraftFromTargets returns null without body metrics', () => {
	assert.equal(
		planDraftFromTargets({
			weightKg: null,
			heightCm: 175,
			ageYears: 30,
			sex: null,
			activityLevel: 'moderate',
			goal: 'maintain',
		}),
		null,
	);
});
