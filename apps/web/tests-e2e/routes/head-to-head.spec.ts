import type { Download } from '@playwright/test';
import { readFile } from 'node:fs/promises';

import { expect, test } from '../fixtures/test';
import { browserDayAt } from '../fixtures/dates';
import { deleteRoute, deleteRun, insertRoute, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * The head-to-head share card (issue #1273 item 9, decisions § 2267): the
 * caller's best public attempt on a route against a mutual-follow friend's.
 * Runs against the real `head_to_head` read: runner and alex follow each
 * other in the seed, morgan follows runner both ways too but has no run on
 * this route, so the picker offers exactly one friend.
 */

const WAYPOINTS = [
	{ lat: -37.81, lng: 144.96 },
	{ lat: -37.812, lng: 144.962 },
	{ lat: -37.814, lng: 144.961 },
];

async function readPng(download: Download): Promise<{ width: number; height: number }> {
	const bytes = await readFile(await download.path());
	expect(bytes.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
	return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
}

test.describe('head-to-head card', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string;
	const runIds: string[] = [];

	test.beforeEach(async () => {
		routeId = await insertRoute({
			user_id: USER_A.id,
			name: 'Head to head loop',
			waypoints: WAYPOINTS,
			distance_m: 5_000,
			is_public: true,
		});
		runIds.push(
			await insertRun({
				user_id: USER_A.id,
				started_at: browserDayAt(-3, 7),
				distance_m: 5_000,
				duration_s: 1_900,
				is_public: true,
				route_id: routeId,
				metadata: { title: 'My loop' },
			}),
		);
	});

	test.afterEach(async () => {
		for (const id of runIds.splice(0)) await deleteRun(id);
		await deleteRoute(routeId);
	});

	test('the route page compares me with the one friend who ran it publicly, and exports the card', async ({
		page,
	}) => {
		runIds.push(
			await insertRun({
				user_id: USER_B.id,
				started_at: browserDayAt(-2, 7),
				distance_m: 5_000,
				duration_s: 1_950,
				is_public: true,
				route_id: routeId,
			}),
		);
		await page.goto(`/routes/${routeId}`);
		await page.getByTestId('route-head-to-head-open').click();
		const dialog = page.getByTestId('head-to-head-dialog');
		await expect(dialog).toBeVisible();
		const friends = dialog.getByTestId('head-to-head-friend');
		await expect(friends).toHaveCount(1, { timeout: 15_000 });
		await expect(friends.first()).toHaveAttribute('aria-checked', 'true');
		await expect(dialog.getByTestId('head-to-head-preview')).toBeVisible({ timeout: 15_000 });

		const pending = page.waitForEvent('download');
		await dialog.getByTestId('head-to-head-download').click();
		const png = await readPng(await pending);
		expect([png.width, png.height]).toEqual([1080, 1350]);
	});

	test('a friend whose only run there is private is not offered', async ({ page }) => {
		runIds.push(
			await insertRun({
				user_id: USER_B.id,
				started_at: browserDayAt(-2, 7),
				distance_m: 5_000,
				duration_s: 1_950,
				is_public: false,
				route_id: routeId,
			}),
		);
		await page.goto(`/routes/${routeId}`);
		await page.getByTestId('route-head-to-head-open').click();
		const dialog = page.getByTestId('head-to-head-dialog');
		await expect(dialog.getByTestId('head-to-head-empty')).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('head-to-head-friend')).toHaveCount(0);
	});

	test('a failed read says so and retries, distinct from having nobody to compare', async ({ page, mockRoute }) => {
		runIds.push(
			await insertRun({
				user_id: USER_B.id,
				started_at: browserDayAt(-2, 7),
				distance_m: 5_000,
				duration_s: 1_950,
				is_public: true,
				route_id: routeId,
			}),
		);
		await mockRoute(
			page,
			'**/rest/v1/rpc/head_to_head**',
			(route) => route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
			{ times: 1 },
		);
		await page.goto(`/routes/${routeId}`);
		await page.getByTestId('route-head-to-head-open').click();
		const dialog = page.getByTestId('head-to-head-dialog');
		const error = dialog.getByTestId('head-to-head-error');
		await expect(error).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('head-to-head-empty')).toHaveCount(0);
		await error.getByRole('button').click();
		await expect(dialog.getByTestId('head-to-head-friend')).toHaveCount(1, { timeout: 15_000 });
	});

	test('run detail offers the card as the Versus share style when the run is on a route', async ({ page }) => {
		runIds.push(
			await insertRun({
				user_id: USER_B.id,
				started_at: browserDayAt(-2, 7),
				distance_m: 5_000,
				duration_s: 1_800,
				is_public: true,
				route_id: routeId,
			}),
		);
		await page.goto(`/runs/${runIds[0]}`);
		await page.locator('button[title="Share image"]').click();
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog).toBeVisible({ timeout: 15_000 });
		await dialog.getByTestId('share-style-versus').click();
		await expect(dialog.getByTestId('head-to-head-friend')).toHaveCount(1, { timeout: 15_000 });
		await expect(dialog.getByTestId('head-to-head-preview')).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('share-image-download')).toHaveCount(0);
	});
});
