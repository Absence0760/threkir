import { expect, test } from '../fixtures/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { deleteRun, insertLivePings } from '../fixtures/simulate';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * The streamer overlay (decisions § 2265) and heart rate on the spectator page.
 *
 * The overlay reads `live_overlay_feed` with the token in the fragment. The
 * server returns only pings older than the creator's delay, coordinates only
 * with the trace on, and bpm only with heart rate on AND health-data consent;
 * these specs drive the real stack so a delay done in the browser would fail.
 *
 * Runs as a saga user: token creation spends the `create_live_overlay_token`
 * bucket, and consent is flipped on this user only. Points are in Melbourne,
 * clear of the Sydney seed privacy zone. Every timestamp is an instant
 * relative to now, never a calendar day.
 */

const SPOT = { lat: -37.8, lng: 144.96 };
const OVERLAY_URL = /\/live\/overlay\?stats=distance,pace,elapsed,hr&units=(km|mi)&layout=row(&map=1)?#[A-Za-z0-9_-]{24}$/;

function agoIso(seconds: number): string {
	return new Date(Date.now() - seconds * 1000).toISOString();
}

async function setConsent(userId: string, on: boolean) {
	const { error } = await getAdminClient()
		.from('user_profiles')
		.update({ health_data_consent_at: on ? new Date().toISOString() : null })
		.eq('id', userId);
	if (error) throw new Error(`consent update failed: ${error.message}`);
}

async function liveRun(userId: string, isPublic: boolean): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('runs')
		.insert({
			user_id: userId,
			started_at: agoIso(600),
			duration_s: 0,
			distance_m: 0,
			source: 'app',
			is_public: isPublic,
			metadata: { in_progress: true },
		})
		.select('id')
		.single();
	if (error || !data) throw new Error(`seed run failed: ${error?.message}`);
	return data.id as string;
}

test.describe('/live/overlay — the streamer overlay (anon)', () => {
	test.describe.configure({ mode: 'serial' });
	test.use({ storageState: { cookies: [], origins: [] } });

	let users: SagaUser[] = [];
	let runId = '';
	let token = '';

	test.beforeAll(async () => {
		users = await createSagaUsers(1);
		const owner = users[0];
		await setConsent(owner.id, true);
		runId = await liveRun(owner.id, false);
		await insertLivePings({
			run_id: runId,
			user_id: owner.id,
			points: [
				{ ...SPOT, distance_m: 1000, elapsed_s: 300, at: agoIso(150), bpm: 148 },
				{ lat: SPOT.lat + 0.001, lng: SPOT.lng, distance_m: 1100, elapsed_s: 330, at: agoIso(120), bpm: 150 },
				{ lat: SPOT.lat + 0.002, lng: SPOT.lng, distance_m: 1250, elapsed_s: 390, at: agoIso(90), bpm: 152 },
				{ lat: SPOT.lat + 0.003, lng: SPOT.lng, distance_m: 1990, elapsed_s: 600, at: agoIso(5), bpm: 171 },
			],
		});
		const client = await getUserClient({ email: owner.email, password: owner.password });
		const { data, error } = await client.rpc('create_live_overlay_token');
		if (error || typeof data !== 'string') throw new Error(`token failed: ${error?.message}`);
		token = data;
		const { error: sErr } = await client.rpc('update_live_overlay_settings', {
			p_delay_s: 60,
			p_show_map: false,
			p_show_heart_rate: false,
		});
		if (sErr) throw new Error(`settings failed: ${sErr.message}`);
	});

	test.afterAll(async () => {
		if (runId) await deleteRun(runId);
		await deleteSagaUsers(users);
	});

	test('the private run streams with the server delay, no trace and no heart rate', async ({ page }) => {
		await page.goto(`/live/overlay?stats=distance,pace,elapsed,hr#${token}`);
		const overlay = page.getByTestId('live-overlay');
		await expect(overlay.getByTestId('overlay-distance')).toContainText('1.25 km');
		await expect(overlay.getByTestId('overlay-elapsed')).toContainText('6:30');
		await expect(overlay).not.toContainText('1.99');
		await expect(overlay.getByTestId('overlay-trace')).toHaveCount(0);
		await expect(overlay.getByTestId('overlay-heart-rate')).toHaveCount(0);
		await expect(page.locator('body')).toHaveCSS('background-color', 'rgba(0, 0, 0, 0)');
		await expect(page.getByRole('dialog')).toHaveCount(0);
	});

	test('the trace and heart rate appear only once the creator turns them on', async ({ page }) => {
		const owner = users[0];
		const client = await getUserClient({ email: owner.email, password: owner.password });
		const { error } = await client.rpc('update_live_overlay_settings', {
			p_delay_s: 60,
			p_show_map: true,
			p_show_heart_rate: true,
		});
		if (error) throw new Error(`settings failed: ${error.message}`);

		await page.goto(`/live/overlay?units=mi&map=1#${token}`);
		const overlay = page.getByTestId('live-overlay');
		await expect(overlay.getByTestId('overlay-trace')).toBeVisible();
		await expect(overlay.getByTestId('overlay-heart-rate')).toContainText('152 bpm');
		await expect(overlay.getByTestId('overlay-distance')).toContainText('yd');
		await expect(overlay).not.toContainText('171');
	});

	test('a wrong token waits, and a missing one says the link is incomplete', async ({ page }) => {
		await page.goto('/live/overlay#AAAAAAAAAAAAAAAAAAAAAAAA');
		await expect(page.getByTestId('overlay-waiting')).toBeVisible();
		await expect(page.getByTestId('overlay-distance')).toHaveCount(0);

		await page.goto('/live/overlay');
		await expect(page.getByTestId('overlay-bad-link')).toBeVisible();
	});
});

