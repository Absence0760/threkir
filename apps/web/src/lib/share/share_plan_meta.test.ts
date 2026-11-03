import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { SharedPlan } from './share_plan_lookup';
import {
	buildPlanShareCanonical,
	buildPlanShareDescription,
	buildPlanShareTitle,
	buildSharePlanHead,
	planAuthorCredit,
	planGoalEnglish,
	renderSharePlanHeadTags,
} from './share_plan_meta';

const ID = '11111111-2222-4333-8444-555555555555';

function plan(over: Partial<SharedPlan> = {}): SharedPlan {
	return {
		id: ID,
		name: 'Spring marathon block',
		goal_event: 'distance_full',
		goal_distance_m: 42195,
		days_per_week: 5,
		author: { name: 'Creator Cat', handle: 'creatorcat' },
		weeks: [
			{ week_index: 0, phase: 'base', target_volume_m: 40000, workouts: [] },
			{ week_index: 1, phase: 'build', target_volume_m: 45000, workouts: [] },
		],
		...over,
	};
}

test('the goal reads in fixed English, with a custom distance in km', () => {
	assert.equal(planGoalEnglish(plan()), 'marathon');
	assert.equal(planGoalEnglish(plan({ goal_event: 'distance_half' })), 'half marathon');
	assert.equal(planGoalEnglish(plan({ goal_event: 'distance_5k' })), '5K');
	assert.equal(planGoalEnglish(plan({ goal_event: 'custom', goal_distance_m: 50000 })), '50 km');
	assert.equal(planGoalEnglish(plan({ goal_event: 'custom', goal_distance_m: 80467 })), '80.5 km');
	assert.equal(planGoalEnglish(plan({ goal_event: 'custom', goal_distance_m: 0 })), 'custom goal');
});

test('the author is credited by handle, then name, then not at all', () => {
	assert.equal(planAuthorCredit({ name: 'Creator Cat', handle: 'creatorcat' }), '@creatorcat');
	assert.equal(planAuthorCredit({ name: 'Creator Cat', handle: null }), 'Creator Cat');
	assert.equal(planAuthorCredit({ name: '  ', handle: '' }), null);
	assert.equal(planAuthorCredit(null), null);
});

test('title and description describe the plan without the author when private', () => {
	assert.equal(buildPlanShareTitle(plan()), 'Spring marathon block — Threkir');
	assert.equal(buildPlanShareTitle(null), 'Training plan — Threkir');
	assert.equal(
		buildPlanShareDescription(plan()),
		'A marathon plan · 2 weeks · 5 days a week · by @creatorcat. Start the same plan on Threkir.',
	);
	assert.equal(
		buildPlanShareDescription(plan({ author: null, weeks: [plan().weeks[0]] })),
		'A marathon plan · 1 week · 5 days a week. Start the same plan on Threkir.',
	);
});

test('the canonical is the /share/plan path on the normalised origin', () => {
	assert.equal(
		buildPlanShareCanonical('https://threkir.com/', ID),
		`https://threkir.com/share/plan/${ID}`,
	);
});

test('the rendered head escapes a hostile plan name', () => {
	const tags = renderSharePlanHeadTags(
		buildSharePlanHead({
			id: ID,
			plan: plan({ name: '</title><script>alert(1)</script>' }),
			siteUrl: 'https://threkir.com',
		}),
	);
	assert.ok(!tags.includes('<script>alert(1)'), 'the name must be escaped');
	assert.match(tags, /<link rel="canonical" href="https:\/\/threkir.com\/share\/plan\//);
	assert.match(tags, /og:image" content="https:\/\/threkir.com\/og-default.png"/);
});
