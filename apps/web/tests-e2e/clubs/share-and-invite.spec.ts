import { expect, test } from '../fixtures/test';

import { originOf } from '../fixtures/base-url';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /clubs/[slug] — the invite link reaches every club an admin runs, not only
 * invite-only ones, and anyone can share a public club's /share/club page.
 *
 * tempo-tuesday is seeded `join_policy = 'request'` with a null token and
 * USER_A as its owner; friends-of-jared is the private invite-only club.
 */
const TEMPO_TUESDAY_ID = 'c2222222-0000-0000-0000-000000000002';

function captureShare() {
	const w = window as unknown as { __shared?: { title: string | null; url: string | null } };
	Object.defineProperty(navigator, 'share', {
		value: async (data: { title?: string; url?: string }) => {
			w.__shared = { title: data.title ?? null, url: data.url ?? null };
		},
		configurable: true
	});
}

async function sharedPayload(page: import('@playwright/test').Page) {
	return page.evaluate(
		() => (window as unknown as { __shared?: { title: string | null; url: string | null } }).__shared ?? null
	);
}

test.describe('/clubs/[slug] — invite link for a request-to-join club', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.afterEach(async () => {
		await getAdminClient()
			.from('clubs')
			.update({ invite_token: null })
			.eq('id', TEMPO_TUESDAY_ID);
	});

	test('the admin generates a link without a confirm, then copies it', async ({
		page,
		context,
		baseURL
	}) => {
		await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
			origin: originOf(baseURL)
		});
		await page.goto('/clubs/tempo-tuesday');
		await expect(
			page.getByRole('heading', { level: 1, name: 'UVA Tempo Tuesday' })
		).toBeVisible({ timeout: 10_000 });

		const card = page.getByTestId('club-invite-card');
		await expect(card).toBeVisible();
		await expect(card).toContainText('without waiting for approval');

		await card.getByRole('button', { name: 'Generate invite link' }).click();
		await expect(page.locator('.modal', { hasText: 'Regenerate invite link' })).toHaveCount(0);

		const link = card.locator('code.invite-link');
		await expect(link).toContainText('/clubs/join/', { timeout: 5_000 });

		const { data } = await getAdminClient()
			.from('clubs')
			.select('invite_token')
			.eq('id', TEMPO_TUESDAY_ID)
			.single();
		const token = (data as { invite_token: string | null } | null)?.invite_token;
		expect(token).toBeTruthy();
		await expect(link).toHaveText(`${originOf(baseURL)}/clubs/join/${token}`);

		await card.getByRole('button', { name: 'Copy' }).click();
		await expect(page.locator('.toast-success')).toContainText('Invite link copied');
		expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
			`${originOf(baseURL)}/clubs/join/${token}`
		);
	});

	test('the admin hands the link to the share sheet', async ({ page, baseURL }) => {
		await getAdminClient()
			.from('clubs')
			.update({ invite_token: 'e2esharetoken0000000000000000aa' })
			.eq('id', TEMPO_TUESDAY_ID);
		await page.addInitScript(captureShare);
		await page.goto('/clubs/tempo-tuesday');

		await page.getByTestId('club-invite-card').getByRole('button', { name: 'Share' }).click();
		await expect.poll(() => sharedPayload(page), { timeout: 5_000 }).toEqual({
			title: 'UVA Tempo Tuesday',
			url: `${originOf(baseURL)}/clubs/join/e2esharetoken0000000000000000aa`
		});
	});
});

test.describe('/clubs/[slug] — public share', () => {
	test.describe('signed out', () => {
		test.use({ storageState: { cookies: [], origins: [] } });

		test('any viewer shares the public club page', async ({ page, baseURL }) => {
			await page.addInitScript(captureShare);
			await page.goto('/clubs/richmond-run-club');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Richmond Run Club' })
			).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('club-invite-card')).toHaveCount(0);

			await page.getByRole('button', { name: 'Share club' }).click();
			await expect.poll(() => sharedPayload(page), { timeout: 5_000 }).toEqual({
				title: 'Richmond Run Club',
				url: `${originOf(baseURL)}/share/club/richmond-run-club`
			});
		});

		test('without a share sheet the link is copied', async ({ page, context, baseURL }) => {
			await context.grantPermissions(['clipboard-read', 'clipboard-write'], {
				origin: originOf(baseURL)
			});
			await page.addInitScript(() => {
				Object.defineProperty(navigator, 'share', { value: undefined, configurable: true });
			});
			await page.goto('/clubs/richmond-run-club');
			await page.getByRole('button', { name: 'Share club' }).click();
			await expect(page.locator('.toast-success')).toContainText('Club link copied');
			expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
				`${originOf(baseURL)}/share/club/richmond-run-club`
			);
		});
	});

	test.describe('private club', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('offers its admin the invite link but no public share', async ({ page }) => {
			await page.goto('/clubs/friends-of-jared');
			await expect(
				page.getByRole('heading', { level: 1, name: 'Friends of Jared' })
			).toBeVisible({ timeout: 10_000 });
			await expect(page.getByTestId('club-invite-card')).toContainText(
				'Only people with this link can join.'
			);
			await expect(page.getByRole('button', { name: 'Share club' })).toHaveCount(0);
		});
	});
});
