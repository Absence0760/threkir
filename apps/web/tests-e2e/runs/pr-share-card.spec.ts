import type { Download } from '@playwright/test';
import { readFile } from 'node:fs/promises';

import { expect, test } from '../fixtures/test';
import { browserDayAt } from '../fixtures/dates';
import { readCount, readMaybeRow, readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import type { TrackPoint } from '../../src/lib/types';

/**
 * The PR card (issue #1273 item 7, decisions § 2266): a run that beats the
 * runner's personal_records cache raises one `personal_record` notification,
 * logs what it beat, and offers a PR style in the share editor — opened from
 * the run's toolbar and from the notification's `?share=pr` link. The record
 * times stay owner-only; only the exported PNG leaves.
 *
 * Two 12K runs, each faster than the last: the times are derived from the
 * 12K best the seed holds, as personal-records-journey derives its 5K, so a
 * faster seed run can never out-rank them.
 */

const TRACK: TrackPoint[] = Array.from({ length: 8 }, (_, i) => ({
	lat: -37.8 + i * 0.001,
	lng: 144.96 + (i % 2) * 0.0008,
	ts: new Date(Date.UTC(2026, 4, 10, 8, i)).toISOString(),
}));

async function pngSize(download: Download): Promise<[number, number]> {
	const bytes = await readFile(await download.path());
	expect(bytes.subarray(0, 8).toString('hex')).toBe('89504e470d0a1a0a');
	return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

test.describe('PR share card', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let earlier: string;
	let improved: string;
	let seedBest: number;
	let seedHeld: boolean;
	test.beforeEach(async () => {
		const data = await readMaybeRow(
			'personal_records 12k for USER_A',
			getAdminClient()
				.from('personal_records')
				.select('best_time_s')
				.eq('user_id', USER_A.id)
				.eq('distance', '12k')
				.maybeSingle(),
		);
		seedHeld = data != null;
		seedBest = (data?.best_time_s as number | undefined) ?? 3000;
		earlier = await insertRun({
			user_id: USER_A.id,
			started_at: browserDayAt(-3, 7),
			distance_m: 12_000,
			duration_s: seedBest - 60,
			metadata: { title: 'Earlier 12K' },
			track: TRACK,
		});
		improved = await insertRun({
			user_id: USER_A.id,
			started_at: browserDayAt(-1, 7),
			distance_m: 12_000,
			duration_s: seedBest - 120,
			metadata: { title: 'Faster 12K' },
			track: TRACK,
		});
	});
	test.afterEach(async () => {
		await deleteRun(improved);
		await deleteRun(earlier);
	});

	test('each faster run logs what it beat and raises one notification', async () => {
		const admin = getAdminClient();
		const logged = await readRows(
			'personal_record_improvements for the two runs',
			admin
				.from('personal_record_improvements')
				.select('run_id, best_time_s, previous_time_s')
				.in('run_id', [earlier, improved])
				.order('best_time_s'),
		);
		expect(logged).toEqual([
			{ run_id: improved, best_time_s: seedBest - 120, previous_time_s: seedBest - 60 },
			{ run_id: earlier, best_time_s: seedBest - 60, previous_time_s: seedHeld ? seedBest : null },
		]);
		const count = await readCount(
			'personal_record notifications for the two runs',
			admin
				.from('notifications')
				.select('id', { count: 'exact', head: true })
				.eq('kind', 'personal_record')
				.in('run_id', [earlier, improved]),
		);
		expect(count).toBe(2);
	});

	test('run detail offers the PR card, which exports at the chosen aspect', async ({ page }) => {
		await page.goto(`/runs/${improved}`);
		await page.getByTestId('run-share-pr').click();
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('share-style-pr')).toHaveAttribute('aria-checked', 'true');
		// The card has no layout or stat picker of its own; colour and size it has.
		await expect(dialog.getByTestId('share-layout-stack')).toHaveCount(0);
		await expect(dialog.getByTestId('share-stat-distance')).toHaveCount(0);
		await expect(dialog.getByTestId('share-ink-dark')).toBeVisible();

		await dialog.getByTestId('share-aspect-post').click();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		let pending = page.waitForEvent('download');
		await dialog.getByTestId('share-image-download').click();
		expect(await pngSize(await pending)).toEqual([1080, 1350]);

		await dialog.getByTestId('share-aspect-story').click();
		await expect(dialog.getByTestId('share-image-download')).toBeEnabled({ timeout: 15_000 });
		pending = page.waitForEvent('download');
		await dialog.getByTestId('share-image-download').click();
		expect(await pngSize(await pending)).toEqual([1080, 1920]);
	});

	test('the notification opens the run on its PR card', async ({ page }) => {
		await page.goto(`/u/${USER_A.id}?tab=notifications`);
		const row = page
			.locator('.item-wrap')
			.filter({ hasText: 'You set a new personal record' })
			.first();
		await expect(row).toBeVisible({ timeout: 15_000 });
		await row.locator('.item-main').click();
		await page.waitForURL(/\/runs\/[0-9a-f-]+\?share=pr$/, { timeout: 10_000 });
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('share-style-pr')).toHaveAttribute('aria-checked', 'true');
	});

	test('a run that set no record offers no PR card, even when asked for one', async ({ page }) => {
		const slow = await insertRun({
			user_id: USER_A.id,
			started_at: browserDayAt(0, 6),
			distance_m: 12_000,
			duration_s: seedBest + 600,
			metadata: { title: 'Slow 12K' },
			track: TRACK,
		});
		try {
			await page.goto(`/runs/${slow}?share=pr`);
			await expect(page.locator('button[title="Share image"]')).toBeVisible({ timeout: 15_000 });
			await expect(page.getByTestId('run-share-pr')).toHaveCount(0);
			await expect(page.getByTestId('run-share-image-dialog')).toBeHidden();
			await page.locator('button[title="Share image"]').click();
			const dialog = page.getByTestId('run-share-image-dialog');
			await expect(dialog.getByTestId('share-style-card')).toHaveAttribute('aria-checked', 'true');
			await expect(dialog.getByTestId('share-style-pr')).toHaveCount(0);
		} finally {
			await deleteRun(slow);
		}
	});

	test('a failed record read leaves the share editor working without the PR card', async ({
		page,
		mockRoute,
	}) => {
		await mockRoute(page, '**/rest/v1/personal_record_improvements*', (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
		);
		await page.goto(`/runs/${improved}`);
		await expect(page.locator('button[title="Share image"]')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('run-share-pr')).toHaveCount(0);
		await page.locator('button[title="Share image"]').click();
		const dialog = page.getByTestId('run-share-image-dialog');
		await expect(dialog.getByTestId('share-image-preview')).toBeVisible({ timeout: 15_000 });
		await expect(dialog.getByTestId('share-style-pr')).toHaveCount(0);
	});
});
