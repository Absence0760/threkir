import { expect, test } from '../fixtures/test';

import { readMaybeRow } from '../fixtures/db-read';
import { setStorageOnLoad } from '../fixtures/helpers';
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

test('nothing is written when the settings read failed and the cache is cold', async ({ browser, mockRoute }) => {
	// Writing over a bag that came from neither the server nor the cache would
	// seed the cache with a bag holding no privacy zones, which the share paths
	// then read as "no zones set" (runs/detail.spec.ts pins that refusal).
	const seed = await getAdminClient()
		.from('user_settings')
		.upsert({ user_id: runner.id, prefs: { time_zone: 'Europe/Paris' } }, { onConflict: 'user_id' });
	expect(seed.error).toBeNull();
	const context = await browser.newContext({ storageState: runner.storageStatePath, timezoneId: 'Asia/Tokyo' });
	const page = await context.newPage();
	let reads = 0;
	const writes: string[] = [];
	try {
		await setStorageOnLoad(page, { removeLocalPrefixes: ['settings_cache_'] });
		await mockRoute(page, '**/rest/v1/user_settings*', (route) => {
			if (route.request().method() === 'GET') {
				reads++;
				return route.abort();
			}
			writes.push(route.request().method());
			return route.continue();
		});
		await page.goto('/dashboard');
		// postgrest-js retries a failed GET three times, 1, 2 and 4 s apart, and
		// more than one load reads the bag. Once the reads have stopped every
		// load has given up, and any write one went on to make has been sent by
		// the time the network is idle.
		let seen = -1;
		await expect
			.poll(
				() => {
					const settled = reads >= 4 && reads === seen;
					seen = reads;
					return settled;
				},
				{ intervals: [5_000], timeout: 40_000 },
			)
			.toBe(true);
		await page.waitForLoadState('networkidle');
		expect(writes).toEqual([]);
		expect(await storedZone()).toBe('Europe/Paris');
		const cached = await page.evaluate(() =>
			Object.keys(localStorage).filter((k) => k.startsWith('settings_cache_universal_')),
		);
		expect(cached).toEqual([]);
	} finally {
		await context.close();
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
