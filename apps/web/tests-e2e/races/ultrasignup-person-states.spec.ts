import { expect, test } from '../fixtures/test';
import type { Page, Route } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { readMaybeRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteIntegration, deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The UltraSignup person link's edges (decisions § 1841) — the paths
 * `ultrasignup-person-import.spec.ts` does not walk:
 *
 *   - a name nobody answers to says so, rather than an empty list;
 *   - a 502 or 503 from the lookup is a toast and a form that still works;
 *   - same-named people are told apart, and the one picked is the one stored;
 *   - unlink is undoable, and a committed unlink can be re-linked as someone
 *     else;
 *   - an import whose stored person UltraSignup no longer lists sends the
 *     runner back to Settings, not to "try again";
 *   - a double press searches once and links once.
 *
 * As in the sibling spec only the Edge Function is stubbed; the link is the
 * panel's own `integrations` write under the runner's session.
 */

const reply = (route: Route, status: number, payload: unknown) =>
	route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(payload) });

const NAMESAKES = [
	{
		id: '900001',
		firstName: 'Alex',
		lastName: 'Sample',
		age: 41,
		resultCount: 4,
		recentEvents: [{ name: 'Example Peaks 100 Mile', date: '2025-06-20' }]
	},
	{
		id: '900002',
		firstName: 'Alex',
		lastName: 'Sample',
		age: null,
		resultCount: 1,
		recentEvents: []
	}
];

type Body = Record<string, unknown>;

/// Stub race-results-import: every probe answers configured, a lookup answers
/// `onLookup`, an import answers `onImport`. Returns the bodies it saw.
async function stubFunction(
	page: Page,
	mockRoute: import('../fixtures/mock-route').MockRoute,
	handlers: {
		onLookup?: (route: Route, body: Body) => Promise<unknown> | unknown;
		onImport?: (route: Route, body: Body) => Promise<unknown> | unknown;
	}
): Promise<{ lookups: Body[]; imports: Body[] }> {
	const seen = { lookups: [] as Body[], imports: [] as Body[] };
	await mockRoute(page, '**/functions/v1/race-results-import', async (route) => {
		const body = (route.request().postDataJSON() ?? {}) as Body;
		if (body.probe === true) {
			return body.ultraSignUpFlow === 'person' || body.provider !== 'ultrasignup'
				? reply(route, 200, { configured: true })
				: reply(route, 503, { error: 'provider_not_configured', reason: 'client_unsupported' });
		}
		if (body.lookup === true) {
			seen.lookups.push(body);
			return handlers.onLookup
				? handlers.onLookup(route, body)
				: reply(route, 200, { candidates: NAMESAKES });
		}
		seen.imports.push(body);
		return handlers.onImport
			? handlers.onImport(route, body)
			: reply(route, 200, { imported: 1, skipped: 0, enriched: 0, complete: true });
	});
	return seen;
}

async function linkDirectly(personId: string): Promise<void> {
	const { error } = await getAdminClient().from('integrations').upsert(
		{
			user_id: USER_A.id,
			provider: 'ultrasignup',
			external_id: personId,
			external_first_name: 'Alex',
			external_last_name: 'Sample'
		},
		{ onConflict: 'user_id,provider' }
	);
	if (error) throw new Error(`linkDirectly failed: ${error.message}`);
}

async function storedPersonId(): Promise<string | null> {
	const row = await readMaybeRow(
		'ultrasignup integration',
		getAdminClient()
			.from('integrations')
			.select('external_id')
			.eq('user_id', USER_A.id)
			.eq('provider', 'ultrasignup')
			.maybeSingle()
	);
	return (row?.external_id as string | null | undefined) ?? null;
}

async function openCard(page: Page) {
	await page.goto('/settings/integrations');
	const card = page.getByTestId('ultrasignup-card');
	await expect(card).toBeVisible({ timeout: 15_000 });
	return card;
}

async function searchFor(card: import('@playwright/test').Locator, first: string, last: string) {
	await card.getByTestId('ultrasignup-first-name').fill(first);
	await card.getByTestId('ultrasignup-last-name').fill(last);
	await card.getByTestId('ultrasignup-find').click();
}

