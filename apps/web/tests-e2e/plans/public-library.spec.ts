import type { Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A, USER_B } from '../fixtures/users';
import { readMaybeRow, readRows } from '../fixtures/db-read';
import { acceptCookieConsent, planSectionsOpen } from '../fixtures/helpers';
import { createThrowawayPlan, deleteThrowawayPlan, type ThrowawayPlan } from '../fixtures/throwaway-plan';

/**
 * Public plan library — publish → browse → clone round-trip.
 *
 * USER_A publishes a copy of their seeded Richmond Half plan to the
 * public library from /plans/[id]. USER_B (a different account, no club
 * tie) then browses /plans/library, opens the preview, and clones it
 * into their own account — landing on the new plan's detail page. Pins:
 *   1. Publish creates exactly one public-library copy and leaves the
 *      source plan untouched.
 *   2. A stranger can see + preview the public template (RLS).
 *   3. The copy carries the plan's design and none of the publisher's
 *      data: no goal time, no absolute pace, no notes, and dates moved onto
 *      the reference week of 2001-01-01 (decisions § 2340).
 *   4. The clone is owned by the stranger, active, parent-linked to the
 *      template, and carries no publisher fitness data.
 */

const SOURCE_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';
const PLAN_NAME = 'Richmond Half 2026';

async function sweepLibrary(): Promise<void> {
	const admin = getAdminClient();
	// Public-library copies of the source plan (by name) + any clones
	// USER_B made off them (parent_template_id points back). Delete the
	// templates first so child clones lose their parent link cleanly;
	// plan_weeks/plan_workouts cascade on the training_plans delete.
	const { data: templates } = await admin
		.from('training_plans')
		.select('id')
		.eq('is_public_template', true)
		.eq('name', PLAN_NAME);
	const tmplIds = (templates ?? []).map((t) => (t as { id: string }).id);
	const { data: clones } = await admin
		.from('training_plans')
		.select('id')
		.eq('user_id', USER_B.id)
		.in('parent_template_id', tmplIds.length > 0 ? tmplIds : ['00000000-0000-0000-0000-000000000000']);
	for (const r of clones ?? []) {
		await admin.from('training_plans').delete().eq('id', (r as { id: string }).id);
	}
	for (const id of tmplIds) {
		await admin.from('training_plans').delete().eq('id', id);
	}
}

