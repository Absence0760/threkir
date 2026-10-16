import { expect, test } from '../fixtures/test';

import { readMaybeRow, readRow } from '../fixtures/db-read';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_C_PRO } from '../fixtures/users';

/**
 * /clubs/join/[token] on a club that requires the activity-risk
 * acknowledgement (§ 1864). `join_club_by_token` refuses the bare
 * token with `activity_waiver_required`, so the page must stop on an
 * acknowledgement step instead of an error, keep Continue disabled until the
 * box is ticked, and only then admit the member with the acknowledgement
 * recorded server-side.
 *
 * The club is planted per test (owned by runner, joined by morgan) so the
 * shared Friends-of-Jared fixture other invite specs redeem stays waiver-free.
 */

let clubId: string | null = null;

test.describe('/clubs/join/[token] — activity-risk acknowledgement', () => {
	test.use({ storageState: USER_C_PRO.storageStatePath });

	test.afterEach(async () => {
		if (!clubId) return;
		await getAdminClient().from('clubs').delete().eq('id', clubId);
		clubId = null;
	});

	test('stops on the acknowledgement, then joins with it recorded', async ({ page }) => {
		const admin = getAdminClient();
		const suffix = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		const token = `waiver-e2e-${suffix}`;
		const slug = `waiver-invite-${suffix}`;
		const { data, error } = await admin
			.from('clubs')
			.insert({
				owner_id: USER_A.id,
				name: `Waiver Invite ${suffix}`,
				slug,
				is_public: false,
				join_policy: 'invite',
				invite_token: token,
				requires_activity_waiver: true,
			})
			.select('id')
			.single();
		if (error || !data) throw new Error(`seed club insert failed: ${error?.message}`);
		const id = data.id;
		clubId = id;

		await page.goto(`/clubs/join/${token}`);

		const step = page.getByTestId('invite-waiver');
		await expect(step).toBeVisible({ timeout: 15_000 });
		const accept = step.getByRole('button', { name: 'Accept and join' });
		await expect(accept).toBeDisabled();

		const before = await readMaybeRow(
			'club_members by club_id+user_id',
			admin
				.from('club_members')
				.select('user_id')
				.eq('club_id', id)
				.eq('user_id', USER_C_PRO.id)
				.maybeSingle(),
		);
		expect(before).toBeNull();

		await step.getByRole('checkbox').check();
		await accept.click();

		await page.waitForURL(new RegExp(`/clubs/${slug}$`), { timeout: 15_000 });

		const after = await readRow(
			'club_members by club_id+user_id',
			admin
				.from('club_members')
				.select('status, activity_waiver_ack_at')
				.eq('club_id', id)
				.eq('user_id', USER_C_PRO.id)
				.single(),
		);
		expect(after.status).toBe('active');
		expect(after.activity_waiver_ack_at).not.toBeNull();
	});
});
