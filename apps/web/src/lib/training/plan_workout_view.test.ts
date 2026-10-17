// The shared plan-workout reading: status by the runner's local day and the
// one accessible name every plan cell announces (decisions § 2084).
//
// Invocation:
//   npx tsx --test src/lib/training/plan_workout_view.test.ts

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { planWorkoutAriaLabel, planWorkoutStatusOf } from './plan_workout_view';
import { en } from '../i18n/locales/en';
import { planWorkoutStatusLook } from './plan_workout_status_style';

const tempo = {
	scheduled_date: '2026-10-13',
	kind: 'tempo',
	manually_completed: false,
	completed_run_id: null,
	skipped_at: null
};

test('planWorkoutStatusOf reads completion from either field and the skip stamp', () => {
	assert.equal(planWorkoutStatusOf({ ...tempo, completed_run_id: 'r1' }, '2026-10-20'), 'done');
	assert.equal(planWorkoutStatusOf({ ...tempo, manually_completed: true }, '2026-10-20'), 'done');
	assert.equal(planWorkoutStatusOf({ ...tempo, skipped_at: '2026-10-13T08:00:00Z' }, '2026-10-20'), 'skipped');
	assert.equal(planWorkoutStatusOf(tempo, '2026-10-20'), 'missed');
	assert.equal(planWorkoutStatusOf(tempo, '2026-10-13'), 'upcoming');
});

test('planWorkoutAriaLabel names the day, kind, distance and state', () => {
	assert.equal(
		planWorkoutAriaLabel(
			tempo,
			'2026-10-20',
			{ day: 'Tue 13 Oct', kind: 'Tempo', distance: '8.0 km' },
			(k) => en[k]
		),
		'Tue 13 Oct: Tempo, 8.0 km, missed'
	);
	assert.equal(
		planWorkoutAriaLabel(
			{ ...tempo, completed_run_id: 'r1' },
			'2026-10-13',
			{ day: 'Tue', kind: 'Tempo', distance: null },
			(k) => en[k]
		),
		'Tue: Tempo, completed, today'
	);
});

test('missed is neutral: dashed outline in the muted text colour, no error or warning ramp', () => {
	const missed = planWorkoutStatusLook('missed');
	assert.equal(missed.borderStyle, 'dashed');
	for (const v of [missed.bg, missed.border, missed.glyphColor]) {
		assert.ok(!/error|danger|warning/.test(v ?? ''), `missed borrows ${v}`);
	}
});

test('an upcoming workout keeps the surface fill and outline', () => {
	const look = planWorkoutStatusLook('upcoming');
	assert.equal(look.bg, null);
	assert.equal(look.border, null);
});
