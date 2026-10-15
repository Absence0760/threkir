import { expect, test } from '../fixtures/test';

import { getAdminClient, getUserClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { insertRun } from '../fixtures/simulate';

/**
 * A linked coach sees the athlete's run map, clipped (decisions § 1968).
 *
 *   - The coach's review page draws a map for the athlete's private run.
 *   - What clip-public-track serves the coach is the track with the athlete's
 *     privacy zone trimmed out — two of three points — never the raw three.
 *   - A signed-in stranger asking for the same run gets a 404, and so does a
 *     coach once the link has ended.
 *
 * Saga users throughout, so the seeded coach links and privacy zones the other
 * coaching specs read are never touched. seed.sql opens the coach_run_map gate.
 */
test.describe('coach run map — clipped, and only through an active link', () => {
	test.describe.configure({ timeout: 90_000 });

	let users: SagaUser[];
	let athlete: SagaUser;
	let coach: SagaUser;
	let stranger: SagaUser;
	let runId: string;

	test.beforeAll(async () => {
		const stamp = Date.now().toString(36);
		users = await createSagaUsers(3, {
			displayNames: [
				`CoachMap Athlete ${stamp}`,
				`CoachMap Coach ${stamp}`,
				`CoachMap Stranger ${stamp}`,
			],
		});
		[athlete, coach, stranger] = users;
		const admin = getAdminClient();

		const { error: zoneErr } = await admin.from('user_settings').upsert({
			user_id: athlete.id,
			prefs: { privacy_zones: [{ lat: -33.86, lng: 151.21, radius_m: 150 }] },
		});
		if (zoneErr) throw new Error(`zone setup failed: ${zoneErr.message}`);

		const { error: linkErr } = await admin.from('coach_athletes').insert({
			coach_id: coach.id,
			athlete_id: athlete.id,
			status: 'active',
			invite_token: `coachmap${stamp}`.padEnd(32, '0'),
			accepted_at: new Date().toISOString(),
		});
		if (linkErr) throw new Error(`link setup failed: ${linkErr.message}`);

		runId = await insertRun({
			user_id: athlete.id,
			started_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
			distance_m: 2_000,
			duration_s: 600,
			is_public: false,
			track: [
				{ lat: -33.86, lng: 151.21, ele: 8, ts: '2026-10-01T07:00:00Z' },
				{ lat: -33.87, lng: 151.22, ele: 9, ts: '2026-10-01T07:03:00Z' },
				{ lat: -33.88, lng: 151.23, ele: 10, ts: '2026-10-01T07:06:00Z' },
			],
		});
	});

	test.afterAll(async () => {
		if (users) await deleteSagaUsers(users);
	});

	async function clip(user: SagaUser): Promise<{ status: number; points: unknown[] | null }> {
		const client = await getUserClient({ email: user.email, password: user.password });
		const { data } = await client.auth.getSession();
		const token = data.session?.access_token;
		if (!token) throw new Error(`no session for ${user.displayName}`);
		const { url, anonKey } = loadSupabaseEnv();
		const res = await fetch(`${url}/functions/v1/clip-public-track`, {
			method: 'POST',
			headers: {
				'content-type': 'application/json',
				apikey: anonKey,
				Authorization: `Bearer ${token}`,
			},
			body: JSON.stringify({ run_id: runId }),
		});
		const json = (await res.json().catch(() => null)) as { points?: unknown[] } | null;
		return { status: res.status, points: Array.isArray(json?.points) ? json.points : null };
	}

	test('the coach page draws the athlete run map', async ({ browser }) => {
		const ctx = await browser.newContext({ storageState: coach.storageStatePath });
		await ctx.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
		const page = await ctx.newPage();
		const served = page.waitForResponse(
			(r) => r.url().includes('/functions/v1/clip-public-track') && r.request().method() === 'POST'
		);
		await page.goto(`/coaching/athletes/${athlete.id}`);
		await expect(page.getByTestId('coach-run-map')).toHaveCount(1, { timeout: 15_000 });
		const res = await served;
		expect(res.status()).toBe(200);
		const body = (await res.json()) as { points: unknown[] };
		expect(body.points).toHaveLength(2);
		await ctx.close();
	});

	test('the coach is served the clipped track, a stranger nothing', async () => {
		const asCoach = await clip(coach);
		expect(asCoach.status).toBe(200);
		expect(asCoach.points).toHaveLength(2);

		const asStranger = await clip(stranger);
		expect(asStranger.status).toBe(404);
	});

	test('ending the link ends the map', async () => {
		const admin = getAdminClient();
		const { error } = await admin
			.from('coach_athletes')
			.update({ status: 'ended', ended_at: new Date().toISOString() })
			.eq('coach_id', coach.id)
			.eq('athlete_id', athlete.id);
		if (error) throw new Error(`ending the link failed: ${error.message}`);

		const asCoach = await clip(coach);
		expect(asCoach.status).toBe(404);
	});
});
