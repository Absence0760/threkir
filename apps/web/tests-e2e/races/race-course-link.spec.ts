import { expect, test } from '../fixtures/test';

import { browserDate } from '../fixtures/dates';
import { readRows } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteClub, deleteRaceListing, deleteRoute, insertRaceListing, insertRoute } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Claim, link and suggest on /races/[id] (issue #1297, decisions § 2381).
 *
 * A verified club's owner claims an unclaimed race and links one of the
 * club's public routes as its course; the race page then says where the
 * course came from. A runner suggests one of their own public routes, which
 * links nothing until the organiser approves it with the club's copy. A
 * hand-added listing a club claimed is credited to the club, not "a runner".
 * Removing a course and rejecting a suggestion are held for the undo window
 * (conventions.md § Destructive actions). The review queue
 * (/races/course-suggestions, decisions § 2396) lets a verified club's owner
 * claim an unclaimed race and review its suggestion in place.
 */

const WAYPOINTS = [
	{ lat: 37.54, lng: -77.43 },
	{ lat: 37.55, lng: -77.44 },
	{ lat: 37.56, lng: -77.45 }
];

test.describe('/races/[id] — race course claim, link and suggest', () => {
	test.use({ storageState: USER_A.storageStatePath });

	const listings: string[] = [];
	const routes: string[] = [];
	const clubs: string[] = [];

	test.afterEach(async () => {
		for (const id of listings.splice(0)) await deleteRaceListing(id).catch(() => undefined);
		for (const id of routes.splice(0)) await deleteRoute(id).catch(() => undefined);
		for (const id of clubs.splice(0)) await deleteClub(id).catch(() => undefined);
	});

	/// A verified, public club USER_A owns, with one public club route.
	async function verifiedClubWithCourse(tag: string) {
		const admin = getAdminClient();
		const name = `E2E Course Org ${tag}`;
		const { data: club, error } = await admin
			.from('clubs')
			.insert({ owner_id: USER_A.id, name, slug: `e2e-course-org-${tag}`, is_public: true, is_verified: true })
			.select('id')
			.single();
		if (error || !club) throw new Error(`club insert failed: ${error?.message}`);
		clubs.push(club.id);
		const routeName = `E2E Club Course ${tag}`;
		const { data: route, error: routeErr } = await admin
			.from('routes')
			.insert({
				user_id: USER_A.id,
				club_id: club.id,
				name: routeName,
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
		return { clubId: club.id, clubName: name, routeId: route.id, routeName };
	}

	test('a verified club claims a race and links its traced course', async ({ page }) => {
		const tag = `${Date.now()}`;
		const org = await verifiedClubWithCourse(tag);
		const raceName = `E2E Course Claim ${tag}`;
		const id = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(60),
			distance_m: 42_195,
			is_verified: false
		});
		listings.push(id);

		await page.goto(`/races/${id}`);
		await expect(page.getByTestId('race-detail-name')).toHaveText(raceName, { timeout: 15_000 });
		await page.getByTestId('race-course-claim').click();
		await page.getByTestId('race-course-claim-club').selectOption(org.clubId);
		await page.getByTestId('race-course-claim-confirm').click();
		await expect(page.getByText('Race claimed.')).toBeVisible({ timeout: 15_000 });

		await page.getByTestId('race-course-link').click();
		await expect(page.getByTestId('race-course-link-route')).toHaveValue(org.routeId, { timeout: 15_000 });
		await page.getByTestId('race-course-source-traced').check();
		await page.getByTestId('race-course-link-confirm').click();
		await expect(page.getByText('Course linked.')).toBeVisible({ timeout: 15_000 });

		await expect(page.getByTestId('race-detail-course-source')).toContainText(
			`Course drawn by ${org.clubName} from the race's published map`
		);
		await expect(page.getByTestId('race-detail-course-source')).toContainText('last checked');
		await expect(page.getByTestId('race-detail-source')).toHaveText('Listed on RunSignUp');
		await expect(page.getByTestId('race-detail-course-map')).toBeVisible();

		const rows = await readRows(
			'claimed listing',
			getAdminClient()
				.from('race_listings')
				.select('organiser_club_id, is_verified, route_id, course_source')
				.eq('id', id)
		);
		expect(rows).toEqual([
			{ organiser_club_id: org.clubId, is_verified: true, route_id: org.routeId, course_source: 'traced' }
		]);
	});

	test('a runner suggests a course and the organiser approves it with the club copy', async ({
		page,
		browser
	}) => {
		const tag = `${Date.now()}`;
		const org = await verifiedClubWithCourse(tag);
		const raceName = `E2E Course Suggest ${tag}`;
		const id = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(45),
			distance_m: 42_195
		});
		listings.push(id);
		const { error: claimErr } = await getAdminClient()
			.from('race_listings')
			.update({ organiser_club_id: org.clubId })
			.eq('id', id);
		if (claimErr) throw claimErr;

		const runnerRouteName = `E2E Runner Trace ${tag}`;
		const runnerRoute = await insertRoute({
			user_id: USER_B.id,
			name: runnerRouteName,
			waypoints: WAYPOINTS,
			distance_m: 42_300,
			is_public: true
		});
		routes.push(runnerRoute);

		const runner = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const runnerPage = await runner.newPage();
			await runnerPage.goto(`/races/${id}`);
			await expect(runnerPage.getByTestId('race-detail-name')).toHaveText(raceName, { timeout: 15_000 });
			await expect(runnerPage.getByTestId('race-course-link')).toHaveCount(0);
			await runnerPage.getByTestId('race-course-suggest').click();
			await expect(runnerPage.getByTestId('race-course-suggest-route')).toHaveValue(runnerRoute, {
				timeout: 15_000
			});
			await runnerPage.getByTestId('race-course-suggest-note').fill('Traced from the published map');
			await runnerPage.getByTestId('race-course-suggest-confirm').click();
			await expect(runnerPage.getByText('Suggestion sent.')).toBeVisible({ timeout: 15_000 });
			await expect(runnerPage.getByTestId('race-course-suggest-pending')).toBeVisible();
		} finally {
			await runner.close();
		}

		const listed = await readRows(
			'listing after suggestion',
			getAdminClient().from('race_listings').select('route_id').eq('id', id)
		);
		expect(listed).toEqual([{ route_id: null }]);

		await page.goto(`/races/${id}`);
		const queue = page.getByTestId('race-course-suggestions');
		await expect(queue).toContainText(runnerRouteName, { timeout: 15_000 });
		await expect(queue).toContainText('Traced from the published map');
		await queue.getByTestId('race-course-approve').click();
		await expect(page.getByTestId('race-course-link-route')).toHaveValue(org.routeId, { timeout: 15_000 });
		await page.getByTestId('race-course-link-confirm').click();
		await expect(page.getByText('Suggestion approved and course linked.')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('race-detail-course-source')).toContainText(
			`Official course from ${org.clubName}`
		);
		await expect(page.getByTestId('race-course-suggestions')).toHaveCount(0);

		const suggestions = await readRows(
			'reviewed suggestion',
			getAdminClient().from('race_course_suggestions').select('status, user_id').eq('listing_id', id)
		);
		expect(suggestions).toEqual([{ status: 'approved', user_id: USER_B.id }]);
	});

	test('a hand-added race a club claimed is credited to the club', async ({ page }) => {
		const tag = `${Date.now()}`;
		const org = await verifiedClubWithCourse(tag);
		const raceName = `E2E Course Manual ${tag}`;
		const id = await insertRaceListing({ provider: 'manual', name: raceName, race_date: browserDate(30) });
		listings.push(id);
		const { error } = await getAdminClient()
			.from('race_listings')
			.update({ organiser_club_id: org.clubId })
			.eq('id', id);
		if (error) throw error;

		await page.goto(`/races/${id}`);
		await expect(page.getByTestId('race-detail-name')).toHaveText(raceName, { timeout: 15_000 });
		await expect(page.getByTestId('race-detail-source')).toHaveText(`Added by ${org.clubName}`);
		await expect(page.getByTestId('race-course-claim')).toHaveCount(0);
		await expect(page.getByTestId('race-course-link')).toBeVisible();
	});

	async function claimedRaceWithCourse(tag: string) {
		const org = await verifiedClubWithCourse(tag);
		const raceName = `E2E Course Undo ${tag}`;
		const id = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(50),
			distance_m: 42_195
		});
		listings.push(id);
		const { error } = await getAdminClient()
			.from('race_listings')
			.update({
				organiser_club_id: org.clubId,
				route_id: org.routeId,
				course_source: 'official',
				course_checked_at: new Date().toISOString()
			})
			.eq('id', id);
		if (error) throw error;
		return { ...org, id, raceName };
	}

	async function runnerSuggestion(listingId: string, tag: string) {
		const routeName = `E2E Runner Trace ${tag}`;
		const routeId = await insertRoute({
			user_id: USER_B.id,
			name: routeName,
			waypoints: WAYPOINTS,
			distance_m: 42_300,
			is_public: true
		});
		routes.push(routeId);
		const { error } = await getAdminClient()
			.from('race_course_suggestions')
			.insert({ listing_id: listingId, route_id: routeId, user_id: USER_B.id });
		if (error) throw error;
		return { routeId, routeName };
	}

	async function courseRouteId(id: string) {
		const rows = await readRows(
			'listing course',
			getAdminClient().from('race_listings').select('route_id').eq('id', id)
		);
		return rows[0]?.route_id ?? null;
	}

	test('removing the course is held for undo, and Undo keeps it', async ({ page }) => {
		const race = await claimedRaceWithCourse(`${Date.now()}`);

		await page.goto(`/races/${race.id}`);
		await expect(page.getByTestId('race-detail-course-source')).toContainText(
			`Official course from ${race.clubName}`,
			{ timeout: 15_000 }
		);
		await page.getByTestId('race-course-link').click();
		await page.getByTestId('race-course-unlink').click();
		await expect(page.getByTestId('undo-bar')).toContainText('Course removed.');
		await expect(page.getByTestId('race-detail-course-source')).toHaveCount(0);
		await page.getByTestId('undo-action').click();
		await expect(page.getByTestId('race-detail-course-source')).toContainText(
			`Official course from ${race.clubName}`
		);
		expect(await courseRouteId(race.id)).toBe(race.routeId);

		await page.getByTestId('race-course-link').click();
		await page.getByTestId('race-course-unlink').click();
		await page.getByTestId('undo-dismiss').click();
		await expect.poll(() => courseRouteId(race.id), { timeout: 15_000 }).toBeNull();
		await expect(page.getByTestId('race-detail-course-source')).toHaveCount(0);
	});

	test('rejecting a suggestion is held for undo, and Undo puts it back', async ({ page }) => {
		const tag = `${Date.now()}`;
		const race = await claimedRaceWithCourse(tag);
		const suggestion = await runnerSuggestion(race.id, tag);
		const status = async () => {
			const rows = await readRows(
				'suggestion status',
				getAdminClient().from('race_course_suggestions').select('status').eq('listing_id', race.id)
			);
			return rows[0]?.status ?? null;
		};

		await page.goto(`/races/${race.id}`);
		const queue = page.getByTestId('race-course-suggestions');
		await expect(queue).toContainText(suggestion.routeName, { timeout: 15_000 });
		await queue.getByTestId('race-course-reject').click();
		await expect(page.getByTestId('undo-bar')).toContainText('Suggestion rejected.');
		await expect(page.getByTestId('race-course-suggestions')).toHaveCount(0);
		await page.getByTestId('undo-action').click();
		await expect(queue).toContainText(suggestion.routeName);
		expect(await status()).toBe('pending');

		await queue.getByTestId('race-course-reject').click();
		await page.getByTestId('undo-dismiss').click();
		await expect.poll(status, { timeout: 15_000 }).toBe('rejected');
	});

	test('the review queue claims an unclaimed race and approves its suggestion in place', async ({
		page,
		browser
	}) => {
		const tag = `${Date.now()}`;
		const org = await verifiedClubWithCourse(tag);
		const raceName = `E2E Course Queue ${tag}`;
		const id = await insertRaceListing({
			provider: 'runsignup',
			name: raceName,
			race_date: browserDate(40),
			distance_m: 42_195
		});
		listings.push(id);
		const suggestion = await runnerSuggestion(id, tag);

		await page.goto('/races');
		await page.getByTestId('race-course-queue-link').click();
		await expect(page).toHaveURL(/\/races\/course-suggestions$/);
		const item = page.getByTestId('race-course-queue-item').filter({ hasText: raceName });
		await expect(item).toContainText('Unclaimed', { timeout: 15_000 });
		await expect(item.getByTestId('race-course-suggestions')).toContainText(suggestion.routeName);
		await expect(item.getByTestId('race-course-review-claim-first')).toBeVisible();
		await expect(item.getByTestId('race-course-suggest')).toHaveCount(0);

		await item.getByTestId('race-course-claim').click();
		await page.getByTestId('race-course-claim-club').selectOption(org.clubId);
		await page.getByTestId('race-course-claim-confirm').click();
		await expect(page.getByText('Race claimed.')).toBeVisible({ timeout: 15_000 });
		await expect(item).toContainText(org.clubName, { timeout: 15_000 });

		await item.getByTestId('race-course-approve').click();
		await expect(page.getByTestId('race-course-link-route')).toHaveValue(org.routeId, { timeout: 15_000 });
		await page.getByTestId('race-course-link-confirm').click();
		await expect(page.getByText('Suggestion approved and course linked.')).toBeVisible({ timeout: 15_000 });
		await expect(item).toHaveCount(0, { timeout: 15_000 });

		const rows = await readRows(
			'queued listing',
			getAdminClient().from('race_listings').select('organiser_club_id, route_id').eq('id', id)
		);
		expect(rows).toEqual([{ organiser_club_id: org.clubId, route_id: org.routeId }]);

		const runner = await browser.newContext({ storageState: USER_B.storageStatePath });
		try {
			const runnerPage = await runner.newPage();
			await runnerPage.goto('/races/course-suggestions');
			await expect(runnerPage.getByTestId('race-course-queue-not-publisher')).toBeVisible({
				timeout: 15_000
			});
		} finally {
			await runner.close();
		}
	});
});

