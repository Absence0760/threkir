import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /settings/integrations — the parkrun barcode card (issue #1148).
 *
 * The card reads `parkrun_number` from the auth store, which loads it from the
 * `get_my_profile` RPC at sign-in. Each test rewrites that one field in the
 * RPC's response, so the spec never depends on what the shared seed user's
 * number happens to be while account.spec.ts is mid-edit of it.
 */

async function withParkrunNumber(page: Page, value: string | null) {
	await page.route('**/rest/v1/rpc/get_my_profile**', async (route) => {
		const response = await route.fetch();
		const body = await response.json();
		const patch = (row: Record<string, unknown>) => ({ ...row, parkrun_number: value });
		await route.fulfill({
			response,
			json: Array.isArray(body) ? body.map(patch) : patch(body),
		});
	});
}

test.describe('parkrun barcode card', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('renders the number as a scannable barcode with its text', async ({ page }) => {
		await withParkrunNumber(page, 'A123456');
		await page.goto('/settings/integrations');

		const card = page.getByTestId('parkrun-barcode-card');
		await expect(card).toBeVisible({ timeout: 10_000 });
		const code = card.getByRole('img', { name: /A123456/ });
		await expect(code).toBeVisible();
		// Code 128 set B: START + 7 characters + check + STOP = 9 × 11 + 13.
		await expect(code).toHaveAttribute('data-modules', '112');
		// One white backdrop plus a rect per bar: three bars a symbol, four in STOP.
		await expect(code.locator('rect')).toHaveCount(1 + 9 * 3 + 4);
		await expect(card.locator('figcaption')).toHaveText('A123456');
	});

	test('the full-screen view opens, and Escape returns focus to its opener', async ({ page }) => {
		await withParkrunNumber(page, 'A123456');
		await page.goto('/settings/integrations');

		const open = page.getByTestId('parkrun-barcode-fullscreen');
		await expect(open).toBeVisible({ timeout: 10_000 });
		await open.click();

		const overlay = page.getByRole('dialog', { name: /parkrun barcode/i });
		await expect(overlay).toBeVisible();
		await expect(overlay.getByTestId('parkrun-barcode-large').getByRole('img')).toBeVisible();
		await expect(page.getByTestId('parkrun-barcode-close')).toBeFocused();

		await page.keyboard.press('Escape');
		await expect(overlay).toHaveCount(0);
		await expect(open).toBeFocused();
	});

	test('the close button dismisses the full-screen view', async ({ page }) => {
		await withParkrunNumber(page, 'A123456');
		await page.goto('/settings/integrations');

		await page.getByTestId('parkrun-barcode-fullscreen').click();
		await page.getByTestId('parkrun-barcode-close').click();
		await expect(page.getByTestId('parkrun-barcode-overlay')).toHaveCount(0);
	});

	test('with no number saved it offers to add one, and draws nothing', async ({ page }) => {
		await withParkrunNumber(page, null);
		await page.goto('/settings/integrations');

		const card = page.getByTestId('parkrun-barcode-card');
		await expect(card.getByTestId('parkrun-barcode-empty')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('parkrun-barcode')).toHaveCount(0);
		await expect(card.getByRole('link', { name: 'Add athlete number' })).toHaveAttribute(
			'href',
			'/settings/account',
		);
	});

	test('a stored number outside parkrun format is not drawn as a barcode', async ({ page }) => {
		await withParkrunNumber(page, '1234 5678');
		await page.goto('/settings/integrations');

		const card = page.getByTestId('parkrun-barcode-card');
		await expect(card.getByTestId('parkrun-barcode-invalid')).toBeVisible({ timeout: 10_000 });
		await expect(card.getByTestId('parkrun-barcode')).toHaveCount(0);
	});
});
