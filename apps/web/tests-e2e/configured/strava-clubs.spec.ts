import type { Page, Request, Route } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient, resetRateLimit } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * "Your Strava clubs" (issue #1151 step 4, decisions § 1959) on a build WITH
 * `PUBLIC_STRAVA_CLIENT_ID` — the configured half that
 * `clubs/strava-clubs.spec.ts` cannot reach, because the sharded lane builds
 * without the id and pins the section's inertness there. This file runs only
 * in the configured lane (playwright.configured.config.ts), whose dev server
 * carries a dummy id.
 *
 * The `strava-clubs` Edge Function is mocked at the network layer, so nothing
 * reaches Strava; the unlink is the real `unlink_club_strava` RPC against the
 * local stack, because it needs no Strava call and is the one write here that
 * lands in the database. USER_A owns Richmond Run Club in the seed, which is
 * what makes it an admin club the section can link to and unlink from.
 */

const RICHMOND = {
	id: 'c1111111-0000-0000-0000-000000000001',
	slug: 'richmond-run-club',
	name: 'Richmond Run Club',
};

// Far outside any id the seed or another spec writes: the column is unique
// where set, and the unlink test sets it for real.
const STRAVA_CLUB_ID = 918_273_645;

function stravaClub(overrides: Record<string, unknown> = {}) {
	return {
		strava_club_id: STRAVA_CLUB_ID,
		name: 'Strava Only Striders',
		city: 'Leeds',
		state: null,
		country: 'United Kingdom',
		sport_type: 'running',
		member_count: 12,
		profile_url: null,
		viewer_is_admin: true,
		linked_club: null,
		...overrides,
	};
}

type Action = { action?: string; club_id?: string; strava_club_id?: number };

/** Answers `strava-clubs` per action, recording each request body. */
function stravaClubsHandler(listed: unknown, calls: Action[]) {
	return async (route: Route, request: Request) => {
		const body = (request.postDataJSON() ?? {}) as Action;
		calls.push(body);
		const payload = body.action === 'list' ? listed : { ok: true };
		await route.fulfill({
			status: 200,
			contentType: 'application/json',
			body: JSON.stringify(payload),
		});
	};
}

async function openMyClubs(page: Page) {
	await page.goto('/social?tab=clubs');
	const section = page.getByTestId('strava-clubs');
	await expect(section).toBeVisible({ timeout: 15_000 });
	return section;
}

test.describe('Your Strava clubs — configured build', () => {
	test.use({ storageState: USER_A.storageStatePath });
	test.beforeEach(async () => {
		await resetRateLimit(USER_A.id, 'create_club');
	});

	test("lists the runner's Strava clubs with the actions each one allows", async ({ page, mockRoute }) => {
		const calls: Action[] = [];
		await mockRoute(
			page,
			'**/functions/v1/strava-clubs',
			stravaClubsHandler(
				{
					status: 'connected',
					clubs: [
						stravaClub(),
						stravaClub({
							strava_club_id: STRAVA_CLUB_ID + 1,
							name: 'Member Only Milers',
							city: null,
							member_count: 1,
							viewer_is_admin: false,
						}),
					],
				},
				calls,
			),
		);

		const section = await openMyClubs(page);
		await expect(section.getByRole('heading', { name: 'Your Strava clubs' })).toBeVisible();
		const rows = section.getByTestId('strava-club-row');
		await expect(rows).toHaveCount(2);
		expect(calls).toEqual([{ action: 'list' }]);

		const admin = rows.filter({ hasText: 'Strava Only Striders' });
		await expect(admin).toContainText('Leeds, United Kingdom');
		await expect(admin).toContainText('12 members');
		const setUp = admin.getByRole('link', { name: 'Set up on Threkir' });
		await expect(setUp).toHaveAttribute('href', new RegExp(`^/clubs/new\\?.*strava_club=${STRAVA_CLUB_ID}`));
		await expect(admin.getByRole('button', { name: 'Link to my club' })).toBeVisible();

		const member = rows.filter({ hasText: 'Member Only Milers' });
		await expect(member).toContainText('United Kingdom');
		await expect(member).toContainText('1 member');
		await expect(member).toContainText('Only an admin of this club on Strava can bring it to Threkir.');
		await expect(member.getByRole('link', { name: 'Set up on Threkir' })).toHaveCount(0);
		await expect(member.getByRole('button', { name: 'Link to my club' })).toHaveCount(0);
	});

	test("links a Strava club to one of the runner's own clubs", async ({ page, mockRoute }) => {
		const calls: Action[] = [];
		await mockRoute(
			page,
			'**/functions/v1/strava-clubs',
			stravaClubsHandler({ status: 'connected', clubs: [stravaClub()] }, calls),
		);

		const section = await openMyClubs(page);
		const row = section.getByTestId('strava-club-row');
		await row.getByRole('button', { name: 'Link to my club' }).click();
		await row.getByRole('combobox', { name: 'Which of your clubs is this?' }).selectOption({ label: RICHMOND.name });
		await row.getByRole('button', { name: 'Link', exact: true }).click();

		await expect(row.getByRole('link', { name: `View ${RICHMOND.name}` })).toHaveAttribute(
			'href',
			`/clubs/${RICHMOND.slug}`,
		);
		await expect(row.getByRole('button', { name: 'Unlink' })).toBeVisible();
		await expect(page.getByText(`Linked to ${RICHMOND.name}.`)).toBeVisible();
		expect(calls).toEqual([
			{ action: 'list' },
			{ action: 'link', club_id: RICHMOND.id, strava_club_id: STRAVA_CLUB_ID },
		]);
	});

	test('unlinking is undoable, and commits through the RPC once the offer closes', async ({ page, mockRoute }) => {
		const admin = getAdminClient();
		const readLink = async () => {
			const { data, error } = await admin.from('clubs').select('strava_club_id').eq('id', RICHMOND.id).single();
			if (error || !data) throw new Error(`could not read ${RICHMOND.slug}: ${error?.message}`);
			return data.strava_club_id as number | null;
		};
		const { error: seedError } = await admin
			.from('clubs')
			.update({ strava_club_id: STRAVA_CLUB_ID })
			.eq('id', RICHMOND.id);
		if (seedError) throw new Error(`could not link ${RICHMOND.slug}: ${seedError.message}`);

		try {
			const calls: Action[] = [];
			await mockRoute(
				page,
				'**/functions/v1/strava-clubs',
				stravaClubsHandler(
					{
						status: 'connected',
						clubs: [stravaClub({ linked_club: RICHMOND })],
					},
					calls,
				),
			);

			const section = await openMyClubs(page);
			const row = section.getByTestId('strava-club-row');
			const unlink = row.getByRole('button', { name: 'Unlink' });
			const view = row.getByRole('link', { name: `View ${RICHMOND.name}` });
			await expect(view).toBeVisible();

			// Undo inside the window: the link comes back and never left the row.
			await unlink.click();
			await expect(row.getByRole('link', { name: 'Set up on Threkir' })).toBeVisible();
			await expect(page.getByTestId('undo-bar')).toContainText(`Unlinked ${RICHMOND.name} from Strava.`);
			await page.getByTestId('undo-action').click();
			await expect(view).toBeVisible();
			expect(await readLink()).toBe(STRAVA_CLUB_ID);

			// Dismissing the offer commits the held unlink.
			await unlink.click();
			await expect(page.getByTestId('undo-bar')).toBeVisible();
			await page.getByTestId('undo-dismiss').click();
			await expect(page.getByTestId('undo-bar')).toBeHidden({ timeout: 5_000 });
			await expect.poll(readLink, { timeout: 5_000 }).toBeNull();
			await expect(row.getByRole('link', { name: 'Set up on Threkir' })).toBeVisible();

			expect(calls, 'unlinking needs no Strava call').toEqual([{ action: 'list' }]);
		} finally {
			await admin.from('clubs').update({ strava_club_id: null }).eq('id', RICHMOND.id);
		}
	});

	test('setting up a Strava club creates the club and then links it', async ({ page, mockRoute }) => {
		const calls: Action[] = [];
		await mockRoute(page, '**/functions/v1/strava-clubs', stravaClubsHandler({ status: 'not_connected' }, calls));
		await page.route('**/api.maptiler.com/geocoding/**', (route) =>
			route.fulfill({
				status: 200,
				contentType: 'application/json',
				body: JSON.stringify({ type: 'FeatureCollection', features: [] }),
			}),
		);

		const name = `Strava Only Striders ${Date.now()}`;
		const params = new URLSearchParams({
			name,
			location: 'Leeds, United Kingdom',
			strava_club: String(STRAVA_CLUB_ID),
		});
		await page.goto(`/clubs/new?${params.toString()}`);
		await expect(page.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue(name, { timeout: 15_000 });
		await expect(page.getByTestId('clubs-new-strava-note')).toHaveText(
			'Once your club is created it will be linked to its Strava club.',
		);

		await page.getByRole('button', { name: 'Create club' }).click();
		await page.waitForURL(/\/clubs\/[a-z0-9-]*\d[a-z0-9-]*$/, {
			timeout: 15_000,
		});
		const slug = page.url().match(/\/clubs\/([a-z0-9-]+)$/)![1];

		const admin = getAdminClient();
		const { data, error } = await admin.from('clubs').select('id').eq('slug', slug).single();
		try {
			if (error || !data) throw new Error(`created club ${slug} not found: ${error?.message}`);
			await expect(page.getByText('Your club is linked to its Strava club.')).toBeVisible();
			expect(calls).toEqual([{ action: 'link', club_id: data.id, strava_club_id: STRAVA_CLUB_ID }]);
		} finally {
			if (data) await admin.from('clubs').delete().eq('id', data.id);
			await resetRateLimit(USER_A.id, 'create_club');
		}
	});
});
