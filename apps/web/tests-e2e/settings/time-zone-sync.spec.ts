import { expect, test } from '../fixtures/test';

import { readMaybeRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The browser writes its IANA zone into the `time_zone` universal pref after
 * sign-in (issue #1182), which coach_roster_summary reads to pick the
 * athlete's current plan by the athlete's local date. A browser in a new zone
 * overwrites the stored one (that it writes nothing when the zone is unchanged
 * is unit-tested in settings/time_zone.test.ts). A zone Postgres does not know
 * is refused by the server, and the stored value survives the refusal.
 *
 * Runs as a throwaway user, in browser contexts pinned to their own zones
 * rather than the suite-wide UTC.
 */

let runner: SagaUser;

test.beforeAll(async () => {
	[runner] = await createSagaUsers(1, { displayNames: ['Zone Runner'] });
});

test.afterAll(async () => {
	await deleteSagaUsers([runner].filter(Boolean));
});

async function storedZone(): Promise<string | null> {
	const row = await readMaybeRow(
		"the runner's universal prefs",
		getAdminClient().from('user_settings').select('prefs').eq('user_id', runner.id).maybeSingle(),
	);
	const zone = ((row?.prefs ?? {}) as Record<string, unknown>).time_zone;
	return typeof zone === 'string' ? zone : null;
}

test('the browser zone is written after sign-in and follows a move', async ({ browser }) => {
	for (const zone of ['Pacific/Auckland', 'America/Denver']) {
		const context = await browser.newContext({ storageState: runner.storageStatePath, timezoneId: zone });
		const page = await context.newPage();
		try {
			await page.goto('/dashboard');
			await expect.poll(storedZone, { timeout: 15_000 }).toBe(zone);
		} finally {
			await context.close();
		}
	}
});

test('a zone the server does not know is refused and the stored one kept', async () => {
	const admin = getAdminClient();
	const seed = await admin
		.from('user_settings')
		.upsert({ user_id: runner.id, prefs: { time_zone: 'Europe/Paris' } }, { onConflict: 'user_id' });
	expect(seed.error).toBeNull();
	const { error } = await admin
		.from('user_settings')
		.upsert({ user_id: runner.id, prefs: { time_zone: 'Mars/Olympus_Mons' } }, { onConflict: 'user_id' });
	expect(error?.code).toBe('22023');
	expect(await storedZone()).toBe('Europe/Paris');
});
