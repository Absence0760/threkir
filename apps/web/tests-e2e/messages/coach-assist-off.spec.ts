import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';

/**
 * The coach assistant (issue #1215 Phase 4) ships behind
 * PUBLIC_COACH_ASSIST_ENABLED, off in every environment until the CISO +
 * counsel sign-off. This lane runs with it off: an athlete sees no consent
 * toggle on /coaching and a coach sees no draft panel in the conversation.
 * The on state is configured/coach-assist.spec.ts.
 */
test.describe.configure({ mode: 'serial', timeout: 90_000 });

test.describe('the coach assistant is off by default', () => {
	const admin = getAdminClient();
	let athlete: SagaUser;
	let coach: SagaUser;
	const stamp = Date.now();

	test.beforeAll(async () => {
		[athlete, coach] = await createSagaUsers(2, {
			displayNames: ['Assist Off Athlete', 'Assist Off Coach'],
		});
		const { error } = await admin.from('coach_athletes').insert({
			coach_id: coach.id,
			athlete_id: athlete.id,
			status: 'active',
			invite_token: `e2e-assist-off-${stamp}`,
			accepted_at: new Date().toISOString(),
		});
		if (error) throw error;
	});

	test.afterAll(async () => {
		if (athlete && coach) {
			await admin.from('coach_athletes').delete().eq('coach_id', coach.id);
			await deleteSagaUsers([athlete, coach]);
		}
	});

	test('no consent toggle for the athlete, no draft panel for the coach', async ({ browser }) => {
		const a = await browser.newContext({ storageState: athlete.storageStatePath });
		const ap = await a.newPage();
		await ap.goto('/coaching');
		await expect(ap.getByText('Assist Off Coach')).toBeVisible({ timeout: 15_000 });
		await expect(ap.getByTestId('coach-assist-consent')).toHaveCount(0);
		await a.close();

		const c = await browser.newContext({ storageState: coach.storageStatePath });
		const cp = await c.newPage();
		await cp.goto(`/messages/${athlete.id}`);
		await expect(cp.locator('.composer textarea')).toBeVisible({ timeout: 15_000 });
		await expect(cp.getByTestId('coach-assist-panel')).toHaveCount(0);
		await c.close();
	});
});