test.describe('Public plan library — publish → browse → clone', () => {
	test.beforeEach(async ({ context }) => {
		await acceptCookieConsent(context);
		await sweepLibrary();
	});

	test.afterEach(async () => {
		await sweepLibrary();
	});

	test('USER_A publishes; USER_B browses, previews, and clones', async ({ browser }) => {
		const admin = getAdminClient();

		// ── USER_A publishes ──
		const ctxA = await browser.newContext({ storageState: USER_A.storageStatePath });
		await acceptCookieConsent(ctxA, planSectionsOpen(USER_A.id));
		const pageA = await ctxA.newPage();
		await pageA.goto(`/plans/${SOURCE_PLAN_ID}`);
		const libraryRow = pageA
			.locator('.publish-row')
			.filter({ hasText: 'Public plan library' });
		await expect(libraryRow).toBeVisible({ timeout: 10_000 });
		await libraryRow.getByRole('button', { name: 'Publish to library' }).click();
		await expect(libraryRow.getByText('This plan is in the public library.')).toBeVisible({
			timeout: 10_000
		});

		// Exactly one public copy exists; source untouched.
		const templates = await readRows(
			'training_plans by is_public_template+name',
			admin
				.from('training_plans')
				.select('id, is_public_template, is_template, user_id, vdot, current_5k_seconds, goal_time_seconds, start_date')
				.eq('is_public_template', true)
				.eq('name', PLAN_NAME)
		);
		expect(templates.length).toBe(1);
		const tmpl = templates![0] as {
			id: string;
			is_public_template: boolean;
			is_template: boolean;
			user_id: string;
			vdot: number | null;
			current_5k_seconds: number | null;
			goal_time_seconds: number | null;
			start_date: string;
		};
		expect(tmpl.is_template).toBe(true);
		expect(tmpl.user_id).toBe(USER_A.id);
		expect(tmpl.vdot).toBeNull();
		expect(tmpl.current_5k_seconds).toBeNull();
		expect(tmpl.goal_time_seconds).toBeNull();
		expect(tmpl.start_date).toMatch(/^2001-01-0[1-7]$/);

		const copyWorkouts = (await readRows(
			'plan_workouts of the library copy',
			admin
				.from('plan_workouts')
				.select('target_pace_sec_per_km, target_pace_end_sec_per_km, notes, structure, plan_weeks!inner(plan_id)')
				.eq('plan_weeks.plan_id', tmpl.id)
		)) as { target_pace_sec_per_km: number | null; target_pace_end_sec_per_km: number | null; notes: string | null; structure: unknown }[];
		expect(copyWorkouts.length).toBeGreaterThan(0);
		for (const w of copyWorkouts) {
			expect(w.target_pace_sec_per_km).toBeNull();
			expect(w.target_pace_end_sec_per_km).toBeNull();
			expect(w.notes).toBeNull();
			expect(JSON.stringify(w.structure ?? null)).not.toContain('pace_sec_per_km');
		}

		const source = await readMaybeRow(
			'training_plans by id',
			admin
				.from('training_plans')
				.select('is_template, is_public_template, library_copy_id')
				.eq('id', SOURCE_PLAN_ID)
				.maybeSingle()
		);
		expect((source as { is_template: boolean }).is_template).toBe(false);
		expect((source as { is_public_template: boolean }).is_public_template).toBe(false);
		expect((source as { library_copy_id: string | null }).library_copy_id).toBe(tmpl.id);

		await ctxA.close();

		// ── USER_B browses + clones ──
		const ctxB = await browser.newContext({ storageState: USER_B.storageStatePath });
		await acceptCookieConsent(ctxB);
		const pageB = await ctxB.newPage();
		await pageB.goto('/plans/library');
		const card = pageB.locator('.plan-card', { hasText: PLAN_NAME });
		await expect(card).toBeVisible({ timeout: 10_000 });
		await card.click();

		// Preview opened.
		await pageB.waitForURL(/\/plans\/library\/[0-9a-f-]+$/, { timeout: 10_000 });
		await expect(pageB.getByRole('heading', { name: PLAN_NAME })).toBeVisible({
			timeout: 10_000
		});

		// Each week reads as what it asks of the runner, rest days skipped —
		// not a raw row count that says 7 for every week.
		await expect(pageB.locator('.week-count').first()).toHaveText(/^\d+ runs?( · .+)?$/);

		// Clone → lands on the new plan's detail page.
		await pageB.getByRole('button', { name: 'Clone into my plans' }).click();
		await pageB.waitForURL(/\/plans\/[0-9a-f-]+$/, { timeout: 15_000 });
		// The copy says whose plan it started from, and links back to it.
		const startedFrom = pageB.getByTestId('plan-started-from');
		await expect(startedFrom).toContainText('Started from', { timeout: 10_000 });
		await expect(startedFrom).toHaveAttribute('href', `/plans/library/${tmpl.id}`);

		const clones = await readRows(
			'training_plans by user_id+parent_template_id',
			admin
				.from('training_plans')
				.select('user_id, status, is_template, is_public_template, parent_template_id, source_author_id, vdot, current_5k_seconds')
				.eq('user_id', USER_B.id)
				.eq('parent_template_id', tmpl.id)
		);
		expect(clones.length).toBe(1);
		const clone = clones![0] as {
			user_id: string;
			status: string;
			is_template: boolean;
			is_public_template: boolean;
			parent_template_id: string;
			source_author_id: string | null;
			vdot: number | null;
			current_5k_seconds: number | null;
		};
		expect(clone.user_id).toBe(USER_B.id);
		expect(clone.source_author_id).toBe(USER_A.id);
		expect(clone.status).toBe('active');
		expect(clone.is_template).toBe(false);
		expect(clone.is_public_template).toBe(false);
		expect(clone.parent_template_id).toBe(tmpl.id);
		expect(clone.vdot).toBeNull();
		expect(clone.current_5k_seconds).toBeNull();

		await ctxB.close();
	});

	// Unpublishing deletes the library row, so every shared link to it stops
	// resolving and a republish mints a new id: it confirms before deleting.
	test('Unpublish asks first; Cancel keeps the library copy', async ({ browser }) => {
		const admin = getAdminClient();
		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		await acceptCookieConsent(ctx, planSectionsOpen(USER_A.id));
		const page = await ctx.newPage();
		await page.goto(`/plans/${SOURCE_PLAN_ID}`);
		const libraryRow = page.locator('.publish-row').filter({ hasText: 'Public plan library' });
		await expect(libraryRow).toBeVisible({ timeout: 10_000 });
		await libraryRow.getByRole('button', { name: 'Publish to library' }).click();
		await expect(libraryRow.getByText('This plan is in the public library.')).toBeVisible({
			timeout: 10_000
		});

		const published = () =>
			readRows(
				'training_plans by is_public_template+name',
				admin
					.from('training_plans')
					.select('id')
					.eq('is_public_template', true)
					.eq('name', PLAN_NAME)
			);

		await page.getByTestId('plan-unpublish-library').click();
		const confirm = page.getByTestId('unpublish-confirm-dialog');
		await expect(confirm).toBeVisible();
		await expect(confirm).toContainText('Unpublish this plan?');
		await confirm.getByRole('button', { name: 'Cancel' }).click();
		await expect(confirm).toBeHidden();
		expect((await published()).length).toBe(1);

		await page.getByTestId('plan-unpublish-library').click();
		await confirm.getByRole('button', { name: 'Unpublish' }).click();
		await expect(libraryRow.getByRole('button', { name: 'Publish to library' })).toBeVisible({
			timeout: 10_000
		});
		expect((await published()).length).toBe(0);

		await ctx.close();
	});

	// The page's mount reads the viewer's clubs after the plan has drawn; it
	// used to set the library state from the plan row it loaded once that read
	// came back, so a publish clicked in between was put back to "Publish".
	test('a publish made while the page is still loading stays published', async ({ browser, mockRoute }) => {
		const ctx = await browser.newContext({ storageState: USER_A.storageStatePath });
		await acceptCookieConsent(ctx, planSectionsOpen(USER_A.id));
		const page = await ctx.newPage();
		let release!: () => void;
		const released = new Promise<void>((r) => (release = r));
		let held = false;
		await mockRoute(page, '**/rest/v1/club_members*', async (route) => {
			if (held) return route.fallback();
			held = true;
			await released;
			await route.fallback();
		});
		await page.goto(`/plans/${SOURCE_PLAN_ID}`);
		const libraryRow = page.locator('.publish-row').filter({ hasText: 'Public plan library' });
		await libraryRow.getByRole('button', { name: 'Publish to library' }).click({ timeout: 10_000 });
		await expect(libraryRow.getByText('This plan is in the public library.')).toBeVisible({
			timeout: 10_000
		});
		expect(held).toBe(true);

		// USER_A owns clubs, so the club picker drawing is the mount finishing.
		release();
		await expect(page.getByRole('combobox', { name: 'Club to publish to' })).toBeVisible({
			timeout: 10_000
		});
		await expect(libraryRow.getByText('This plan is in the public library.')).toBeVisible();
		await expect(page.getByTestId('plan-unpublish-library')).toBeVisible();

		await ctx.close();
	});
});

