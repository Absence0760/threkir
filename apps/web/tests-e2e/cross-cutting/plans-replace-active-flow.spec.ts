import { expect, test } from '../fixtures/test';

import { deletePlan, setPlanStatus } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /plans overlap dialog — Replace path.
 *
 * The Cancel branch is already pinned by tests-e2e/plans/create.spec.ts.
 * This saga covers the Confirm path end-to-end:
 *
 *  1. The seed's "Richmond Half 2026" card is showing as active.
 *  2. Open the New-plan wizard, fill it, click "Create plan".
 *  3. Overlap dialog appears → click "Replace plan".
 *  4. Land on /plans/<new-id>.
 *  5. Back on /plans: the new plan card has `.card-active`, and the
 *     Richmond Half card now shows the `status-abandoned` badge (the
 *     seed's plan overlapped the new window, and Replace retires the
 *     overlapping plans as abandoned — decisions § 2008, § 2075).
 *
 * The active-card-class flip is what `.card-active` encodes; absence
 * of `.card-active` on the seed card combined with a visible
 * status-abandoned badge proves the swap happened.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

test.describe('/plans — Replace active plan confirm path', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let plantedPlanId: string | null = null;

	test.afterEach(async () => {
		if (plantedPlanId) {
			try {
				await deletePlan(plantedPlanId);
			} catch (_) {
				/* best-effort */
			}
			plantedPlanId = null;
		}
		try {
			await setPlanStatus(SEED_PLAN_ID, 'active');
		} catch (_) {
			/* best-effort */
		}
	});

	test('Replace plan confirm path flips Richmond Half from active to abandoned', async ({
		page,
	}) => {
		const name = `e2e replace active ${Date.now()}`;

		await test.step('seed Richmond Half plan starts active', async () => {
			await page.goto('/plans');
			const seedCard = page.locator('.card', { hasText: 'Richmond Half 2026' });
			await expect(seedCard).toBeVisible({ timeout: 10_000 });
			await expect(seedCard).toHaveClass(/card-active/);
		});

		await test.step('open wizard, fill, submit, Replace plan', async () => {
			await page.getByRole('button', { name: /New plan/ }).first().click();
			const modal = page.locator('.modal');
			await expect(modal).toBeVisible({ timeout: 5_000 });

			await modal.getByPlaceholder('Autumn half marathon').fill(name);
			const start = new Date(Date.now() + 14 * 24 * 3600 * 1000);
			await modal
				.locator('input[type="date"]')
				.first()
				.fill(start.toISOString().slice(0, 10));

			await expect(modal.locator('.preview')).toBeVisible({ timeout: 5_000 });
			const submit = modal.getByRole('button', { name: /Create plan/ });
			await expect(submit).toBeEnabled({ timeout: 5_000 });
			await submit.click();

			const confirm = page.getByTestId('plan-overlap-dialog');
			await expect(confirm).toBeVisible({ timeout: 5_000 });
			await expect(confirm).toContainText('Richmond Half 2026');
			await confirm.getByRole('button', { name: 'Replace plan' }).click();
		});

		await test.step('land on /plans/<new-id>', async () => {
			await page.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
			plantedPlanId = page.url().match(/\/plans\/([0-9a-f-]+)$/)![1];
			await expect(
				page.getByRole('heading', { level: 1, name }),
			).toBeVisible({ timeout: 10_000 });
		});

		await test.step('back on /plans: new card active, Richmond Half flipped to abandoned', async () => {
			await page.goto('/plans');
			const newCard = page.locator('.card', { hasText: name });
			await expect(newCard).toBeVisible({ timeout: 10_000 });
			await expect(newCard).toHaveClass(/card-active/);

			const seedCard = page.locator('.card', { hasText: 'Richmond Half 2026' });
			await expect(seedCard).toBeVisible();
			await expect(seedCard).not.toHaveClass(/card-active/);
			await expect(seedCard.locator('.badge.status-abandoned')).toBeVisible();
		});
	});
});
