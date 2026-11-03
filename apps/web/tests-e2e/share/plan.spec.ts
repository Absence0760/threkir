import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /share/plan/[id] — the "Train with me" page for a public-library plan
 * (decisions § 2262).
 *
 * A public plan's tables are signed-in only, so the page reads the redacted
 * `public_plan_share` RPC: goal, weeks and workouts by day offset, never the
 * publisher's notes, paces or dates. A plan that is not public 404s. The
 * `public_plan_share` gate is opened by seed.sql for local + CI.
 */

const stamp = Date.now();
const NAME = `E2E Train with me ${stamp}`;
const SECRET = `publisher-only note ${stamp}`;

let publicId: string | null = null;
let privateId: string | null = null;

test.beforeAll(async () => {
	const admin = getAdminClient();
	const { data: pub, error } = await admin
		.from('training_plans')
		.insert({
			user_id: USER_A.id,
			name: NAME,
			goal_event: 'distance_full',
			goal_distance_m: 42195,
			start_date: '2026-03-02',
			end_date: '2026-03-15',
			days_per_week: 4,
			status: 'completed',
			is_template: true,
			is_public_template: true,
		})
		.select('id')
		.single();
	if (error) throw error;
	publicId = (pub as { id: string }).id;
	const { data: week, error: weekErr } = await admin
		.from('plan_weeks')
		.insert({ plan_id: publicId, week_index: 0, phase: 'base', target_volume_m: 20000, notes: SECRET })
		.select('id')
		.single();
	if (weekErr) throw weekErr;
	const { error: woErr } = await admin.from('plan_workouts').insert([
		{
			week_id: (week as { id: string }).id,
			scheduled_date: '2026-03-03',
			kind: 'easy',
			target_distance_m: 8000,
			target_pace_sec_per_km: 330,
			notes: SECRET,
		},
		{
			week_id: (week as { id: string }).id,
			scheduled_date: '2026-03-05',
			kind: 'tempo',
			target_distance_m: 10000,
			notes: null,
		},
	]);
	if (woErr) throw woErr;

	const { data: priv, error: privErr } = await admin
		.from('training_plans')
		.insert({
			user_id: USER_A.id,
			name: `${NAME} (private)`,
			goal_event: 'distance_10k',
			goal_distance_m: 10000,
			start_date: '2026-03-02',
			end_date: '2026-03-15',
			days_per_week: 3,
			status: 'completed',
			is_template: true,
			is_public_template: false,
		})
		.select('id')
		.single();
	if (privErr) throw privErr;
	privateId = (priv as { id: string }).id;
});

test.afterAll(async () => {
	const admin = getAdminClient();
	for (const id of [publicId, privateId]) {
		if (id) await admin.from('training_plans').delete().eq('id', id);
	}
});

test.describe('/share/plan/[id] — anon', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a signed-out reader sees the weeks and a start call to action through signup', async ({
		page,
	}) => {
		await page.goto(`/share/plan/${publicId}`);
		await expect(page.getByRole('heading', { name: NAME })).toBeVisible({ timeout: 10_000 });
		const weeks = page.getByTestId('share-plan-weeks');
		await expect(weeks).toContainText('Week 1');
		await expect(weeks).toContainText('2 runs');
		await weeks.locator('summary').first().click();
		await expect(weeks).toContainText('Day 2');
		await expect(weeks).toContainText('Day 4');
		await expect(page.getByText(SECRET)).toHaveCount(0);
		await expect(page.getByTestId('share-plan-start')).toHaveAttribute(
			'href',
			`/login?signup=1&return_to=${encodeURIComponent(`/plans/library/${publicId}`)}`,
		);
	});

	test('a plan that is not public 404s to the not-found card', async ({ page }) => {
		await page.goto(`/share/plan/${privateId}`);
		await expect(page.getByText('Training plan not found.')).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('share-plan-weeks')).toHaveCount(0);
	});

	test('the head carries the canonical, an English description and JSON-LD', async ({ page }) => {
		await page.goto(`/share/plan/${publicId}`);
		await expect(page).toHaveTitle(`${NAME} — Threkir`);
		await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
			'href',
			new RegExp(`/share/plan/${publicId}$`),
		);
		const desc = await page.locator('meta[property="og:description"]').getAttribute('content');
		expect(desc).toContain('A marathon plan · 1 week · 4 days a week');
		expect(desc).not.toContain(SECRET);
		const jsonLd = await page.locator('script[type="application/ld+json"]').last().textContent();
		expect(JSON.parse(jsonLd ?? '{}')['@type']).toBe('WebPage');
	});
});

test.describe('/share/plan/[id] — signed in', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the start call to action opens the in-app preview directly', async ({ page }) => {
		await page.goto(`/share/plan/${publicId}`);
		await expect(page.getByTestId('share-plan-start')).toHaveAttribute(
			'href',
			`/plans/library/${publicId}`,
			{ timeout: 10_000 },
		);
	});
});