// The plan page finds its library copy by its own `library_copy_id`, the link
// publish_plan_to_library writes on the source (decisions § 2340), never by name: by name, a rename lost the copy (no
// Unpublish, and a republish minted a duplicate) and two plans sharing a name
// both claimed the first copy. Each test runs on an account of its own, so a
// rename or a second same-named plan never touches the seeded plan.
test.describe('Public plan library — the copy follows its plan, not its name', () => {
	test.describe.configure({ timeout: 60_000 });

	let plan: ThrowawayPlan | undefined;

	test.afterEach(async () => {
		await deleteThrowawayPlan(plan);
		plan = undefined;
	});

	/// Each plan's library copy, as { source, id }, for the plans that have one.
	async function copiesOf(planIds: string[]) {
		const rows = (await readRows(
			'library_copy_id of the source plans',
			getAdminClient()
				.from('training_plans')
				.select('id, library_copy_id')
				.in('id', planIds)
				.not('library_copy_id', 'is', null)
		)) as { id: string; library_copy_id: string }[];
		return rows.map((r) => ({ source: r.id, id: r.library_copy_id }));
	}

	async function publish(page: Page, planId: string) {
		await page.goto(`/plans/${planId}`);
		const row = page.locator('.publish-row').filter({ hasText: 'Public plan library' });
		await expect(row).toBeVisible({ timeout: 10_000 });
		await row.getByRole('button', { name: 'Publish to library' }).click();
		await expect(row.getByText('This plan is in the public library.')).toBeVisible({ timeout: 10_000 });
		return row;
	}

	async function unpublish(page: Page) {
		await page.getByTestId('plan-unpublish-library').click();
		await page.getByTestId('unpublish-confirm-dialog').getByRole('button', { name: 'Unpublish' }).click();
	}

	test('a renamed plan still offers Unpublish, and it removes that copy', async ({ browser }) => {
		plan = await createThrowawayPlan(`Rename ${Date.now().toString(36)}`);
		const ctx = await browser.newContext({ storageState: plan.user.storageStatePath });
		await acceptCookieConsent(ctx, planSectionsOpen(plan.user.id));
		const page = await ctx.newPage();
		try {
			await publish(page, plan.planId);
			expect(await copiesOf([plan.planId])).toHaveLength(1);

			const { error } = await getAdminClient()
				.from('training_plans')
				.update({ name: `${plan.name} renamed` })
				.eq('id', plan.planId);
			if (error) throw new Error(`rename failed: ${error.message}`);

			await page.reload();
			const row = page.locator('.publish-row').filter({ hasText: 'Public plan library' });
			await expect(row.getByText('This plan is in the public library.')).toBeVisible({ timeout: 10_000 });
			await unpublish(page);
			await expect(row.getByRole('button', { name: 'Publish to library' })).toBeVisible({ timeout: 10_000 });
			expect(await copiesOf([plan.planId])).toHaveLength(0);
		} finally {
			await ctx.close();
		}
	});

	test('two plans with one name each keep their own copy', async ({ browser }) => {
		plan = await createThrowawayPlan(`Twin ${Date.now().toString(36)}`);
		const admin = getAdminClient();
		const { data: first, error: readError } = await admin
			.from('training_plans')
			.select('goal_event, goal_distance_m, start_date, end_date, days_per_week')
			.eq('id', plan.planId)
			.single();
		if (readError || !first) throw new Error(`plan read failed: ${readError?.message}`);
		const secondId = crypto.randomUUID();
		const { error: insertError } = await admin
			.from('training_plans')
			.insert({ ...first, id: secondId, user_id: plan.user.id, name: plan.name, status: 'paused' });
		if (insertError) throw new Error(`second plan seed failed: ${insertError.message}`);
		const { error: weekError } = await admin
			.from('plan_weeks')
			.insert({ plan_id: secondId, week_index: 0, phase: 'build', target_volume_m: 10_000 });
		if (weekError) throw new Error(`second plan week seed failed: ${weekError.message}`);

		const ctx = await browser.newContext({ storageState: plan.user.storageStatePath });
		await acceptCookieConsent(ctx, planSectionsOpen(plan.user.id));
		const page = await ctx.newPage();
		try {
			await publish(page, plan.planId);
			// The second plan has its own copy to make: the first one's copy is
			// not it, however alike their names.
			await publish(page, secondId);

			const copies = await copiesOf([plan.planId, secondId]);
			expect(copies).toHaveLength(2);
			const firstCopy = copies.find((c) => c.source === plan!.planId);
			const secondCopy = copies.find((c) => c.source === secondId);
			expect(firstCopy).toBeDefined();
			expect(secondCopy).toBeDefined();
			expect(firstCopy!.id).not.toBe(secondCopy!.id);

			await page.goto(`/plans/${plan.planId}`);
			await expect(page.getByTestId('plan-unpublish-library')).toBeVisible({ timeout: 10_000 });
			await unpublish(page);
			const row = page.locator('.publish-row').filter({ hasText: 'Public plan library' });
			await expect(row.getByRole('button', { name: 'Publish to library' })).toBeVisible({ timeout: 10_000 });
			expect((await copiesOf([plan.planId, secondId])).map((c) => c.id)).toEqual([secondCopy!.id]);

			await page.goto(`/plans/${secondId}`);
			await expect(page.getByTestId('plan-unpublish-library')).toBeVisible({ timeout: 10_000 });
		} finally {
			await ctx.close();
		}
	});
});
