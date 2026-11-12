import { expect, test } from '../fixtures/test';
import type { Browser, BrowserContext } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { readRows } from '../fixtures/db-read';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * Organiser name disputes (issue #1363, migrations 20271202000001..4,
 * decisions § 2441).
 *
 * The gate, the no-auto-hide rule and every action's writes are pinned by
 * organiser_disputes_test.sql. This spec walks the pages on top, with three
 * ephemeral saga users so the create_report bucket it spends is its own:
 *
 *   an organiser (owner of a verified club) reports a fan club from the club
 *   page; a moderator sees the dispute first in /admin/reports with the
 *   organiser's verified club named, sends a rename notice with a deadline,
 *   then hides the club; the fan club's owner reads the outcome on
 *   /disputes, and has no "Report as your organisation" action of their own,
 *   because their club is not verified.
 */

async function consentingContext(browser: Browser, storageStatePath: string): Promise<BrowserContext> {
	const ctx = await browser.newContext({ storageState: storageStatePath });
	await acceptCookieConsent(ctx);
	return ctx;
}

async function insertClub(ownerId: string, label: string, verified: boolean) {
	const id = crypto.randomUUID();
	const slug = `e2e-dispute-${label}-${id.slice(0, 8)}`;
	const name = `E2E Dispute ${label} ${id.slice(0, 8)}`;
	const admin = getAdminClient();
	const { error } = await admin
		.from('clubs')
		.insert({ id, owner_id: ownerId, name, slug, is_public: true, is_verified: verified });
	if (error) throw new Error(`insertClub failed: ${error.message}`);
	const { error: memberError } = await admin
		.from('club_members')
		.upsert({ club_id: id, user_id: ownerId, role: 'owner', status: 'active' }, { onConflict: 'club_id,user_id' });
	if (memberError) throw new Error(`insertClub member failed: ${memberError.message}`);
	return { id, slug, name };
}

