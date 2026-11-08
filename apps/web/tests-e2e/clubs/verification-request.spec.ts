import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { deleteClub } from '../fixtures/simulate';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Club verification requests (issue #1190 § 2, migration 20271120000004,
 * decisions § 2398).
 *
 * The RLS, RPC and lock rules are pinned by club_verification_test.sql and the
 * proof checks by the Edge Function's Deno suites. This spec pins the two
 * pages on top: the club owner (USER_A) requests verification from the club
 * card and sees the DNS and file instructions carrying the request's token;
 * the email proof's landing page confirms on a click; the site admin (USER_A
 * is the seeded app_admin) approves from /admin/club-verification, which
 * badges the club, and removes the badge with a reason the owner then reads
 * on the card. A signed-in non-admin (USER_B) gets the not-authorized card.
 *
 * The DNS check itself needs the network, so the spec records a passing check
 * through the service-role writer the Edge Function uses, rather than calling
 * the function against a real domain.
 */

async function insertOwnedClub(): Promise<{ id: string; slug: string; name: string }> {
	const admin = getAdminClient();
	const id = crypto.randomUUID();
	const slug = `e2e-verify-${id.slice(0, 8)}`;
	const name = `E2E Verify ${id.slice(0, 8)}`;
	const { error } = await admin.from('clubs').insert({
		id,
		owner_id: USER_A.id,
		name,
		slug,
		is_public: true,
		website_url: `https://www.${slug}.example.org/about`,
	});
	if (error) throw new Error(`insertOwnedClub failed: ${error.message}`);
	return { id, slug, name };
}

async function pendingRequest(clubId: string): Promise<{ id: string; token: string; domain: string }> {
	const { data, error } = await getAdminClient()
		.from('club_verification_requests')
		.select('id, token, domain')
		.eq('club_id', clubId)
		.eq('status', 'pending')
		.single();
	if (error) throw new Error(`pendingRequest failed: ${error.message}`);
	return data;
}

