import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { acceptCookieConsent } from '../fixtures/helpers';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * Park courses, phase 5 (issue #1313, decisions § 2404 / § 2405): one park
 * course effort awards the first-course badge, shows on the recap's park
 * card and list, and counts on a regional park_courses challenge.
 *
 * Awards are durable, so the runner is a saga user (deleted with every award
 * at the end) rather than a seeded account a sibling spec reads badges from.
 */

const uniq = () => `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

test('one park course: the badge, the recap card and the regional challenge', async ({ browser }) => {
	const admin = getAdminClient();
	const tag = uniq();
	const [runner] = (await createSagaUsers(1, { displayNames: ['Park Collector'] })) as [SagaUser];
	let parkId: string | null = null;
	let segmentId: string | null = null;
	let challengeId: string | null = null;
	try {
		const parkName = `E2E Collection Park ${tag}`;
		const { data: seg, error: segErr } = await admin
			.from('global_segments')
			.insert({
				name: `E2E Collection Loop ${tag}`,
				waypoints: [
					{ lat: 37.31, lng: -78.1 },
					{ lat: 37.319, lng: -78.1 },
				],
				distance_m: 1000,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (segErr) throw segErr;
		segmentId = seg.id;
		const { data: park, error: parkErr } = await admin
			.from('parks')
			.insert({
				slug: `e2e-collection-${tag}`,
				name: parkName,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (parkErr) throw parkErr;
		parkId = park.id;
		const { error: courseErr } = await admin.from('park_courses').insert({
			park_id: park.id,
			global_segment_id: seg.id,
			slug: 'loop',
			course_shape: 'loop',
			geometry_source: 'osm',
		});
		if (courseErr) throw courseErr;

		const now = new Date();
		const { data: challenge, error: chErr } = await admin
			.from('challenges')
			.insert({
				creator_id: runner.id,
				title: `E2E park passport ${tag}`,
				metric: 'park_courses',
				scope: 'individual',
				goal_value: 3,
				is_public: true,
				park_region_code: 'US-VA',
				starts_at: new Date(now.getTime() - 7 * 86_400_000).toISOString(),
				ends_at: new Date(now.getTime() + 7 * 86_400_000).toISOString(),
			})
			.select('id')
			.single();
		if (chErr) throw chErr;
		challengeId = challenge.id;
		const { error: joinErr } = await admin
			.from('challenge_participants')
			.insert({ challenge_id: challenge.id, user_id: runner.id });
		if (joinErr) throw joinErr;

		const startedAt = new Date(now.getTime() - 60 * 60 * 1000).toISOString();
		const runId = await insertRun({
			user_id: runner.id,
			started_at: startedAt,
			duration_s: 900,
			distance_m: 1000,
			is_public: true,
		});
		const { error: effortErr } = await admin.from('global_segment_efforts').insert({
			global_segment_id: seg.id,
			run_id: runId,
			user_id: runner.id,
			time_seconds: 840,
			started_at: startedAt,
		});
		if (effortErr) throw effortErr;

		const ctx = await browser.newContext({ storageState: runner.storageStatePath });
		await acceptCookieConsent(ctx);
		const page = await ctx.newPage();

		await test.step('the effort awards the first park course badge', async () => {
			await page.goto(`/u/${runner.id}?tab=achievements`);
			await expect(page.getByText('First park course')).toBeVisible();
		});

		await test.step('the recap counts the course and lists its park', async () => {
			await page.goto(`/recap/${now.getUTCFullYear()}`);
			await expect(page.getByTestId('recap-park-courses')).toContainText('in 1 park');
			await expect(page.getByTestId('recap-parks')).toContainText(parkName);
		});

		await test.step('the regional challenge names its region and counts the course', async () => {
			await page.goto(`/challenges/${challenge.id}`);
			await expect(page.getByTestId('challenge-park-region')).toHaveText('Counts park courses in US-VA');
			await expect(page.getByText(/1 course\b/).first()).toBeVisible();
		});
		await ctx.close();
	} finally {
		if (challengeId) await admin.from('challenges').delete().eq('id', challengeId).then(() => {}, () => {});
		if (parkId) await admin.from('parks').delete().eq('id', parkId).then(() => {}, () => {});
		if (segmentId) await admin.from('global_segments').delete().eq('id', segmentId).then(() => {}, () => {});
		await deleteSagaUsers([runner]);
	}
});