test.describe('organiser name dispute — report, review, both sides told', () => {
	test('a verified organiser reports a fan club; the moderator notices, then hides it', async ({ browser }) => {
		const users = await createSagaUsers(3, {
			displayNames: ['Saga Organiser', 'Saga Fan', 'Saga Moderator'],
		});
		const [organiser, fan, moderator] = users as [SagaUser, SagaUser, SagaUser];
		const admin = getAdminClient();
		const contexts: BrowserContext[] = [];
		let official: { id: string; slug: string; name: string } | null = null;
		let fanClub: { id: string; slug: string; name: string } | null = null;

		try {
			await admin.from('app_admins').upsert({ user_id: moderator.id }, { onConflict: 'user_id' });
			official = await insertClub(organiser.id, 'official', true);
			fanClub = await insertClub(fan.id, 'fans', false);

			const organiserCtx = await consentingContext(browser, organiser.storageStatePath);
			contexts.push(organiserCtx);
			const organiserPage = await organiserCtx.newPage();

			await test.step('the organiser reports the fan club as their organisation', async () => {
				await organiserPage.goto(`/clubs/${fanClub!.slug}`);
				const open = organiserPage.getByTestId('organiser-dispute-open');
				await expect(open).toBeVisible({ timeout: 15_000 });
				await open.click();
				await expect(organiserPage.getByTestId('organiser-dispute-as')).toContainText(official!.name);
				await organiserPage.getByTestId('organiser-dispute-notes').fill('Uses our race name and logo.');
				await organiserPage.getByTestId('organiser-dispute-submit').click();
				await expect(organiserPage.getByText('Report sent. A reviewer will look at it.')).toBeVisible({
					timeout: 10_000,
				});
			});

			await test.step('the organiser is not offered a dispute against their own club', async () => {
				await organiserPage.goto(`/clubs/${official!.slug}`);
				await expect(organiserPage.getByTestId('club-verification-card')).toBeVisible({ timeout: 15_000 });
				await expect(organiserPage.getByTestId('organiser-dispute-open')).toHaveCount(0);
			});

			const rows = await readRows(
				'dispute report on the fan club',
				admin
					.from('reports')
					.select('reason, organiser_club_id, status')
					.eq('target_kind', 'club')
					.eq('target_id', fanClub.id),
			);
			expect(rows).toEqual([{ reason: 'organiser_dispute', organiser_club_id: official.id, status: 'pending' }]);

			const moderatorCtx = await consentingContext(browser, moderator.storageStatePath);
			contexts.push(moderatorCtx);
			const moderatorPage = await moderatorCtx.newPage();
			const queueRow = moderatorPage.getByTestId('admin-queue-row').filter({ hasText: fanClub.id.slice(0, 8) });

			await test.step('the moderator sees the dispute first, naming the verified club', async () => {
				await moderatorPage.goto('/admin/reports');
				await expect(queueRow).toBeVisible({ timeout: 15_000 });
				await expect(moderatorPage.getByTestId('admin-queue-row').first()).toHaveText(
					new RegExp(fanClub!.id.slice(0, 8)),
				);
				await expect(queueRow.getByTestId('admin-dispute-row')).toContainText(official!.name);
			});

			await test.step('the moderator sends a rename notice with a deadline', async () => {
				await queueRow.getByTestId('admin-queue-review').click();
				const modal = moderatorPage.getByTestId('admin-detail-modal');
				await expect(modal.getByTestId('admin-report-organiser')).toContainText(official!.name);
				const panel = modal.getByTestId('admin-dispute-panel');
				await expect(panel).toBeVisible();
				await panel.getByTestId('admin-dispute-note').fill('Please rename the club so runners are not misled.');
				await panel.getByTestId('admin-dispute-deadline').fill('10');
				await panel.getByTestId('admin-dispute-rename').click();
				await moderatorPage.getByTestId('admin-dispute-confirm').getByRole('button', { name: 'Send rename notice' }).click();
				await expect(moderatorPage.getByText('Rename notice sent. Both sides have been told.')).toBeVisible({
					timeout: 10_000,
				});
				await expect(queueRow).toContainText('Rename by');
			});

			const fanCtx = await consentingContext(browser, fan.storageStatePath);
			contexts.push(fanCtx);
			const fanPage = await fanCtx.newPage();

			await test.step('the fan club owner reads the notice and its deadline, without the reviewer', async () => {
				await fanPage.goto('/disputes');
				const mine = fanPage.getByTestId('disputes-mine');
				await expect(mine).toBeVisible({ timeout: 15_000 });
				await expect(mine.getByTestId('dispute-status')).toContainText(official!.name);
				await expect(mine.getByTestId('dispute-deadline')).toContainText('Rename by');
				await expect(mine).toContainText('Please rename the club so runners are not misled.');
				await expect(mine).not.toContainText('Saga Moderator');
			});

			await test.step('an unverified club owner has no organiser report of their own', async () => {
				await fanPage.goto(`/clubs/${official!.slug}`);
				await expect(fanPage.getByRole('button', { name: 'Report this club' })).toBeVisible({ timeout: 15_000 });
				await expect(fanPage.getByTestId('organiser-dispute-open')).toHaveCount(0);
			});

			await test.step('the moderator hides the club, and the dispute leaves the queue', async () => {
				await moderatorPage.reload();
				await expect(queueRow).toBeVisible({ timeout: 15_000 });
				await queueRow.getByTestId('admin-queue-review').click();
				const panel = moderatorPage.getByTestId('admin-dispute-panel');
				await expect(panel.getByTestId('admin-dispute-history')).toContainText('Rename notice sent');
				await panel.getByTestId('admin-dispute-hide').click();
				await moderatorPage.getByTestId('admin-dispute-confirm').getByRole('button', { name: 'Hide' }).click();
				await expect(moderatorPage.getByText('Hidden. Both sides have been told.')).toBeVisible({ timeout: 10_000 });
				await expect(queueRow).toHaveCount(0, { timeout: 10_000 });
			});

			const hidden = await readRows(
				'fan club after the hide',
				admin.from('clubs').select('shadow_hidden').eq('id', fanClub.id),
			);
			expect(hidden).toEqual([{ shadow_hidden: true }]);

			await test.step('the organiser reads the outcome on their side', async () => {
				await organiserPage.goto('/disputes');
				const filed = organiserPage.getByTestId('disputes-filed');
				await expect(filed).toBeVisible({ timeout: 15_000 });
				await expect(filed.getByTestId('dispute-status')).toContainText('Hidden after review.');
			});
		} finally {
			for (const ctx of contexts) await ctx.close().catch(() => {});
			const targets = [official?.id, fanClub?.id].filter((x): x is string => !!x);
			if (targets.length > 0) {
				await admin.from('reports').delete().in('target_id', targets);
				await admin.from('organiser_dispute_actions').delete().in('target_id', targets);
				await admin.from('clubs').delete().in('id', targets);
			}
			await admin.from('app_admins').delete().eq('user_id', moderator.id);
			await deleteSagaUsers(users);
		}
	});
});
