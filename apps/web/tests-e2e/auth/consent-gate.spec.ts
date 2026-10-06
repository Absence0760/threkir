import { expect, test } from '@playwright/test';

import { readRow } from '../fixtures/db-read';
import { signIn } from '../fixtures/helpers';
import { getAdminClient } from '../fixtures/local-supabase';

/**
 * The root layout's GDPR Art 8 consent gate (issue #1065).
 *
 * An account can reach the app without ever recording the age affirmation
 * and terms acceptance: an OAuth sign-in from a client that skipped the
 * sign-in hop, a tab closed on /auth/confirm-age, or a user created with no
 * `user_profiles` row at all. The last case also broke the profile bootstrap:
 * `get_my_profile()` answered an all-null object for a missing row, the auth
 * store read that as "row present", and the row was never created.
 *
 * This user starts with NO profile row and signs in with a password, so the
 * only things that can route them to the gate are the bootstrap (which must
 * now create the row) and the layout gate (which must then see no consent).
 */
test.describe('Consent gate', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('an account with no profile row is bootstrapped and held at /auth/confirm-age until it consents', async ({
		page
	}) => {
		const admin = getAdminClient();
		const email = `consent-gate-${Date.now()}@test.com`;
		const password = 'consent-gate-pass';
		const { data: created, error: createErr } = await admin.auth.admin.createUser({
			email,
			password,
			email_confirm: true
		});
		if (createErr || !created?.user) throw createErr ?? new Error('createUser failed');
		const userId = created.user.id;

		try {
			await signIn(page, { email, password, id: userId, tier: 'free', storageStatePath: '' });
			await page.waitForURL('**/auth/confirm-age');

			// readRow throws when the row is absent: the auth store must have
			// created it.
			const bootstrapped = await readRow(
				'bootstrapped user_profiles row',
				admin
					.from('user_profiles')
					.select('id, age_confirmed_at, terms_accepted_at')
					.eq('id', userId)
					.single()
			);
			expect(bootstrapped.age_confirmed_at).toBeNull();
			expect(bootstrapped.terms_accepted_at).toBeNull();

			// A feature surface bounces back to the gate...
			await page.goto('/dashboard');
			await page.waitForURL('**/auth/confirm-age');
			// ...but the legal pages stay readable before accepting them.
			await page.goto('/privacy');
			await expect(page.getByRole('heading', { level: 1, name: 'Privacy Policy' })).toBeVisible();
			expect(new URL(page.url()).pathname).toBe('/privacy');

			await page.goto('/auth/confirm-age');
			const continueButton = page.getByRole('button', { name: 'Continue' });
			await expect(continueButton).toBeDisabled();
			const boxes = page.getByRole('checkbox');
			await boxes.nth(0).check();
			await boxes.nth(1).check();
			await continueButton.click();

			// The row has no onboarded_at, so the next gate in line takes over.
			await page.waitForURL('**/onboarding');

			const stamped = await readRow(
				'stamped user_profiles row',
				admin
					.from('user_profiles')
					.select('age_confirmed_at, terms_accepted_at')
					.eq('id', userId)
					.single()
			);
			expect(stamped.age_confirmed_at).not.toBeNull();
			expect(stamped.terms_accepted_at).not.toBeNull();
		} finally {
			await admin.auth.admin.deleteUser(userId);
		}
	});
});
