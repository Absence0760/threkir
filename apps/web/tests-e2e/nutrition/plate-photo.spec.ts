import { expect, test } from '../fixtures/mock-route';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * /nutrition/log — "Log from a photo" (decisions § 1972).
 *
 * `/api/coach/plate-photo` is mocked at the network layer, so no Anthropic key
 * is needed: the endpoint's gates (v5 consent, Pro, the throttle, the forced
 * tool call, the clamp) are unit-tested in
 * `src/lib/nutrition/plate_photo/*.test.ts`. Here we pin the page wiring: the
 * picture is re-encoded to a JPEG before it leaves, nothing is written until
 * the runner saves, an edit and a removal are honoured, and each refusal shows
 * its own state with the manual composer still there.
 */

// A real 2×2 PNG, so the browser's decode → canvas → JPEG path runs for real.
const PNG_2X2 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGM4UaFxokKDAUIBACnuBaHpn/lZAAAAAElFTkSuQmCC',
	'base64',
);
const MARK = '[e2e-plate]';

async function cleanup() {
	await getAdminClient().from('food_log').delete().eq('user_id', USER_A.id).like('item_name', `%${MARK}%`);
}

test.describe('/nutrition/log — plate photo', () => {
	test.use({ storageState: USER_A.storageStatePath });
	test.beforeEach(cleanup);
	test.afterEach(cleanup);

	async function pick(page: import('@playwright/test').Page) {
		await page.goto('/nutrition/log');
		const panel = page.getByTestId('plate-photo');
		await expect(panel).toBeVisible({ timeout: 10_000 });
		await panel.getByTestId('plate-photo-file').setInputFiles({
			name: 'dinner.png',
			mimeType: 'image/png',
			buffer: PNG_2X2,
		});
		return panel;
	}

	test('estimates, lets the runner edit and remove, and saves only what is kept', async ({ page, mockRoute }) => {
		const seen: { body: { image?: string; media_type?: string; note?: string } | null } = { body: null };
		await mockRoute(page, '**/api/coach/plate-photo', async (route) => {
			seen.body = route.request().postDataJSON();
			await route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({
					meal_slot: 'dinner',
					items: [
						{ item_name: `Rice ${MARK}`, confidence: 'high', calories: 205, protein_g: 4.3, carbs_g: 44.5, fat_g: 0.4 },
						{ item_name: `Salmon ${MARK}`, confidence: 'low', calories: 367, protein_g: 39, carbs_g: 0, fat_g: 22 },
						{ item_name: `Napkin ${MARK}`, confidence: 'low', calories: null, protein_g: null, carbs_g: null, fat_g: null },
					],
				}),
			});
		});

		const panel = await pick(page);
		await panel.getByLabel('Note (optional)').fill('half portion');
		await panel.getByTestId('plate-photo-estimate').click();

		const items = panel.getByTestId('plate-photo-item');
		await expect(items).toHaveCount(3, { timeout: 10_000 });
		await expect(panel.getByTestId('plate-photo-slot')).toHaveValue('dinner');

		// The upload is a JPEG re-encode, whatever the runner picked.
		expect(seen.body?.media_type).toBe('image/jpeg');
		expect(Buffer.from(seen.body?.image ?? '', 'base64').subarray(0, 3)).toEqual(Buffer.from([0xff, 0xd8, 0xff]));
		expect(seen.body?.note).toBe('half portion');

		// Nothing is written before the runner saves.
		const before = await getAdminClient()
			.from('food_log')
			.select('id', { count: 'exact', head: true })
			.eq('user_id', USER_A.id)
			.like('item_name', `%${MARK}%`);
		expect(before.count).toBe(0);

		await panel.getByRole('button', { name: `Remove Napkin ${MARK}` }).click();
		await expect(items).toHaveCount(2);
		await items.nth(1).getByLabel('kcal').fill('300');

		await panel.getByTestId('plate-photo-save').click();
		await page.waitForURL('**/nutrition', { timeout: 10_000 });

		const { data } = await getAdminClient()
			.from('food_log')
			.select('item_name, calories, meal_slot')
			.eq('user_id', USER_A.id)
			.like('item_name', `%${MARK}%`)
			.order('item_name');
		expect(data).toEqual([
			{ item_name: `Rice ${MARK}`, calories: 205, meal_slot: 'dinner' },
			{ item_name: `Salmon ${MARK}`, calories: 300, meal_slot: 'dinner' },
		]);
	});

	for (const [label, status, body, text] of [
		['the updated disclosure', 403, { error: 'ai disclosure required', code: 'ai_disclosure_required', required_version: 5 }, 'needs the updated AI disclosure'],
		['Pro', 403, { error: 'pro required', upgrade: true }, 'is a Pro feature'],
		['the hourly limit', 429, { error: 'rate_limited' }, 'a lot of photos this hour'],
		['an outage', 503, { error: 'plate photo unavailable' }, "isn't available right now"],
	] as const) {
		test(`a refusal for ${label} says so and leaves the manual composer`, async ({ page, mockRoute }) => {
			await mockRoute(page, '**/api/coach/plate-photo', (route) =>
				route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) }),
			);
			const panel = await pick(page);
			await panel.getByTestId('plate-photo-estimate').click();
			await expect(panel.getByTestId('plate-photo-error')).toContainText(text, { timeout: 10_000 });
			await expect(page.getByTestId('meal-slot')).toBeVisible();
		});
	}
});
