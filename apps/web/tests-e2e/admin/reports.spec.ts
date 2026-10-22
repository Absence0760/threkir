import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { RUNNER_PUBLIC_RUN_ID } from '../fixtures/seeded-data';
import { USER_A, USER_B } from '../fixtures/users';

/**
 * Admin moderation surface (/admin/reports, migration 20270104_001).
 *
 * USER_A (runner@test.com) is seeded as an app_admin in seed.sql;
 * USER_B (alex@test.com) is not. The DB is the real authorization
 * boundary — these specs pin the UX layer on top of it:
 *
 *   1. An admin sees the queue, opens a target, and resolves it →
 *      the reports leave the queue.
 *   2. A non-admin sees the not-authorized state and the queue RPC
 *      returns nothing to them.
 *
 * Reports are planted via the service-role client (bypasses the
 * submit_report rate limit + duplicate guard) and torn down after.
 */

// Two distinct reporters (runner + morgan) flag a third user (alex).
const REPORTER_ONE = USER_A.id;
const REPORTER_TWO = 'c3d4e5f6-a7b8-9012-cdef-345678901234'; // morgan
const TARGET_ID = USER_B.id; // alex

const plantedReportIds: string[] = [];

async function plantPendingReports(targetId: string) {
	const admin = getAdminClient();
	const { data, error } = await admin
		.from('reports')
		.insert([
			{ reporter_id: REPORTER_ONE, target_kind: 'user', target_id: targetId, reason: 'spam', notes: 'spammy dms', status: 'pending' },
			{ reporter_id: REPORTER_TWO, target_kind: 'user', target_id: targetId, reason: 'harassment', status: 'pending' },
		])
		.select('id');
	if (error) throw error;
	for (const r of data ?? []) plantedReportIds.push(r.id as string);
}

const plantedCommentIds: string[] = [];

test.afterEach(async () => {
	const admin = getAdminClient();
	if (plantedReportIds.length > 0) {
		await admin.from('reports').delete().in('id', plantedReportIds);
		plantedReportIds.length = 0;
	}
	if (plantedCommentIds.length > 0) {
		await admin.from('run_comments').delete().in('id', plantedCommentIds);
		plantedCommentIds.length = 0;
	}
});

test.describe('admin moderation — admin can triage the queue', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('admin sees the queue, resolves a target → it leaves the queue', async ({ page }) => {
		await plantPendingReports(TARGET_ID);

		await page.goto('/admin/reports');

		const row = page
			.getByTestId('admin-queue-row')
			.filter({ hasText: TARGET_ID.slice(0, 8) });
		await expect(row).toBeVisible();
		await expect(row).toContainText('2'); // two reports

		await row.click();

		const modal = page.getByTestId('admin-detail-modal');
		await expect(modal).toBeVisible();
		// Both individual reports show (reason chips, exact so the
		// "spammy dms" notes line doesn't also match "spam").
		await expect(modal.getByText('spam', { exact: true })).toBeVisible();
		await expect(modal.getByText('harassment', { exact: true })).toBeVisible();

		await modal.getByTestId('admin-resolution-input').fill('warned the user');
		await modal.getByTestId('admin-mark-reviewed').click();

		// ConfirmDialog → confirm.
		await page.getByTestId('admin-resolve-confirm').getByRole('button', { name: /reviewed/i }).click();

		// The target leaves the queue.
		await expect(
			page.getByTestId('admin-queue-row').filter({ hasText: TARGET_ID.slice(0, 8) }),
		).toHaveCount(0);

		// And the DB reflects the resolution.
		const admin = getAdminClient();
		const { data } = await admin
			.from('reports')
			.select('status, reviewed_by, resolution')
			.in('id', plantedReportIds);
		for (const r of data ?? []) {
			expect(r.status).toBe('reviewed');
			expect(r.reviewed_by).toBe(USER_A.id);
			expect(r.resolution).toBe('warned the user');
		}
	});

	test('the review panel is reachable by keyboard, not only by clicking the row',
		async ({ page }) => {
			// The row's onclick had no keyboard equivalent, and the only
			// focusable control in it was the target link — which navigates to
			// the reported CONTENT, not this panel. A keyboard-only moderator
			// could not review or resolve anything.
			await plantPendingReports(TARGET_ID);

			await page.goto('/admin/reports');

			const row = page
				.getByTestId('admin-queue-row')
				.filter({ hasText: TARGET_ID.slice(0, 8) });
			await expect(row).toBeVisible();

			const review = row.getByTestId('admin-queue-review');
			// Focusable, and activating it from the keyboard opens the panel.
			await review.focus();
			await expect(review).toBeFocused();
			await page.keyboard.press('Enter');

			await expect(page.getByTestId('admin-detail-modal')).toBeVisible();
		});

	test('the row target link still goes to the reported content, not the panel',
		async ({ page }) => {
			// The two destinations are different, which is exactly why the row
			// needed its own control rather than being made one big button.
			await plantPendingReports(TARGET_ID);

			await page.goto('/admin/reports');

			const row = page
				.getByTestId('admin-queue-row')
				.filter({ hasText: TARGET_ID.slice(0, 8) });
			await expect(row).toBeVisible();

			await expect(row.locator('a.target-link')).toHaveAttribute(
				'href',
				new RegExp(`/${TARGET_ID}$`)
			);
		});
});

