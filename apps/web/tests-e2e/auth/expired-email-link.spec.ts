import { expect, test } from '../fixtures/test';

/**
 * An emailed sign-in, confirmation or reset link opened after it expired
 * (or a second time) makes GoTrue redirect to /auth/callback with
 * `error_code=otp_expired`. The callback used to print GoTrue's own
 * "Email link is invalid or has expired"; it now says what to do next.
 */

const EXPIRED =
	'/auth/callback#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired';

test('an expired email link asks for a new one and offers the way back', async ({ page }) => {
	await page.goto(EXPIRED);

	await expect(
		page.getByRole('alert').filter({ hasText: 'That link has expired or was already used' }),
	).toBeVisible();
	await expect(page.getByRole('alert')).not.toContainText('Authentication failed');
	await expect(page).toHaveURL(/\/auth\/callback$/);
	await expect(page.getByRole('link', { name: /back to login/i })).toBeVisible();
});
