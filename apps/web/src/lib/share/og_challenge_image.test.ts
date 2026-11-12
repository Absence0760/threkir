import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildChallengeOgSvg, buildChallengeSubline } from './og_challenge_image';
import type { SharedChallenge } from './share_challenge_lookup';

function challenge(over: Partial<SharedChallenge> = {}): SharedChallenge {
	return {
		id: '0b9f3c2e-1111-4222-8333-944455556666',
		title: 'November 100 km',
		description: 'Private note for members',
		metric: 'distance',
		scope: 'public',
		goal_value: 100000,
		starts_at: '2026-11-01T00:00:00Z',
		ends_at: '2026-11-30T23:59:59Z',
		participant_count: 12,
		creator_id: 'c0ffee00-0000-4000-8000-000000000001',
		...over,
	};
}

test('a known challenge draws its title, goal and subline on a 1200x630 card', () => {
	const svg = buildChallengeOgSvg({ challenge: challenge(), creatorName: 'Sam' });
	assert.match(svg, /<svg [^>]*viewBox="0 0 1200 630"/);
	assert.match(svg, />November 100 km<\/text>/);
	assert.match(svg, />Goal [^<]+<\/text>/);
	assert.match(svg, /12 runners in<\/text>/);
	assert.match(svg, />by Sam<\/text>/);
	assert.match(svg.trimEnd(), /<\/svg>$/);
});

test('a missing challenge renders the generic branded card with no subline', () => {
	const svg = buildChallengeOgSvg({ challenge: null });
	assert.match(svg, />Threkir<\/text>/);
	assert.match(svg, />Challenge<\/text>/);
	assert.doesNotMatch(svg, /Goal /);
	assert.equal(buildChallengeSubline({ challenge: null }), '');
});

test('the card never carries the description, the creator id or a hidden creator name', () => {
	const c = challenge();
	const svg = buildChallengeOgSvg({ challenge: c, creatorName: null });
	assert.ok(!svg.includes(c.description!));
	assert.ok(!svg.includes(c.creator_id!));
	assert.doesNotMatch(svg, /by /);
});

test('the title and creator name are XML-escaped', () => {
	const svg = buildChallengeOgSvg({
		challenge: challenge({ title: '<script>&"x"' }),
		creatorName: 'A & <B>',
	});
	assert.ok(!svg.includes('<script>'));
	assert.match(svg, /&lt;script&gt;&amp;/);
	assert.match(svg, />by A &amp; &lt;B&gt;<\/text>/);
});

test('a single participant is singular and zero participants say nothing', () => {
	assert.match(buildChallengeSubline({ challenge: challenge({ participant_count: 1 }) }), /1 runner in/);
	assert.doesNotMatch(buildChallengeSubline({ challenge: challenge({ participant_count: 0 }) }), /runner/);
});

test('a goal-less challenge draws no goal line', () => {
	const svg = buildChallengeOgSvg({ challenge: challenge({ goal_value: null }) });
	assert.doesNotMatch(svg, /Goal /);
});
