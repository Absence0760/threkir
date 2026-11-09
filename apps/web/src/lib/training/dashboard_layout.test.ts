import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	DASHBOARD_HIDDEN_CARDS_KEY,
	HIDEABLE_DASHBOARD_CARDS,
	parseHiddenCards,
	todayHeroState,
	withCardHidden,
	type TodayHeroInputs,
} from './dashboard_layout';

const base: TodayHeroInputs = {
	hasPlan: false,
	raceToday: false,
	todayWorkoutKind: null,
	isNewAccount: false,
	ranToday: false,
};

test('a plan workout today leads', () => {
	assert.equal(todayHeroState({ ...base, hasPlan: true, todayWorkoutKind: 'easy' }), 'plan_today');
});

test('race day outranks the day\'s workout', () => {
	assert.equal(
		todayHeroState({ ...base, hasPlan: true, raceToday: true, todayWorkoutKind: 'race' }),
		'race_day',
	);
});

test('a plan with nothing or a rest workout today is a rest day', () => {
	assert.equal(todayHeroState({ ...base, hasPlan: true }), 'rest_day');
	assert.equal(todayHeroState({ ...base, hasPlan: true, todayWorkoutKind: 'rest' }), 'rest_day');
});

test('a plan rest day stays a rest day even after a run', () => {
	assert.equal(todayHeroState({ ...base, hasPlan: true, ranToday: true }), 'rest_day');
});

test('a new account without a plan gets the first-run state', () => {
	assert.equal(todayHeroState({ ...base, isNewAccount: true }), 'new_account');
});

test('a new account with a plan is led by the plan', () => {
	assert.equal(
		todayHeroState({ ...base, isNewAccount: true, hasPlan: true, todayWorkoutKind: 'easy' }),
		'plan_today',
	);
});

test('without a plan, a run today leads', () => {
	assert.equal(todayHeroState({ ...base, ranToday: true }), 'ran_today');
});

test('without a plan or a run today, readiness and a start prompt lead', () => {
	assert.equal(todayHeroState(base), 'no_plan');
});

test('the settings key and the hideable ids', () => {
	assert.equal(DASHBOARD_HIDDEN_CARDS_KEY, 'dashboard_hidden_cards');
	assert.deepEqual([...HIDEABLE_DASHBOARD_CARDS], ['volume', 'fitness', 'performance', 'effort', 'recent']);
});

test('parse keeps known ids once, in Home order', () => {
	assert.deepEqual(parseHiddenCards(['recent', 'volume', 'recent']), ['volume', 'recent']);
});

test('parse drops unknown ids and non-strings', () => {
	assert.deepEqual(parseHiddenCards(['streak', 3, null, 'effort']), ['effort']);
});

test('parse reads anything that is not a list as nothing hidden', () => {
	assert.deepEqual(parseHiddenCards(null), []);
	assert.deepEqual(parseHiddenCards('volume'), []);
	assert.deepEqual(parseHiddenCards({ volume: true }), []);
});

test('hiding adds an id in Home order and is idempotent', () => {
	assert.deepEqual(withCardHidden(['recent'], 'volume', true), ['volume', 'recent']);
	assert.deepEqual(withCardHidden(['volume'], 'volume', true), ['volume']);
});

test('showing removes an id and tolerates one that was not hidden', () => {
	assert.deepEqual(withCardHidden(['volume', 'recent'], 'volume', false), ['recent']);
	assert.deepEqual(withCardHidden(['recent'], 'effort', false), ['recent']);
});

test('a toggle drops ids the parse would drop', () => {
	assert.deepEqual(withCardHidden(['streak', 'fitness'], 'effort', true), ['fitness', 'effort']);
});
