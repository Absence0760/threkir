import { expect, test } from '../fixtures/test';

import { getAdminClient, getUserClient } from '../fixtures/local-supabase';
import {
	clearUserSettingKey,
	deleteRun,
	insertLivePings,
	setUserSetting,
} from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * /live/[id] on the safety-contacts-only audience (decisions § 1964).
 *
 * The run is private and never flips public. Its only reader besides the
 * runner is whoever holds the per-contact link the escalation emails — the
 * token in the URL fragment, checked by `safety_live_run` /
 * `safety_live_pings`. So the same URL without the fragment must show the
 * not-broadcasting state, a wrong token the closed-link state, and the real
 * one the live feed.
 *
 * Seed: the gate row is opened by seed.sql for local + CI. Points are in
 * Melbourne, clear of the Sydney seed privacy zone.
 */

const SPOT = { lat: -37.8, lng: 144.96 };
const CONTACT_EMAIL = 'safety-audience-e2e@example.invalid';

test.describe('/live/[id] — safety-contacts link (anon)', () => {
	test.describe.configure({ mode: 'serial' });
	test.use({ storageState: { cookies: [], origins: [] } });

	let runId = '';
	let contactId = '';
	let token = '';

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const { data: run, error: runErr } = await admin
			.from('runs')
			.insert({
				user_id: USER_A.id,
				started_at: new Date(Date.now() - 10 * 60 * 1000).toISOString(),
				duration_s: 0,
				distance_m: 0,
				source: 'app',
				is_public: false,
				safety_audience: true,
				metadata: { in_progress: true },
			})
			.select('id, safety_audience')
			.single();
		if (runErr || !run) throw new Error(`seed run failed: ${runErr?.message}`);
		expect(run.safety_audience, 'the seed must open the safety_audience gate').toBe(true);
		runId = run.id as string;

		await admin.from('safety_contacts').delete().eq('owner_id', USER_A.id).eq('contact_email', CONTACT_EMAIL);
		const { data: contact, error: cErr } = await admin
			.from('safety_contacts')
			.insert({ owner_id: USER_A.id, contact_email: CONTACT_EMAIL })
			.select('id')
			.single();
		if (cErr || !contact) throw new Error(`seed contact failed: ${cErr?.message}`);
		contactId = contact.id as string;
		await admin
			.from('safety_contacts')
			.update({ confirmed_at: new Date().toISOString() })
			.eq('id', contactId);

		await insertLivePings({
			run_id: runId,
			user_id: USER_A.id,
			points: [0, 1, 2, 3].map((i) => ({
				lat: SPOT.lat + i * 0.0005,
				lng: SPOT.lng,
				distance_m: 1_000 + i * 55,
				elapsed_s: 300 + i * 15,
				at: new Date(Date.now() - (4 - i) * 5_000).toISOString(),
			})),
		});

		await setUserSetting(USER_A.id, 'safety_off_route_alerts', true);
		const runner = await getUserClient({ email: USER_A.email, password: USER_A.password });
		const { data: escalated, error: eErr } = await runner.rpc('escalate_run_off_route', {
			p_run_id: runId,
		});
		if (eErr || escalated !== true) throw new Error(`escalation failed: ${eErr?.message}`);

		const { data: jobs } = await admin
			.from('jobs')
			.select('payload')
			.eq('kind', 'safety_email')
			.eq('payload->>run_id', runId)
			.eq('payload->>contact_email', CONTACT_EMAIL);
		token = ((jobs?.[0]?.payload as Record<string, unknown> | undefined)?.view_token as string) ?? '';
		expect(token, 'the escalation email must carry the contact link').toMatch(/^[0-9a-f-]{36}$/);
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		await clearUserSettingKey(USER_A.id, 'safety_off_route_alerts');
		if (runId) {
			await admin.from('jobs').delete().eq('payload->>run_id', runId);
			await deleteRun(runId);
		}
		if (contactId) await admin.from('safety_contacts').delete().eq('id', contactId);
	});

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() }),
			);
		});
	});

	test('the run is never public: the bare link shows nothing', async ({ page }) => {
		const admin = getAdminClient();
		const { data } = await admin.from('runs').select('is_public').eq('id', runId).single();
		expect(data?.is_public).toBe(false);

		await page.goto(`/live/${runId}`);
		await expect(page.getByRole('heading', { name: "This run isn't broadcasting" })).toBeVisible();
		await expect(page.getByTestId('safety-notice')).toHaveCount(0);
	});

	test('the contact link shows the live feed and says who it is for', async ({ page }) => {
		await page.goto(`/live/${runId}#k=${token}`);
		await expect(page.getByTestId('safety-notice')).toBeVisible();
		await expect(page.getByTestId('safety-notice')).toContainText('Safety contacts only');
		await expect(page.getByTestId('live-distance')).not.toContainText('0.00');
		await expect(page.getByRole('heading', { name: "This run isn't broadcasting" })).toHaveCount(0);
	});

	test('a wrong token opens nothing', async ({ page }) => {
		await page.goto(`/live/${runId}#k=00000000-0000-4000-8000-000000000000`);
		await expect(page.getByTestId('safety-link-closed')).toBeVisible();
		await expect(page.getByTestId('live-distance')).toHaveCount(0);
	});

	test('stopping the share closes the link', async ({ page }) => {
		const admin = getAdminClient();
		await admin.from('runs').update({ concluded_at: new Date().toISOString() }).eq('id', runId);
		await page.goto(`/live/${runId}#k=${token}`);
		await expect(page.getByTestId('safety-link-closed')).toBeVisible();
	});
});
