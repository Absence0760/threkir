import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	RACE_PLAN_DESCRIBE_MAX,
	racePlanChain,
	racePlanDescribe,
	racePlanGoalTimeS,
	racePlanHref,
	type RacePlanOwnPlan,
	type RacePlanRace,
} from './race_plan_prefill';

const TODAY = '2026-08-14'; // a Friday
const RICHMOND: RacePlanRace = { name: 'Richmond Marathon', raceDateIso: '2026-11-14', distanceM: 42_195 };

function plan(p: Partial<RacePlanOwnPlan> & Pick<RacePlanOwnPlan, 'id' | 'endDateIso'>): RacePlanOwnPlan {
	return { name: p.id, status: 'active', goalDistanceM: null, goalTimeSeconds: null, ...p };
}

const FULL = {
	race: RICHMOND,
	goalTimeS: 13_500,
	recentEffort: { distanceM: 10_000, durationS: 2910, ageDays: 12.3 },
	course: { ascentM: 250.4, descentM: 240, surface: ' road ' },
};

test('describe: every field, in priority order', () => {
	assert.equal(
		racePlanDescribe(FULL),
		'Race: Richmond Marathon on 2026-11-14. Distance: 42.2 km. Goal time: 3:45:00. ' +
			'Recent effort: 10 km in 48:30, 12 days ago. Course: 250 m ascent, 240 m descent, road surface.',
	);
});

test('describe: no fitness and no course fall back to the race and goal', () => {
	assert.equal(
		racePlanDescribe({ race: RICHMOND, goalTimeS: 13_500, recentEffort: null, course: null }),
		'Race: Richmond Marathon on 2026-11-14. Distance: 42.2 km. Goal time: 3:45:00.',
	);
});

test('describe: unusable values are left out rather than written as zero', () => {
	assert.equal(
		racePlanDescribe({
			race: { name: 'Mystery Trail', raceDateIso: '2026-11-14', distanceM: null },
			goalTimeS: 0,
			recentEffort: { distanceM: 5000, durationS: 0, ageDays: 3 },
			course: { ascentM: null, descentM: 0, surface: '   ' },
		}),
		'Race: Mystery Trail on 2026-11-14.',
	);
	assert.equal(
		racePlanDescribe({ race: { name: 'Mystery Trail', raceDateIso: '2026-11-14', distanceM: null }, goalTimeS: NaN }),
		'Race: Mystery Trail on 2026-11-14.',
	);
});

test('describe: the 600-char cap holds for an absurd listing', () => {
	const out = racePlanDescribe({
		race: { name: 'x'.repeat(1000), raceDateIso: '2026-11-14', distanceM: 42_195 },
		goalTimeS: 13_500,
		recentEffort: { distanceM: 10_000, durationS: 2910, ageDays: 12 },
		course: { ascentM: 1_000_000, descentM: 1_000_000, surface: 'y'.repeat(500) },
	});
	assert.equal(RACE_PLAN_DESCRIBE_MAX, 600);
	assert.ok(out.length <= 600, String(out.length));
	assert.ok(out.startsWith(`Race: ${'x'.repeat(120)} on 2026-11-14. Distance: 42.2 km.`), out);
	assert.ok(out.endsWith(`${'y'.repeat(40)} surface.`), out);
});

test('describe: a tighter cap drops lower-priority sentences whole', () => {
	assert.equal(racePlanDescribe(FULL, 60), 'Race: Richmond Marathon on 2026-11-14. Distance: 42.2 km.');
	assert.equal(racePlanDescribe(FULL, 40), 'Race: Richmond Marathon on 2026-11-14.');
});

test('describe: distances, clocks and ages format the same on both platforms', () => {
	const race = { name: 'Two  Oceans\nHalf', raceDateIso: '2027-04-04', distanceM: 21_097.5 };
	assert.equal(
		racePlanDescribe({ race, goalTimeS: 5999, recentEffort: { distanceM: 5000, durationS: 1499.6, ageDays: 0.6 } }),
		'Race: Two Oceans Half on 2027-04-04. Distance: 21.1 km. Goal time: 1:39:59. ' +
			'Recent effort: 5 km in 25:00, 1 day ago.',
	);
	assert.ok(
		racePlanDescribe({ race, recentEffort: { distanceM: 5000, durationS: 1500, ageDays: 0.2 } }).endsWith(
			'5 km in 25:00, today.',
		),
	);
});

