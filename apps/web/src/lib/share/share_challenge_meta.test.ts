import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	buildChallengeShareDescription,
	buildShareChallengeHead,
	challengeGoalStable,
	challengeWindowStable,
	renderShareChallengeHeadTags,
} from './share_challenge_meta';
import { buildChallengeOgSvg, buildChallengeSubline } from './og_challenge_image';
import { lookupSharedChallenge } from './share_challenge_lookup';
import type { SharedChallenge } from './share_challenge_lookup';

const base: SharedChallenge = {
	id: '5f1c7e2a-0000-4000-8000-000000000001',
	title: 'Run 50 km with me',
	description: null,
	metric: 'distance',
	scope: 'individual',
	goal_value: 50000,
	starts_at: '2026-11-01T00:00:00.000Z',
	ends_at: '2026-11-30T23:00:00.000Z',
	participant_count: 12,
	creator_id: 'u-1',
};

test('the goal reads the same for every crawler, per metric', () => {
	assert.equal(challengeGoalStable(base), '50.00 km');
	assert.equal(challengeGoalStable({ metric: 'duration', goal_value: 36000 }), '10 h');
	assert.equal(challengeGoalStable({ metric: 'activity_count', goal_value: 20 }), '20 activities');
	assert.equal(challengeGoalStable({ metric: 'activity_count', goal_value: 1 }), '1 activity');
	assert.equal(challengeGoalStable({ metric: 'streak_days', goal_value: 1 }), '1 day');
	assert.equal(challengeGoalStable({ metric: 'park_courses', goal_value: 1 }), '1 park course');
	assert.equal(challengeGoalStable({ metric: 'streak_days', goal_value: 30 }), '30 days');
	assert.equal(challengeGoalStable({ metric: 'vert', goal_value: 1000 }), '1000 m');
	assert.equal(challengeGoalStable({ metric: 'distance', goal_value: null }), '');
});

test('the window and the fallback description name the goal and dates', () => {
	assert.equal(challengeWindowStable(base), '1 Nov 2026 – 30 Nov 2026');
	assert.equal(
		buildChallengeShareDescription(base),
		'A running challenge on Threkir: Goal 50.00 km · 1 Nov 2026 – 30 Nov 2026.',
	);
	assert.equal(
		buildChallengeShareDescription({ ...base, description: 'Every km counts.' }),
		'Every km counts.',
	);
});

test('the head points at the challenge card and is absolute', () => {
	const head = buildShareChallengeHead({ id: base.id, challenge: base, siteUrl: 'https://threkir.com/' });
	assert.equal(head.canonical, `https://threkir.com/share/challenge/${base.id}`);
	assert.equal(head.ogImageUrl, `https://threkir.com/og/challenge/${base.id}.png`);
	const tags = renderShareChallengeHeadTags(head);
	assert.match(tags, /twitter:card" content="summary_large_image"/);
	assert.match(tags, /"@type":"Event"/);
});

test('the card escapes the title and names no participant', () => {
	const svg = buildChallengeOgSvg({
		challenge: { ...base, title: '<script>x</script> & co' },
		creatorName: 'Cass',
	});
	assert.ok(!svg.includes('<script>'));
	assert.ok(svg.includes('&lt;script&gt;'));
	assert.equal(
		buildChallengeSubline({ challenge: base, creatorName: 'Cass' }),
		'1 Nov 2026 – 30 Nov 2026 · 12 runners in',
	);
	assert.match(svg, />by Cass<\/text>/);
	assert.equal(buildChallengeSubline({ challenge: null }), '');
	assert.ok(buildChallengeOgSvg({ challenge: null }).includes('Challenge'));
});

test('the lookup refuses a non-uuid and an unconfigured stack without a request', async () => {
	let called = false;
	const make = () => {
		called = true;
		throw new Error('no client');
	};
	assert.deepEqual(await lookupSharedChallenge('nope', { supabaseUrl: 'x', supabaseAnonKey: 'y' }, make), {
		challenge: null,
		creatorName: null,
		leaders: [],
	});
	assert.equal((await lookupSharedChallenge(base.id, null, make)).challenge, null);
	assert.equal(called, false);
});