test.describe('admin moderation — a comment report names its kind and opens its run', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the row reads Comment and links to the run the comment is on', async ({ page }) => {
		// The queue used to label every kind it had no arm for "Route" and link
		// `/clubs/<comment id>` — a missing club (decisions § 2225).
		const admin = getAdminClient();
		const { data: comment, error: commentError } = await admin
			.from('run_comments')
			.insert({ run_id: RUNNER_PUBLIC_RUN_ID, author_id: USER_B.id, body: `queue-kind ${Date.now()}` })
			.select('id')
			.single();
		if (commentError) throw commentError;
		plantedCommentIds.push(comment.id);
		const { data: report, error: reportError } = await admin
			.from('reports')
			.insert({ reporter_id: REPORTER_TWO, target_kind: 'comment', target_id: comment.id, reason: 'harassment', status: 'pending' })
			.select('id')
			.single();
		if (reportError) throw reportError;
		plantedReportIds.push(report.id);

		await page.goto('/admin/reports');

		const row = page.getByTestId('admin-queue-row').filter({ hasText: comment.id.slice(0, 8) });
		await expect(row).toBeVisible();
		await expect(row.locator('.kind')).toHaveText('Comment');
		await expect(row.locator('a.target-link')).toHaveAttribute(
			'href',
			`/runs/${RUNNER_PUBLIC_RUN_ID}`
		);
	});
});

test.describe('admin moderation — legal hold on a resolved report', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a resolved report is reachable from the Resolved tab and its hold toggles', async ({ page }) => {
		// A resolved report has left the pending queue, and it is the only kind
		// the retention purge can delete — so the hold has to be placeable from
		// here (decisions § 2231). The reporter is null: they deleted their
		// account and the report was kept.
		const targetId = crypto.randomUUID();
		const admin = getAdminClient();
		const { data, error } = await admin
			.from('reports')
			.insert({
				reporter_id: null,
				target_kind: 'route',
				target_id: targetId,
				reason: 'harassment',
				status: 'dismissed',
				reviewed_at: new Date().toISOString(),
			})
			.select('id')
			.single();
		if (error) throw error;
		plantedReportIds.push(data.id);

		await page.goto('/admin/reports');
		await page.getByTestId('admin-tab-resolved').click();

		const row = page.getByTestId('admin-resolved-row').filter({ hasText: targetId.slice(0, 8) });
		await expect(row).toBeVisible();
		await row.getByTestId('admin-resolved-review').click();

		const modal = page.getByTestId('admin-detail-modal');
		await expect(modal.getByText('Reporter deleted their account')).toBeVisible();
		await expect(modal.getByText(/Eligible for deletion from/)).toBeVisible();
		// Nothing is pending, so there is nothing to resolve.
		await expect(modal.getByTestId('admin-mark-reviewed')).toHaveCount(0);

		await modal.getByTestId('admin-legal-hold-toggle').click();
		await expect(modal.getByTestId('admin-legal-hold-badge')).toBeVisible();
		await expect(modal.getByText(/Eligible for deletion from/)).toHaveCount(0);
		const held = await admin.from('reports').select('legal_hold').eq('id', data.id).single();
		expect(held.data?.legal_hold).toBe(true);

		// Lifting is confirmed: without the hold the purge may delete it.
		await modal.getByTestId('admin-legal-hold-toggle').click();
		await page.getByTestId('admin-lift-hold-confirm').getByRole('button', { name: /lift legal hold/i }).click();
		await expect(modal.getByTestId('admin-legal-hold-badge')).toHaveCount(0);
		const lifted = await admin.from('reports').select('legal_hold').eq('id', data.id).single();
		expect(lifted.data?.legal_hold).toBe(false);
	});
});

test.describe('admin moderation — non-admin is locked out', () => {
	test.use({ storageState: USER_B.storageStatePath });

	test('non-admin sees the not-authorized state and no report data leaks', async ({ page }) => {
		await plantPendingReports(TARGET_ID);

		await page.goto('/admin/reports');

		// Chrome gate (am_i_admin → false) renders the locked-out state.
		await expect(page.getByTestId('admin-not-authorized')).toBeVisible();
		// The queue never renders, and no planted target id leaks into the DOM —
		// the server-side 42501 on fetch_pending_reports is the real boundary
		// (also pinned by admin_moderation_test.sql), so a non-admin sees nothing.
		await expect(page.getByTestId('admin-queue')).toHaveCount(0);
		await expect(page.getByTestId('admin-queue-row')).toHaveCount(0);
		await expect(page.getByText(TARGET_ID.slice(0, 8))).toHaveCount(0);
	});
});