test.describe('UltraSignup person link — edges', () => {
	test.use({ storageState: USER_A.storageStatePath });
	// Every case reads and writes the same user's one UltraSignup row.
	test.describe.configure({ mode: 'serial' });

	test.beforeEach(async () => {
		await deleteIntegration(USER_A.id, 'ultrasignup');
	});

	test.afterAll(async () => {
		await deleteIntegration(USER_A.id, 'ultrasignup');
	});

	test('a name nobody answers to says so, and links nothing', async ({ page, mockRoute }) => {
		await stubFunction(page, mockRoute, {
			onLookup: (route) => reply(route, 200, { candidates: [] })
		});
		const card = await openCard(page);
		await searchFor(card, 'Nobody', 'Byname');

		await expect(card.getByTestId('ultrasignup-no-matches')).toHaveText(
			'UltraSignup has nobody by that name. Check the spelling you race under.',
			{ timeout: 15_000 }
		);
		await expect(card.getByTestId('ultrasignup-candidate')).toHaveCount(0);
		await expect(card.getByTestId('ultrasignup-find')).toBeEnabled();
		expect(await storedPersonId()).toBeNull();
	});

	for (const [status, code] of [
		[502, 'ultrasignup_upstream_failed'],
		[503, 'provider_not_configured']
	] as const) {
		test(`a ${status} from the lookup is a toast and a form that still searches`, async ({
			page,
			mockRoute
		}) => {
			let failNext = true;
			const seen = await stubFunction(page, mockRoute, {
				onLookup: (route) => {
					if (failNext) {
						failNext = false;
						return reply(route, status, { error: code });
					}
					return reply(route, 200, { candidates: NAMESAKES });
				}
			});
			const card = await openCard(page);
			await searchFor(card, 'Alex', 'Sample');

			await expect(page.getByText("Couldn't search UltraSignup. Try again in a moment.")).toBeVisible({
				timeout: 15_000
			});
			await expect(card.getByTestId('ultrasignup-candidate')).toHaveCount(0);
			await expect(card.getByTestId('ultrasignup-no-matches')).toHaveCount(0);

			// The names survive the failure, so a retry is one press.
			await expect(card.getByTestId('ultrasignup-last-name')).toHaveValue('Sample');
			await card.getByTestId('ultrasignup-find').click();
			await expect(card.getByTestId('ultrasignup-candidate')).toHaveCount(2, { timeout: 15_000 });
			expect(seen.lookups).toHaveLength(2);
		});
	}

	test('same-named people are told apart, and the one picked is the one stored', async ({
		page,
		mockRoute
	}) => {
		await stubFunction(page, mockRoute, {});
		const card = await openCard(page);
		await searchFor(card, 'Alex', 'Sample');

		const people = card.getByTestId('ultrasignup-candidate');
		await expect(people).toHaveCount(2, { timeout: 15_000 });
		await expect(card).toContainText('Which of these is you?');
		await expect(people.nth(0)).toContainText(/Age 41\s*·\s*4 results/);
		await expect(people.nth(0)).toContainText('Example Peaks 100 Mile (2025)');
		await expect(people.nth(1)).toContainText('1 result');
		await expect(people.nth(1)).not.toContainText('Age');

		await card.getByTestId('ultrasignup-pick-900002').click();
		await expect(card.getByTestId('ultrasignup-linked-as')).toHaveText(
			'Linked as Alex Sample (UltraSignup #900002)',
			{ timeout: 15_000 }
		);
		await expect(card.getByTestId('ultrasignup-candidate')).toHaveCount(0);
		await expect.poll(storedPersonId).toBe('900002');
	});

	test('unlink can be undone, and once committed the runner can link someone else', async ({
		page,
		mockRoute
	}) => {
		await linkDirectly('900001');
		await stubFunction(page, mockRoute, {});
		const card = await openCard(page);
		await expect(card.getByTestId('ultrasignup-linked-as')).toContainText('#900001', {
			timeout: 15_000
		});

		await card.getByTestId('ultrasignup-unlink').click();
		await expect(card.getByTestId('ultrasignup-find')).toBeVisible();
		await expect(page.getByTestId('undo-bar')).toContainText('UltraSignup profile unlinked');
		await page.getByTestId('undo-action').click();
		await expect(card.getByTestId('ultrasignup-linked-as')).toContainText('#900001');
		expect(await storedPersonId(), 'an undone unlink never reached the row').toBe('900001');

		await card.getByTestId('ultrasignup-unlink').click();
		await page.getByTestId('undo-dismiss').click();
		await expect(page.getByTestId('undo-bar')).toBeHidden({ timeout: 5_000 });
		await expect.poll(storedPersonId).toBeNull();

		await searchFor(card, 'Alex', 'Sample');
		await card.getByTestId('ultrasignup-pick-900002').click();
		await expect(card.getByTestId('ultrasignup-linked-as')).toContainText('#900002', {
			timeout: 15_000
		});
		await expect.poll(storedPersonId).toBe('900002');
	});

	test('a double press searches once and links once', async ({ page, mockRoute }) => {
		let release!: () => void;
		const held = new Promise<void>((r) => (release = r));
		const seen = await stubFunction(page, mockRoute, {
			onLookup: async (route) => {
				await held;
				return reply(route, 200, { candidates: NAMESAKES });
			}
		});
		const linkWrites: string[] = [];
		page.on('request', (req) => {
			if (req.method() === 'POST' && req.url().includes('/rest/v1/integrations')) {
				linkWrites.push(req.url());
			}
		});

		const card = await openCard(page);
		await card.getByTestId('ultrasignup-first-name').fill('Alex');
		await card.getByTestId('ultrasignup-last-name').fill('Sample');
		const find = card.getByTestId('ultrasignup-find');
		await find.dblclick();
		await expect(find).toBeDisabled();
		await expect(find).toHaveText('Searching UltraSignup…');
		await card.getByTestId('ultrasignup-last-name').press('Enter');
		release();

		await expect(card.getByTestId('ultrasignup-candidate')).toHaveCount(2, { timeout: 15_000 });
		expect(seen.lookups).toHaveLength(1);

		await card.getByTestId('ultrasignup-pick-900001').dblclick();
		await expect(card.getByTestId('ultrasignup-linked-as')).toContainText('#900001', {
			timeout: 15_000
		});
		await expect.poll(storedPersonId).toBe('900001');
		expect(linkWrites).toHaveLength(1);
	});
});

