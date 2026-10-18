import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deletePlan, deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_B } from '../fixtures/users';

/**
 * The race page's one race-to-plan entry point (decisions § 2154).
 *
 * "Build a plan for this race" opens the deterministic wizard sized to race
 * day. With the AI plan assistant live (the e2e build sets both flags), a
 * second action carries a `describe=` built by `racePlanDescribe`; the
 * flag-off half is a source guard in `src/lib/paywall_guards.test.ts`, since
 * a Playwright run cannot unset a build-time public flag. When the runner
 * already has an active plan ending before the race, "Add to my season"
 * queues the new plan behind it plus its recovery days instead of
 * overlapping it. The plan the wizard creates links back to the listing
 * (decisions § 2156), and the plan page names the race.
 *
 * The planted plan sits a year out so no other USER_B spec's plan window can
 * be the one the page chains after.
 */

const PLAN_NAME = 'e2e raceplan base';

async function deletePlantedPlans(): Promise<void> {
	const rows = await readRows(
		'USER_B race-plan plans',
		getAdminClient().from('training_plans').select('id').eq('user_id', USER_B.id).like('name', `${PLAN_NAME}%`)
	);
	for (const row of rows) await deletePlan(row.id as string);
}

test.describe('/races/[id] — build a plan from a race', () => {
	test.describe.configure({ mode: 'serial' });
	test.use({ storageState: USER_B.storageStatePath });

	const listings: string[] = [];
	const createdPlans: string[] = [];

	test.afterEach(async () => {
		await deletePlantedPlans();
		for (const id of createdPlans.splice(0)) await deletePlan(id);
		for (const id of listings.splice(0)) {
			try {
				await deleteRaceListing(id);
			} catch (_) {
				/* best-effort */
			}
		}
	});

	test('the build action lands on the wizard sized to race day, with the race named', async ({ page }) => {
		const raceName = `E2E Race Plan ${Date.now()}`;
		const raceDate = browserDate(70);
		const id = await insertRaceListing({ provider: 'runsignup', name: raceName, race_date: raceDate, distance_m: 21_097 });
		listings.push(id);

		await page.goto(`/races/${id}`);
		const build = page.getByTestId('race-detail-train');
		await expect(build).toHaveText('Build a plan for this race');
		await build.click();

		await expect(page).toHaveURL(/\/plans\/new\?/);
		const url = new URL(page.url());
		expect(url.searchParams.get('raceDate')).toBe(raceDate);
		expect(url.searchParams.has('notBefore')).toBe(false);
		await expect(page.getByTestId('race-preset-note')).toBeVisible();
		await expect(page.getByLabel('Plan name')).toHaveValue(raceName);
		await expect(page.getByTestId('race-preset-chained')).toHaveCount(0);
	});

	test('with the assistant live, the AI action hands over a capped race description', async ({ page }) => {
		const raceName = `E2E Race Plan AI ${Date.now()}`;
		const raceDate = browserDate(70);
		const id = await insertRaceListing({ provider: 'runsignup', name: raceName, race_date: raceDate, distance_m: 42_195 });
		listings.push(id);

		await page.goto(`/races/${id}`);
		const ai = page.getByTestId('race-detail-tailor-ai');
		await expect(ai).toHaveText('Tailor it with AI');
		const href = new URL((await ai.getAttribute('href'))!, 'https://example.test');
		expect(href.pathname).toBe('/plans/new');
		const describe = href.searchParams.get('describe') ?? '';
		expect(describe.startsWith(`Race: ${raceName} on ${raceDate}. Distance: 42.2 km.`)).toBe(true);
		expect(describe.length).toBeLessThanOrEqual(600);
		expect(describe).not.toMatch(/volume|longest/i);
	});

	test('an active plan ending before the race offers "Add to my season", which starts after it', async ({ page }) => {
		const planEnd = browserDate(400);
		const { error } = await getAdminClient().from('training_plans').insert({
			id: crypto.randomUUID(),
			user_id: USER_B.id,
			name: PLAN_NAME,
			goal_event: 'distance_10k',
			goal_distance_m: 10_000,
			start_date: browserDate(360),
			end_date: planEnd,
			days_per_week: 4,
			status: 'active'
		});
		if (error) throw error;
		const raceName = `E2E Race Plan Season ${Date.now()}`;
		const id = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(480),
			distance_m: 42_195
		});
		listings.push(id);

		await page.goto(`/races/${id}`);
		const add = page.getByTestId('race-detail-add-to-season');
		await expect(add).toHaveText('Add to my season');
		await expect(page.getByTestId('race-detail-season-hint')).toContainText(PLAN_NAME);
		await expect(page.getByTestId('race-detail-season-hint')).toContainText('3 days to recover');
		await expect(page.getByTestId('race-detail-train')).toBeVisible();

		await add.click();
		await expect(page).toHaveURL(/\/plans\/new\?/);
		// A 10 km goal earns 3 recovery days: the floor is the 4th day after the end.
		const floor = browserDate(404);
		expect(new URL(page.url()).searchParams.get('notBefore')).toBe(floor);
		await expect(page.getByTestId('race-preset-chained')).toBeVisible();
		const start = await page.getByLabel('Start date').inputValue();
		expect(start >= floor).toBe(true);
		expect(new Date(`${start}T00:00:00Z`).getUTCDay()).toBe(0);
	});

	test('the plan built from a race links back to it, and the plan page names the race', async ({ page }) => {
		const raceName = `E2E Race Link ${Date.now()}`;
		const raceDate = browserDate(700);
		const id = await insertRaceListing({ provider: 'runsignup', name: raceName, race_date: raceDate, distance_m: 21_097 });
		listings.push(id);

		await page.goto(`/races/${id}`);
		await page.getByTestId('race-detail-train').click();
		await expect(page).toHaveURL(/\/plans\/new\?/);
		expect(new URL(page.url()).searchParams.get('raceListing')).toBe(id);

		const submit = page.locator('form.plan-editor').getByRole('button', { name: 'Create plan' });
		await expect(submit).toBeEnabled({ timeout: 10_000 });
		await submit.click();
		await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		const planId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];
		createdPlans.push(planId);

		const rows = await readRows(
			'race-linked plan',
			getAdminClient().from('training_plans').select('race_listing_id').eq('id', planId)
		);
		expect(rows[0]?.race_listing_id).toBe(id);

		const linked = page.getByTestId('plan-linked-race');
		await expect(linked).toContainText(raceName);
		await expect(linked).toHaveAttribute('href', `/races/${id}`);
	});
});
