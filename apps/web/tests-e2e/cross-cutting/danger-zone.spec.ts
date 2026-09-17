import { expect, test, type Page } from '@playwright/test';

import { readMaybeRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Deleting a whole entity — a club, a challenge, the account — is never a
 * primary action (#902 §6). `/clubs/[slug]` used to put Delete club in the
 * header's primary slot directly above New event, and `/challenges/[id]` put a
 * bare Delete beside Leave and Edit challenge. Each now sits in a
 * `DangerZone` after the page's content, named for what it deletes, and still
 * asks before it does anything. A Cancel is asserted to be a no-op on every
 * surface; the confirmed deletes themselves are pinned by
 * clubs/detail.spec.ts, challenges/club-admin-manage.spec.ts and the account
 * erasure journey.
 */

const RICHMOND_SLUG = 'richmond-run-club';

async function followsContent(page: Page, contentSelector: string): Promise<boolean> {
	return page.evaluate((selector) => {
		const content = document.querySelector(selector);
		const zone = document.querySelector('section.danger-zone');
		if (!content || !zone) return false;
		return (content.compareDocumentPosition(zone) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
	}, contentSelector);
}

test.describe('destructive deletes live in a danger zone', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/clubs/[slug]: Delete club is out of the header and asks first', async ({ page }) => {
		await page.goto(`/clubs/${RICHMOND_SLUG}`);
		await expect(page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })).toBeVisible({
			timeout: 10_000
		});

		await expect(page.locator('.hero-actions').getByRole('button', { name: 'New event' })).toBeVisible();
		await expect(page.locator('.hero-actions').getByRole('button', { name: /Delete/ })).toHaveCount(0);

		const zone = page.getByRole('region', { name: 'Danger zone' });
		await expect(zone).toContainText('removes all of its events, posts and members');
		expect(await followsContent(page, '[role="tablist"]')).toBe(true);

		await zone.getByRole('button', { name: 'Delete club' }).click();
		const dialog = page.getByRole('dialog', { name: 'Delete club' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);

		const club = await readMaybeRow(
			'the club after Cancel',
			getAdminClient().from('clubs').select('id').eq('slug', RICHMOND_SLUG).maybeSingle()
		);
		expect(club).not.toBeNull();
	});

	test('/challenges/[id]: Delete challenge is separated from Leave and Edit, and asks first', async ({
		page
	}) => {
		const admin = getAdminClient();
		const now = Date.now();
		const { data, error } = await admin
			.from('challenges')
			.insert({
				creator_id: USER_A.id,
				title: `e2e-danger-zone ${now}`,
				metric: 'distance',
				scope: 'individual',
				goal_value: 50_000,
				starts_at: new Date(now - 86_400_000).toISOString(),
				ends_at: new Date(now + 7 * 86_400_000).toISOString()
			})
			.select('id')
			.single();
		if (error) throw new Error(error.message);
		const challengeId = (data as { id: string }).id;
		try {
			await page.goto(`/challenges/${challengeId}`);
			await expect(page.getByRole('button', { name: 'Edit challenge' })).toBeVisible({ timeout: 10_000 });

			await expect(page.locator('.cta-row').getByRole('button', { name: /Delete/ })).toHaveCount(0);

			const zone = page.getByRole('region', { name: 'Danger zone' });
			await expect(zone).toContainText('its leaderboard for everyone who joined');
			expect(await followsContent(page, '.board')).toBe(true);

			await zone.getByRole('button', { name: 'Delete challenge' }).click();
			const dialog = page.getByRole('dialog', { name: 'Delete challenge?' });
			await expect(dialog).toBeVisible({ timeout: 5_000 });
			await dialog.getByRole('button', { name: 'Cancel' }).click();
			await expect(dialog).toHaveCount(0);

			const still = await readMaybeRow(
				'the challenge after Cancel',
				admin.from('challenges').select('id').eq('id', challengeId).maybeSingle()
			);
			expect(still).not.toBeNull();
		} finally {
			await admin.from('challenges').delete().eq('id', challengeId);
		}
	});

	test('/settings/account: Delete Account keeps its danger zone and asks first', async ({ page }) => {
		await page.goto('/settings/account');

		const zone = page.getByRole('region', { name: 'Danger Zone' });
		await expect(zone).toContainText('This cannot be undone', { timeout: 10_000 });

		await zone.getByRole('button', { name: 'Delete Account' }).click();
		const dialog = page.getByRole('dialog', { name: 'Delete your account?' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });
		await dialog.getByRole('button', { name: 'Cancel' }).click();
		await expect(dialog).toHaveCount(0);
	});
});