test.describe('club verification — owner request and admin review', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let club: { id: string; slug: string; name: string } | null = null;

	test.afterEach(async () => {
		if (club) {
			try {
				await deleteClub(club.id);
			} catch (_) {
				/* best-effort */
			}
			club = null;
		}
	});

	test('the owner requests, proves, and the admin approves then revokes', async ({ page }) => {
		club = await insertOwnedClub();
		const domain = `${club.slug}.example.org`;

		await page.goto(`/clubs/${club.slug}`);
		const card = page.getByTestId('club-verification-card');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await expect(card).toContainText(domain);

		await card.getByTestId('club-verification-org').fill('E2E Marathon Association');
		await card.getByTestId('club-verification-submit').click();

		await expect(card.getByTestId('club-verification-pending')).toBeVisible();
		const request = await pendingRequest(club.id);
		expect(request.domain).toBe(domain);
		await expect(card.getByTestId('club-verification-txt-name')).toHaveText(`_threkir-verification.${domain}`);
		await expect(card.getByTestId('club-verification-txt-value')).toHaveText(`threkir-verification=${request.token}`);
		await expect(card.getByTestId('club-verification-proof')).toContainText('No proof found yet');

		// What the Edge Function records when the TXT record is found.
		const { error: recordError } = await getAdminClient().rpc('record_club_verification_check', {
			p_request_id: request.id,
			p_method: 'dns_txt',
			p_ok: true,
			p_detail: `TXT _threkir-verification.${domain}`,
		});
		expect(recordError).toBeNull();
		await page.reload();
		await expect(page.getByTestId('club-verification-proof')).toContainText('DNS record');

		// The review.
		await page.goto('/admin/club-verification');
		const row = page.locator(`[data-testid="club-verification-row"][data-club="${club.slug}"]`);
		await expect(row).toBeVisible({ timeout: 15_000 });
		await expect(row.getByTestId('club-verification-row-proof')).toContainText('DNS record');
		await row.getByTestId('club-verification-approve').click();
		const dialog = page.getByTestId('club-verification-action-dialog');
		await expect(dialog).toBeVisible();
		await dialog.getByTestId('club-verification-action-confirm').click();
		await expect(row).toHaveCount(0);

		await page.getByTestId('club-verification-tab-verified').click();
		const verifiedRow = page.locator(`[data-testid="club-verification-row"][data-club="${club.slug}"]`);
		await expect(verifiedRow).toBeVisible();

		await verifiedRow.getByTestId('club-verification-history').click();
		const history = page.getByTestId('club-verification-history-dialog');
		await expect(history).toContainText('Request submitted');
		await expect(history).toContainText('Approved');
		await page.keyboard.press('Escape');

		await page.goto(`/clubs/${club.slug}`);
		await expect(page.getByTestId('verified-badge').first()).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('club-verification-verified')).toContainText('E2E Marathon Association');

		// Removing the badge needs a reason, and the owner reads it.
		await page.goto('/admin/club-verification');
		await page.getByTestId('club-verification-tab-verified').click();
		const toRevoke = page.locator(`[data-testid="club-verification-row"][data-club="${club.slug}"]`);
		await toRevoke.getByTestId('club-verification-revoke').click();
		const revokeDialog = page.getByTestId('club-verification-action-dialog');
		await revokeDialog.getByTestId('club-verification-action-confirm').click();
		await expect(revokeDialog).toContainText('Give a reason');
		await revokeDialog.getByTestId('club-verification-action-text').fill('Impersonation report upheld');
		await revokeDialog.getByTestId('club-verification-action-confirm').click();
		await expect(toRevoke).toHaveCount(0);

		await page.goto(`/clubs/${club.slug}`);
		await expect(page.getByTestId('club-verification-last')).toContainText('Impersonation report upheld', {
			timeout: 15_000,
		});
		await expect(page.getByTestId('club-verification-form')).toBeVisible();
	});

	test('the email proof confirms on a click, once', async ({ page }) => {
		club = await insertOwnedClub();

		await page.goto(`/clubs/${club.slug}`);
		const card = page.getByTestId('club-verification-card');
		await card.getByTestId('club-verification-org').fill('E2E Email Org');
		await card.getByTestId('club-verification-submit').click();
		await expect(card.getByTestId('club-verification-pending')).toBeVisible({ timeout: 15_000 });

		await card.getByTestId('club-verification-local').fill('a@b');
		await card.getByTestId('club-verification-send').click();
		await expect(card.getByTestId('club-verification-email-result')).toContainText('before the @');

		await card.getByTestId('club-verification-local').fill('Hostmaster');
		await card.getByTestId('club-verification-send').click();
		await expect(card.getByTestId('club-verification-email-result')).toContainText(
			`hostmaster@${club.slug}.example.org`,
		);

		const { data: job, error } = await getAdminClient()
			.from('jobs')
			.select('payload')
			.eq('kind', 'club_verification_email')
			.eq('payload->>email', `hostmaster@${club.slug}.example.org`)
			.order('id', { ascending: false })
			.limit(1)
			.single();
		if (error) throw new Error(`job lookup failed: ${error.message}`);
		const token = (job.payload as { token: string }).token;

		await page.goto(`/club-verification/confirm#token=${token}`);
		const confirm = page.getByTestId('club-verification-confirm');
		await expect(confirm).toHaveAttribute('data-state', 'prompt');
		await confirm.getByTestId('club-verification-confirm-button').click();
		await expect(confirm).toHaveAttribute('data-state', 'success');
		await expect(confirm).toContainText(club.name);

		// A fresh load, as a second open of the mailed link is: a fragment-only
		// navigation would keep the confirmed page on screen.
		await page.goto('/');
		await page.goto(`/club-verification/confirm#token=${token}`);
		await page.getByTestId('club-verification-confirm-button').click();
		await expect(page.getByTestId('club-verification-confirm')).toHaveAttribute('data-state', 'failure');

		await page.goto(`/clubs/${club.slug}`);
		await expect(page.getByTestId('club-verification-proof')).toContainText('email at the domain', {
			timeout: 15_000,
		});
	});
});

test.describe('club verification — a non-admin', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('gets the not-authorized card on the review page', async ({ page }) => {
		await page.goto('/admin/club-verification');
		await expect(page.getByTestId('club-verification-not-authorized')).toBeVisible({ timeout: 15_000 });
		await expect(page.getByTestId('club-verification-row')).toHaveCount(0);
	});
});