test.describe('UltraSignup import — the linked person is gone', () => {
	test.use({ storageState: USER_A.storageStatePath });
	test.describe.configure({ mode: 'serial' });

	const raceName = `E2E UltraSignup Gone ${Date.now()}`;
	let listingId: string | null = null;

	test.beforeAll(async () => {
		listingId = await insertRaceListing({
			provider: 'ultrasignup',
			name: raceName,
			race_date: browserDate(40),
			distance_m: 160_934,
			provider_race_id: '500102'
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
		await deleteIntegration(USER_A.id, 'ultrasignup');
	});

	test('an import whose person UltraSignup no longer lists points back to Settings', async ({
		page,
		mockRoute
	}) => {
		await linkDirectly('900001');
		const seen = await stubFunction(page, mockRoute, {
			onImport: (route) => reply(route, 404, { error: 'ultrasignup_person_not_found' })
		});

		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		const race = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(race).toBeVisible({ timeout: 15_000 });
		await race.getByTestId('race-import').click();
		await expect(page.getByTestId('ultrasignup-linked-person')).toContainText('Alex Sample', {
			timeout: 15_000
		});
		await page.getByTestId('race-import-ultrasignup').click();

		await expect(
			page.getByText(
				'UltraSignup no longer lists your linked profile under that name. Link it again in Settings.'
			)
		).toBeVisible({ timeout: 15_000 });
		await expect(page.getByText("Couldn't import the result. Please try again.")).toHaveCount(0);
		// The modal stays open on the race: nothing was imported.
		await expect(page.getByTestId('race-import-ultrasignup')).toBeVisible();
		expect(seen.imports).toHaveLength(1);
		expect(seen.imports[0]).toMatchObject({ ultraSignUpPersonId: '900001' });
	});
});
