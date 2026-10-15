import { expect, test } from '../fixtures/test';

import { readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Runners' photos on /share/race/[id] (#1150, decisions § 1961).
 *
 * A photo reaches the public, logged-out race page only when its owner opted
 * it in AND its run is public AND linked to the listing AND the thumbnail is
 * processed. The owner opts in from /runs/[id]; a private run's toggle is
 * disabled, and a photo nobody opted in never shows.
 */

const PNG_1X1 = Buffer.from(
	'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
	'base64'
);

const RACE_DAY = '2027-05-09';

let listingId: string | null = null;
const runIds: string[] = [];
const storagePaths: string[] = [];

test.beforeAll(async () => {
	const { data, error } = await getAdminClient()
		.from('race_listings')
		.insert({
			provider: 'manual',
			name: `E2E Photo 10K ${Date.now()}`,
			race_date: RACE_DAY,
			distance_m: 10000,
			location_label: 'Leeds, UK',
			is_verified: true
		})
		.select('id')
		.single();
	expect(error).toBeNull();
	listingId = (data as { id: string }).id;
});

test.afterAll(async () => {
	const admin = getAdminClient();
	for (const id of runIds) {
		try {
			await deleteRun(id);
		} catch (_) {
			/* best-effort */
		}
	}
	if (storagePaths.length > 0) await admin.storage.from('run-photos').remove(storagePaths);
	if (listingId) await admin.from('race_listings').delete().eq('id', listingId);
});

/// A linked run of USER_A's with one processed photo (thumbnail present), as
/// the photo_process worker would leave it.
async function seedLinkedRunWithPhoto(opts: {
	isPublic: boolean;
	caption: string;
	raceGallery?: boolean;
}): Promise<{ runId: string; photoId: string }> {
	const admin = getAdminClient();
	const runId = await insertRun({
		user_id: USER_A.id,
		started_at: `${RACE_DAY}T09:00:00.000Z`,
		duration_s: 2700,
		distance_m: 10000,
		is_public: opts.isPublic
	});
	runIds.push(runId);
	const { error: linkError } = await admin
		.from('runs')
		.update({ race_listing_id: listingId })
		.eq('id', runId);
	expect(linkError).toBeNull();

	const photoId = crypto.randomUUID();
	const original = `${USER_A.id}/${photoId}.png`;
	const thumb = `${USER_A.id}/${photoId}_512.png`;
	for (const path of [original, thumb]) {
		await admin.storage
			.from('run-photos')
			.upload(path, PNG_1X1, { contentType: 'image/png', upsert: true });
		storagePaths.push(path);
	}
	const { error } = await admin.from('run_photos').insert({
		id: photoId,
		run_id: runId,
		owner_id: USER_A.id,
		storage_path: original,
		thumb_512_path: thumb,
		caption: opts.caption,
		position_idx: 0
	});
	expect(error).toBeNull();
	if (opts.raceGallery) {
		const { error: optError } = await admin
			.from('run_photos')
			.update({ race_gallery: true })
			.eq('id', photoId);
		expect(optError).toBeNull();
	}
	return { runId, photoId };
}

test.describe('owner', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('opts a public linked run photo in; it shows on the race page logged out', async ({
		page,
		browser
	}) => {
		const caption = `e2e race photo ${Date.now()}`;
		const { runId, photoId } = await seedLinkedRunWithPhoto({ isPublic: true, caption });

		await page.goto(`/runs/${runId}`);
		const toggle = page.locator('.tile').first().getByRole('checkbox', { name: 'Show on race page' });
		await expect(toggle).toBeVisible({ timeout: 15_000 });
		await expect(toggle).toBeEnabled();
		await expect(page.getByTestId('race-gallery-hint')).toContainText('The race page is public');
		await toggle.check();

		await expect
			.poll(
				async () =>
					(
						await readRow(
							'run_photos.race_gallery by id',
							getAdminClient().from('run_photos').select('race_gallery').eq('id', photoId).single()
						)
					).race_gallery,
				{ timeout: 15_000 }
			)
			.toBe(true);

		const anon = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		try {
			const anonPage = await anon.newPage();
			await anonPage.goto(`/share/race/${listingId}`);
			const gallery = anonPage.getByTestId('race-photos');
			await expect(gallery).toBeVisible({ timeout: 15_000 });
			await expect(gallery.getByRole('heading', { name: "Runners' photos" })).toBeVisible();
			await expect(gallery.getByText(caption)).toBeVisible();
			// The thumbnail is what the page shows; the original never reaches it.
			const src = await gallery.locator('img').first().getAttribute('src');
			expect(src).toContain('_512.png');
		} finally {
			await anon.close();
		}
	});

	test('withdraws a shared photo; it leaves the race page', async ({ page, browser }) => {
		const caption = `e2e race photo withdrawn ${Date.now()}`;
		const { runId, photoId } = await seedLinkedRunWithPhoto({
			isPublic: true,
			caption,
			raceGallery: true
		});

		await page.goto(`/runs/${runId}`);
		const toggle = page.locator('.tile').first().getByRole('checkbox', { name: 'Show on race page' });
		await expect(toggle).toBeChecked({ timeout: 15_000 });
		await toggle.uncheck();

		await expect
			.poll(
				async () =>
					(
						await readRow(
							'run_photos.race_gallery by id',
							getAdminClient().from('run_photos').select('race_gallery').eq('id', photoId).single()
						)
					).race_gallery,
				{ timeout: 15_000 }
			)
			.toBe(false);

		const anon = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		try {
			const anonPage = await anon.newPage();
			const galleryRead = anonPage.waitForResponse((r) =>
				r.url().includes('/rest/v1/rpc/race_listing_photos')
			);
			await anonPage.goto(`/share/race/${listingId}`);
			await expect(anonPage.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
			expect((await galleryRead).ok()).toBe(true);
			await expect(anonPage.getByText(caption)).toHaveCount(0);
		} finally {
			await anon.close();
		}
	});

	test('a shared photo on a private run can still be withdrawn', async ({ page }) => {
		const { runId, photoId } = await seedLinkedRunWithPhoto({
			isPublic: false,
			caption: `e2e private withdraw ${Date.now()}`,
			raceGallery: true
		});

		await page.goto(`/runs/${runId}`);
		const toggle = page.locator('.tile').first().getByRole('checkbox', { name: 'Show on race page' });
		await expect(toggle).toBeChecked({ timeout: 15_000 });
		await expect(toggle).toBeEnabled();
		await toggle.uncheck();

		await expect
			.poll(
				async () =>
					(
						await readRow(
							'run_photos.race_gallery by id',
							getAdminClient().from('run_photos').select('race_gallery').eq('id', photoId).single()
						)
					).race_gallery,
				{ timeout: 15_000 }
			)
			.toBe(false);
	});

	test('a private run disables the toggle and explains why', async ({ page }) => {
		const { runId } = await seedLinkedRunWithPhoto({
			isPublic: false,
			caption: `e2e private ${Date.now()}`
		});

		await page.goto(`/runs/${runId}`);
		const toggle = page.locator('.tile').first().getByRole('checkbox', { name: 'Show on race page' });
		await expect(toggle).toBeVisible({ timeout: 15_000 });
		await expect(toggle).toBeDisabled();
		await expect(page.getByTestId('race-gallery-hint')).toHaveText(
			'Make this run public to share it on the race page.'
		);
	});
});

test.describe('logged-out race page', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('omits photos on a private run and photos nobody opted in', async ({ page }) => {
		const privateCaption = `e2e opted-in private ${Date.now()}`;
		const notOptedCaption = `e2e not opted in ${Date.now()}`;
		await seedLinkedRunWithPhoto({ isPublic: false, caption: privateCaption, raceGallery: true });
		await seedLinkedRunWithPhoto({ isPublic: true, caption: notOptedCaption });

		// The section is absent rather than empty, so wait for the gallery read
		// itself before asserting the negative.
		const galleryRead = page.waitForResponse((r) => r.url().includes('/rest/v1/rpc/race_listing_photos'));
		await page.goto(`/share/race/${listingId}`);
		await expect(page.getByRole('heading', { level: 1 })).toBeVisible({ timeout: 15_000 });
		expect((await galleryRead).ok()).toBe(true);
		await expect(page.getByText(privateCaption)).toHaveCount(0);
		await expect(page.getByText(notOptedCaption)).toHaveCount(0);
	});
});