test.describe('/live/[id] — heart rate for spectators (anon)', () => {
	test.describe.configure({ mode: 'serial' });
	test.use({ storageState: { cookies: [], origins: [] } });

	let users: SagaUser[] = [];
	let runId = '';

	test.beforeAll(async () => {
		users = await createSagaUsers(1);
		runId = await liveRun(users[0].id, true);
	});

	test.afterAll(async () => {
		if (runId) await deleteRun(runId);
		await deleteSagaUsers(users);
	});

	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
	});

	test('without health-data consent the stored ping keeps no bpm and none is shown', async ({ page }) => {
		await setConsent(users[0].id, false);
		await insertLivePings({
			run_id: runId,
			user_id: users[0].id,
			points: [{ ...SPOT, distance_m: 500, elapsed_s: 150, at: agoIso(20), bpm: 140 }],
		});
		await page.goto(`/live/${runId}`);
		await expect(page.getByTestId('live-distance')).toContainText('500');
		await expect(page.getByTestId('live-heart-rate')).toHaveCount(0);
	});

	test('with consent the spectator page shows the runner’s heart rate', async ({ page }) => {
		await setConsent(users[0].id, true);
		await insertLivePings({
			run_id: runId,
			user_id: users[0].id,
			points: [{ lat: SPOT.lat + 0.001, lng: SPOT.lng, distance_m: 700, elapsed_s: 210, at: agoIso(10), bpm: 156 }],
		});
		await page.goto(`/live/${runId}`);
		await expect(page.getByTestId('live-heart-rate')).toContainText('156 bpm');
	});
});

test.describe('Settings → Privacy — streamer overlay card', () => {
	let users: SagaUser[] = [];

	test.beforeAll(async () => {
		users = await createSagaUsers(1);
	});

	test.afterAll(async () => {
		await deleteSagaUsers(users);
	});

	test('create, restyle, a failed save reverts, replace and turn off', async ({ browser, mockRoute }) => {
		const ctx = await browser.newContext({ storageState: users[0].storageStatePath });
		const page = await ctx.newPage();
		await page.goto('/settings/privacy');

		const card = page.getByTestId('streamer-overlay-card');
		await card.getByTestId('streamer-overlay-create').click();
		const url = card.getByTestId('streamer-overlay-url');
		await expect(url).toHaveValue(OVERLAY_URL);
		const first = await url.inputValue();

		await card.getByTestId('streamer-overlay-units-mi').check();
		await expect(url).toHaveValue(/units=mi/);
		await card.getByTestId('streamer-overlay-stat-hr').uncheck();
		await expect(url).toHaveValue(/stats=distance,pace,elapsed&/);

		// Health-data consent is off for a fresh user, so heart rate cannot be
		// turned on from here.
		await expect(card.getByTestId('streamer-overlay-heart-rate')).toBeDisabled();

		await mockRoute(page, '**/rest/v1/rpc/update_live_overlay_settings', (route) =>
			route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }),
		);
		await card.getByTestId('streamer-overlay-map').check();
		await expect(card.getByTestId('streamer-overlay-error')).toBeVisible();
		await expect(card.getByTestId('streamer-overlay-map')).not.toBeChecked();
		await expect(url).not.toHaveValue(/map=1/);
		await page.unroute('**/rest/v1/rpc/update_live_overlay_settings');

		// The URL updates before the save lands; reload only once it has, or the
		// reload can read the row the save has not written yet.
		const saved = page.waitForResponse(
			(r) => r.url().includes('/rest/v1/rpc/update_live_overlay_settings') && r.ok(),
		);
		await card.getByTestId('streamer-overlay-map').check();
		await saved;
		await expect(url).toHaveValue(/map=1/);
		await page.reload();
		await expect(card.getByTestId('streamer-overlay-map')).toBeChecked();
		await expect(card.getByTestId('streamer-overlay-delay')).toHaveValue('60');

		await card.getByTestId('streamer-overlay-replace').click();
		await page.getByRole('dialog').getByRole('button', { name: 'Replace link' }).click();
		await expect(url).not.toHaveValue(new RegExp(first.split('#')[1]));
		await expect(url).toHaveValue(/#[A-Za-z0-9_-]{24}$/);

		await card.getByTestId('streamer-overlay-revoke').click();
		await page.getByRole('dialog').getByRole('button', { name: 'Turn off' }).click();
		await expect(card.getByTestId('streamer-overlay-create')).toBeVisible();
		await page.reload();
		await expect(card.getByTestId('streamer-overlay-create')).toBeVisible();
		await ctx.close();
	});
});
