import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteClub, deleteRaceListing, deleteRoute, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Provenance labels and organiser course alerts on the race calendar
 * (issue #1190, decisions § 2406 / § 2407).
 *
 * A race claimed by a verified club reads "Official" on its calendar card
 * and its page, a provider-synced race reads "Verified source", and a
 * runner's own unverified listing carries no badge. The claimed race's
 * traced course reads "Traced", with a sentence a screen reader can hear.
 * The organiser club's owner posts a course alert, which every visitor then
 * reads on the race page; removing it is held for the undo window. The
 * stable-id notification target opens the race and reads not found once the
 * alert is gone. Fixtures are seeded with the service-role client, the only
 * writer of clubs.is_verified and the claim columns.
 */

const WAYPOINTS = [
	{ lat: 37.54, lng: -77.43 },
	{ lat: 37.55, lng: -77.44 },
	{ lat: 37.56, lng: -77.45 }
];

test.describe('race provenance and course alerts (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const listings: string[] = [];
	const routes: string[] = [];
	const clubs: string[] = [];

	test.afterEach(async () => {
		for (const id of listings.splice(0)) await deleteRaceListing(id).catch(() => undefined);
		for (const id of routes.splice(0)) await deleteRoute(id).catch(() => undefined);
		for (const id of clubs.splice(0)) await deleteClub(id).catch(() => undefined);
	});

	/// A verified club USER_A owns, with a claimed race whose course the club
	/// traced from the published map.
	async function claimedRace(tag: string) {
		const admin = getAdminClient();
		const { data: club, error } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: `E2E Provenance Org ${tag}`,
				slug: `e2e-provenance-org-${tag}`,
				is_public: true,
				is_verified: true
			})
			.select('id')
			.single();
		if (error || !club) throw new Error(`club insert failed: ${error?.message}`);
		clubs.push(club.id);
		const { data: route, error: routeErr } = await admin
			.from('routes')
			.insert({
				user_id: USER_A.id,
				club_id: club.id,
				name: `E2E Provenance Course ${tag}`,
				waypoints: WAYPOINTS,
				distance_m: 42_195,
				elevation_m: 120,
				surface: 'road',
				is_public: true
			})
			.select('id')
			.single();
		if (routeErr || !route) throw new Error(`route insert failed: ${routeErr?.message}`);
		routes.push(route.id);
		const raceName = `E2E Provenance Official ${tag}`;
		const id = await insertRaceListing({
			provider: 'manual',
			name: raceName,
			race_date: browserDate(60),
			distance_m: 42_195
		});
		listings.push(id);
		const claim = await admin
			.from('race_listings')
			.update({
				organiser_club_id: club.id,
				route_id: route.id,
				course_source: 'traced',
				course_checked_at: new Date().toISOString()
			})
			.eq('id', id);
		if (claim.error) throw new Error(`claim failed: ${claim.error.message}`);
		return { id, raceName, clubId: club.id };
	}

	test('cards and the race page say where each race and course came from', async ({ page }) => {
		const tag = `${Date.now()}`;
		const official = await claimedRace(tag);
		const syncedName = `E2E Provenance Synced ${tag}`;
		listings.push(
			await insertRaceListing({ provider: 'runsignup', name: syncedName, race_date: browserDate(61) })
		);
		const fanName = `E2E Provenance Fan ${tag}`;
		listings.push(
			await insertRaceListing({ provider: 'manual', name: fanName, race_date: browserDate(62), is_verified: false })
		);

		await page.goto('/races');
		await page.getByTestId('races-search').fill(`E2E Provenance`);
		const officialCard = page.getByTestId('race-card').filter({ hasText: official.raceName });
		const syncedCard = page.getByTestId('race-card').filter({ hasText: syncedName });
		const fanCard = page.getByTestId('race-card').filter({ hasText: fanName });
		await expect(officialCard).toBeVisible({ timeout: 15_000 });
		await expect(officialCard.getByTestId('official-badge')).toBeVisible();
		await expect(officialCard.getByTestId('official-badge')).toContainText(
			'Official: published by a verified organiser'
		);
		await expect(syncedCard.locator('[data-provenance="verified_source"]')).toBeVisible();
		await expect(syncedCard.getByTestId('official-badge')).toHaveCount(0);
		await expect(fanCard.locator('[data-provenance]')).toHaveCount(0);
		await expect(fanCard.getByTestId('race-unverified')).toBeVisible();

		await officialCard.getByTestId('race-detail-link').click();
		await expect(page).toHaveURL(new RegExp(`/races/${official.id}$`));
		await expect(page.getByTestId('race-detail-provenance').getByTestId('official-badge')).toBeVisible({
			timeout: 15_000
		});
		const course = page.getByTestId('race-detail-course-provenance').locator('[data-provenance="traced"]');
		await expect(course).toBeVisible();
		await expect(course).toContainText("Traced: drawn by a verified club from the race's published map");
	});

	test('a revoked club takes the badge off its race at once', async ({ page }) => {
		const tag = `${Date.now()}`;
		const official = await claimedRace(tag);
		const revoke = await getAdminClient().from('clubs').update({ is_verified: false }).eq('id', official.clubId);
		if (revoke.error) throw new Error(`revoke failed: ${revoke.error.message}`);

		await page.goto(`/races/${official.id}`);
		await expect(page.getByTestId('race-detail-name')).toHaveText(official.raceName, { timeout: 15_000 });
		await expect(page.getByTestId('official-badge')).toHaveCount(0);
		await expect(page.getByTestId('race-detail-provenance').locator('[data-provenance="community"]')).toBeVisible();
		await expect(page.getByTestId('race-detail-course-source')).toHaveCount(0);
		await expect(page.getByTestId('course-alert-form')).toHaveCount(0);
	});

	test('the organiser posts a course alert, the notice link opens the race, and removal is held for undo', async ({
		page
	}) => {
		const tag = `${Date.now()}`;
		const official = await claimedRace(tag);

		await page.goto(`/races/${official.id}`);
		await expect(page.getByTestId('course-alert-form')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('course-alerts-empty')).toBeVisible();
		await page.getByTestId('course-alert-kind').selectOption('closure');
		await page.getByTestId('course-alert-message').fill('The river path is closed; the course stays on the road.');
		await page.getByTestId('course-alert-post').click();
		await expect(page.getByText('Course alert posted.')).toBeVisible({ timeout: 15_000 });
		const alert = page.getByTestId('course-alert');
		await expect(alert).toHaveCount(1);
		await expect(alert).toHaveAttribute('data-kind', 'closure');
		await expect(alert).toContainText('Closure');
		await expect(alert).toContainText('The river path is closed; the course stays on the road.');

		const { data: rows, error } = await getAdminClient()
			.from('course_alerts')
			.select('id')
			.eq('listing_id', official.id);
		if (error || !rows?.length) throw new Error(`alert read failed: ${error?.message}`);
		await page.goto(`/course-alerts/${rows[0].id}`);
		await expect(page).toHaveURL(new RegExp(`/races/${official.id}$`), { timeout: 15_000 });

		await page.getByTestId('course-alert-remove').click();
		await expect(page.getByTestId('course-alert')).toHaveCount(0);
		await expect(page.getByText('Course alert removed.')).toBeVisible();
	});

	test('a notice whose alert is gone reads as not found', async ({ page }) => {
		await page.goto(`/course-alerts/${crypto.randomUUID()}`);
		await expect(page.getByTestId('course-alert-not-found')).toBeVisible({ timeout: 15_000 });
	});
});