test('chain: follows the latest active plan ending before race day', () => {
	const plans = [
		plan({ id: 'a', endDateIso: '2026-09-20', goalDistanceM: 21_097.5 }),
		plan({ id: 'b', name: 'Autumn 10k', endDateIso: '2026-10-04', goalDistanceM: 10_000 }),
		plan({ id: 'c', status: 'completed', endDateIso: '2026-10-30' }),
		plan({ id: 'd', endDateIso: '2026-11-14' }),
	];
	assert.deepEqual(racePlanChain(plans, RICHMOND, TODAY), {
		planId: 'b',
		planName: 'Autumn 10k',
		planEndIso: '2026-10-04',
		recoveryDays: 3,
		notBeforeIso: '2026-10-08',
	});
});

test('chain: none when no active plan ends before race day', () => {
	const plans = [
		plan({ id: 'c', status: 'completed', endDateIso: '2026-10-30' }),
		plan({ id: 'd', endDateIso: '2026-11-14' }),
	];
	assert.equal(racePlanChain(plans, RICHMOND, TODAY), null);
	assert.equal(racePlanChain([], RICHMOND, TODAY), null);
});

test('chain: none when the recovery floor is already behind today', () => {
	const plans = [plan({ id: 'old', endDateIso: '2026-07-20', goalDistanceM: 5000 })];
	assert.equal(racePlanChain(plans, RICHMOND, TODAY), null);
});

test('chain: none when the race is too close to build after the earlier plan', () => {
	const plans = [plan({ id: 'm', endDateIso: '2026-10-25', goalDistanceM: 42_195 })];
	assert.equal(racePlanChain(plans, RICHMOND, TODAY), null);
});

test('goal time: an active plan ending on race day supplies it', () => {
	const plans = [
		plan({ id: 'done', status: 'completed', endDateIso: '2026-11-14', goalTimeSeconds: 10_000 }),
		plan({ id: 'live', endDateIso: '2026-11-14', goalTimeSeconds: 13_500.4 }),
	];
	assert.equal(racePlanGoalTimeS(plans, '2026-11-14'), 13_500);
});

test('goal time: none without a matching plan that carries one', () => {
	const plans = [
		plan({ id: 'other', endDateIso: '2026-11-15', goalTimeSeconds: 13_500 }),
		plan({ id: 'blank', endDateIso: '2026-11-14', goalTimeSeconds: 0 }),
	];
	assert.equal(racePlanGoalTimeS(plans, '2026-11-14'), null);
});

// Web-only: the phone passes these fields to PlanNewScreen directly.
test('href carries the race, its listing, the chained floor and the description', () => {
	const href = racePlanHref({
		race: RICHMOND,
		listingId: '11111111-1111-4111-8111-111111111111',
		notBeforeIso: '2026-10-08',
		describe: 'Race: x.',
	});
	const url = new URL(href, 'https://example.test');
	assert.equal(url.pathname, '/plans/new');
	assert.equal(url.searchParams.get('type'), 'training');
	assert.equal(url.searchParams.get('raceDate'), '2026-11-14');
	assert.equal(url.searchParams.get('raceName'), 'Richmond Marathon');
	assert.equal(url.searchParams.get('raceDistance'), '42195');
	assert.equal(url.searchParams.get('raceListing'), '11111111-1111-4111-8111-111111111111');
	assert.equal(url.searchParams.get('notBefore'), '2026-10-08');
	assert.equal(url.searchParams.get('describe'), 'Race: x.');
	const bare = new URL(racePlanHref({ race: { ...RICHMOND, distanceM: null } }), 'https://example.test');
	assert.equal(bare.searchParams.has('raceDistance'), false);
	assert.equal(bare.searchParams.has('raceListing'), false);
	assert.equal(bare.searchParams.has('notBefore'), false);
	assert.equal(bare.searchParams.has('describe'), false);
});
