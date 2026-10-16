import { expect, test } from '../fixtures/test';
import type { Route } from '@playwright/test';

import { browserDate } from '../fixtures/dates';
import { deleteIntegration, deleteRaceListing, insertRaceListing } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * UltraSignup's person flow end to end (decisions § 1841): find yourself by
 * name in Settings, pick the right one of the same-named people, and the
 * race calendar then imports as that person with nothing typed.
 *
 * Only the Edge Function is stubbed — its probe, its lookup and its import —
 * because dev and CI leave the leg off and the real feed is a third party's.
 * The link itself is the real `integrations` write the panel makes under the
 * runner's own session, and the assertions are on the request body the
 * calendar actually sends with what it read back.
 */

const reply = (route: Route, status: number, payload: unknown) =>
	route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(payload) });

const stamp = Date.now();
const raceName = `E2E UltraSignup Person ${stamp}`;

const CANDIDATES = [
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

test.describe('UltraSignup — link a person, then import as them', () => {
	test.use({ storageState: USER_A.storageStatePath });
	// Both tests read and write the same user's one UltraSignup row.
	test.describe.configure({ mode: 'serial' });

	let listingId: string | null = null;

	test.beforeAll(async () => {
		await deleteIntegration(USER_A.id, 'ultrasignup');
		listingId = await insertRaceListing({
			provider: 'ultrasignup',
			name: raceName,
			race_date: browserDate(40),
			distance_m: 160_934,
			provider_race_id: '500101'
		});
	});

	test.afterAll(async () => {
		if (listingId) await deleteRaceListing(listingId);
		await deleteIntegration(USER_A.id, 'ultrasignup');
	});

	test('the picked person is who the calendar imports as', async ({ page, mockRoute }) => {
		const lookups: Record<string, unknown>[] = [];
		const imports: Record<string, unknown>[] = [];
		await mockRoute(page, '**/functions/v1/race-results-import', (route) => {
			const body = (route.request().postDataJSON() ?? {}) as Record<string, unknown>;
			if (body.probe === true) {
				// The probe only answers a client that says it speaks the person
				// flow; reply as the function would.
				return body.ultraSignUpFlow === 'person' || body.provider !== 'ultrasignup'
					? reply(route, 200, { configured: true })
					: reply(route, 503, { error: 'provider_not_configured', reason: 'client_unsupported' });
			}
			if (body.lookup === true) {
				lookups.push(body);
				return reply(route, 200, { candidates: CANDIDATES });
			}
			imports.push(body);
			return reply(route, 200, { imported: 1, skipped: 0, enriched: 0, complete: true });
		});

		// Settings: find by name, pick the right namesake.
		await page.goto('/settings/integrations');
		const card = page.getByTestId('ultrasignup-card');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card.getByTestId('ultrasignup-find')).toBeDisabled();
		await card.getByTestId('ultrasignup-first-name').fill('Alex');
		await card.getByTestId('ultrasignup-last-name').fill('Sample');
		await card.getByTestId('ultrasignup-find').click();

		await expect(card.getByTestId('ultrasignup-candidate')).toHaveCount(2, { timeout: 15_000 });
		expect(lookups[0]).toMatchObject({
			provider: 'ultrasignup',
			ultraSignUpFirstName: 'Alex',
			ultraSignUpLastName: 'Sample'
		});
		await card.getByTestId('ultrasignup-pick-900001').click();
		await expect(card.getByTestId('ultrasignup-linked-as')).toContainText('900001', {
			timeout: 15_000
		});

		// The calendar: nothing to type, and the import names the picked person.
		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		const race = page.getByTestId('race-card').filter({ hasText: raceName });
		await expect(race).toBeVisible({ timeout: 15_000 });
		await race.getByTestId('race-import').click();

		await expect(page.getByTestId('ultrasignup-linked-person')).toContainText('Alex Sample', {
			timeout: 15_000
		});
		await page.getByTestId('race-import-ultrasignup').click();

		await expect.poll(() => imports.length, { timeout: 15_000 }).toBeGreaterThan(0);
		expect(imports[0]).toMatchObject({
			provider: 'ultrasignup',
			listingId,
			ultraSignUpPersonId: '900001',
			ultraSignUpFirstName: 'Alex',
			ultraSignUpLastName: 'Sample'
		});
		// The retired athlete-id shape is gone from the wire.
		expect(imports[0]).not.toHaveProperty('ultraSignUpAthleteId');
	});

	test('without a link the calendar says where to make one', async ({ page, mockRoute }) => {
		await deleteIntegration(USER_A.id, 'ultrasignup');
		await mockRoute(page, '**/functions/v1/race-results-import', (route) =>
			reply(route, 200, { configured: true })
		);

		await page.goto('/races');
		await page.getByTestId('races-search').fill(raceName);
		await page
			.getByTestId('race-card')
			.filter({ hasText: raceName })
			.getByTestId('race-import')
			.click();

		const notLinked = page.getByTestId('ultrasignup-not-linked');
		await expect(notLinked).toBeVisible({ timeout: 15_000 });
		await expect(notLinked.getByRole('link')).toHaveAttribute(
			'href',
			'/settings/integrations#ultrasignup-link'
		);
		await expect(page.getByTestId('race-import-ultrasignup')).toBeDisabled();
	});
});
