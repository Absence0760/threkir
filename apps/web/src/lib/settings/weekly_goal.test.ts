import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	WEEKLY_GOAL_KEY,
	WEEKLY_GOAL_MAX,
	WEEKLY_GOAL_MIN,
	isUsableWeeklyGoalInput,
	weeklyGoalFromInput,
	weeklyGoalToInput,
} from './weekly_goal';

test('the goal is stored under the registered bag key', () => {
	assert.equal(WEEKLY_GOAL_KEY, 'weekly_mileage_goal_m');
});

test('a stored goal shows in the reader own unit, to one decimal', () => {
	assert.equal(weeklyGoalToInput(50000, 'km'), 50);
	assert.equal(weeklyGoalToInput(50000, 'mi'), 31.1);
	assert.equal(weeklyGoalToInput(42195, 'km'), 42.2);
	assert.equal(weeklyGoalToInput(42195, 'mi'), 26.2);
});

test('an absent or unusable stored goal shows nothing', () => {
	for (const stored of [null, undefined, 0, -5, Number.NaN, Number.POSITIVE_INFINITY, '50000']) {
		assert.equal(weeklyGoalToInput(stored, 'km'), null, String(stored));
	}
});

test('a stored goal below the display precision shows as 0, which the field refuses', () => {
	assert.equal(weeklyGoalToInput(1, 'km'), 0);
	assert.equal(isUsableWeeklyGoalInput(weeklyGoalToInput(1, 'km')), false);
});

test('a typed goal is stored in whole metres', () => {
	assert.equal(weeklyGoalFromInput(50, 'km', null), 50000);
	assert.equal(weeklyGoalFromInput(31, 'mi', null), 49890);
	assert.equal(weeklyGoalFromInput(26.2, 'mi', null), 42165);
	assert.equal(weeklyGoalFromInput(0.1, 'mi', null), 161);
});

test('every one-decimal goal in range survives a save and a reload unchanged', () => {
	for (let tenths = WEEKLY_GOAL_MIN * 10; tenths <= WEEKLY_GOAL_MAX * 10; tenths++) {
		const typed = tenths / 10;
		for (const unit of ['km', 'mi'] as const) {
			const stored = weeklyGoalFromInput(typed, unit, null);
			assert.equal(weeklyGoalToInput(stored, unit), typed, `${typed} ${unit}`);
		}
	}
});

test('re-saving the value the field shows keeps the stored metres', () => {
	assert.equal(weeklyGoalFromInput(31.1, 'mi', 50000), 50000);
	assert.equal(weeklyGoalFromInput(31.2, 'mi', 50000), 50212);
	assert.equal(weeklyGoalFromInput(50, 'km', '50000'), 50000);
});

test('an empty, unparseable or non-positive field clears the goal', () => {
	for (const typed of [null, Number.NaN, 0, -31.1]) {
		assert.equal(weeklyGoalFromInput(typed, 'mi', 50000), null, String(typed));
	}
});

test('only a finite goal inside the range is usable', () => {
	for (const typed of [WEEKLY_GOAL_MIN, 1, 42.2, WEEKLY_GOAL_MAX]) {
		assert.equal(isUsableWeeklyGoalInput(typed), true, String(typed));
	}
	for (const typed of [null, Number.NaN, Number.POSITIVE_INFINITY, -1, 0, 0.05, 500.5]) {
		assert.equal(isUsableWeeklyGoalInput(typed), false, String(typed));
	}
});
