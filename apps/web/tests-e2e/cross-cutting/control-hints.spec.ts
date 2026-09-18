import { expect, test, type Locator } from '@playwright/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * Every control on a swept surface renders a one-line plain explanation
 * (issue #905 workstream 5 — the Spoken-cues pattern).
 *
 * `control_hints_guard.test.ts` pins the MARKUP: an `aria-describedby` whose
 * id exists, or a `.hint` inside a checkbox's label. It cannot see whether the
 * element that id points at actually renders text — a hint behind an `{#if}`
 * that never opens, or a catalogue key that resolves to empty, passes the
 * source scan and reaches the runner as a described-by pointing at nothing.
 * So this walks the rendered page instead and reads the description back.
 *
 * The control list is derived from the DOM, not enumerated here, so a control
 * added to one of these surfaces is covered the moment it ships.
 */

const SEED_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

interface Unexplained {
	control: string;
	why: string;
}

/** Controls on `root` whose explanation is missing or renders empty. */
async function unexplained(root: Locator): Promise<Unexplained[]> {
	return root.evaluate((el) => {
		const bad: Array<{ control: string; why: string }> = [];
		const describe = (c: Element) =>
			`${c.tagName.toLowerCase()}${c.getAttribute('type') ? `[type=${c.getAttribute('type')}]` : ''}` +
			`${c.getAttribute('name') ? `[name=${c.getAttribute('name')}]` : ''}` +
			` "${(c.closest('label')?.textContent ?? c.getAttribute('aria-label') ?? '').trim().slice(0, 40)}"`;

		const controls = el.querySelectorAll(
			'input, select, [role="group"], [role="radiogroup"]'
		);
		for (const c of controls) {
			if (c instanceof HTMLInputElement && c.type === 'hidden') continue;
			const ids = (c.getAttribute('aria-describedby') ?? '').split(/\s+/).filter(Boolean);
			if (ids.length > 0) {
				const text = ids
					.map((id) => el.ownerDocument.getElementById(id)?.textContent ?? '')
					.join(' ')
					.trim();
				if (text.length < 10) {
					bad.push({
						control: describe(c),
						why: `aria-describedby resolves to ${JSON.stringify(text)}`,
					});
				}
				continue;
			}
			if (c instanceof HTMLInputElement && c.type === 'checkbox') {
				const hint = c.closest('label')?.querySelector('.hint, .field-hint');
				if ((hint?.textContent ?? '').trim().length >= 10) continue;
				bad.push({ control: describe(c), why: 'no .hint text inside its label' });
				continue;
			}
			bad.push({ control: describe(c), why: 'no aria-describedby' });
		}
		return bad;
	});
}

async function assertEveryControlExplained(root: Locator, surface: string): Promise<void> {
	const missing = await unexplained(root);
	expect(missing, `${surface} has controls with no rendered explanation`).toEqual([]);
}

test.describe('every swept control renders its explanation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/plans/new — the pickers and the training-plan wizard', async ({ page }) => {
		await page.goto('/plans/new');
		await expect(
			page.getByRole('heading', { level: 1, name: 'Build a training plan' })
		).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.plan-editor')).toBeVisible({ timeout: 5_000 });

		// The recent-5K confirm checkbox only mounts once a time is entered,
		// and the week grid only once a week is expanded — both are controls
		// the sweep covers, so open them before reading the page.
		const recent = page.locator('.plan-editor fieldset', { hasText: 'Recent 5K time' });
		await recent.locator('input[type="number"]').first().fill('25');
		await expect(recent.getByRole('checkbox')).toBeVisible({ timeout: 5_000 });

		const firstWeek = page.locator('.plan-editor .week-item').first();
		await expect(firstWeek).toBeVisible({ timeout: 10_000 });
		await firstWeek.locator('.week-row').click();
		await expect(firstWeek.locator('.week-editor')).toBeVisible({ timeout: 5_000 });

		await assertEveryControlExplained(page.locator('.page'), '/plans/new');
	});

	test('/runs/new — the manual-run editor', async ({ page }) => {
		await page.goto('/runs/new');
		await expect(page.getByRole('heading', { level: 1, name: 'Add a run' })).toBeVisible({
			timeout: 10_000,
		});
		await assertEveryControlExplained(page.locator('form.run-editor'), '/runs/new');
	});

	test('/plans/[id] — the Edit-plan dialog', async ({ page }) => {
		await page.goto(`/plans/${SEED_PLAN_ID}`);
		await page.getByRole('button', { name: 'Edit plan' }).first().click({ timeout: 15_000 });
		const dialog = page.locator('.modal', { hasText: 'Edit plan' });
		await expect(dialog).toBeVisible({ timeout: 5_000 });

		await assertEveryControlExplained(dialog.locator('form.editor-form'), 'PlanMetaEditor');
	});
});

test.describe('every swept creator control renders its explanation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/clubs/new — the club editor', async ({ page }) => {
		await page.goto('/clubs/new');
		const form = page.locator('form.editor-form');
		await expect(form).toBeVisible({ timeout: 10_000 });
		await assertEveryControlExplained(form, '/clubs/new');

		// Private hides the join-policy fieldset and is the only way to reach
		// the private radio's own description, so read the page in both states.
		await form.getByRole('radio', { name: 'Private' }).check();
		await assertEveryControlExplained(form, '/clubs/new (private)');
	});

	test('/clubs/[slug]/events/new — the event editor', async ({ page }) => {
		await page.goto('/clubs/richmond-run-club/events/new');
		const form = page.locator('form.event-editor');
		await expect(form).toBeVisible({ timeout: 15_000 });

		// Recurrence hides its end fields until a cadence is picked, so the
		// run-category pass opens them first.
		await form.getByRole('radio', { name: 'Weekly' }).check();
		await assertEveryControlExplained(form, 'EventEditor (group run)');

		// A class swaps the athletic fields for the discipline / gym-template /
		// session-plan trio, which no other state renders.
		await form.getByRole('radio', { name: 'Class' }).click();
		await expect(form.getByTestId('gym-template-duration')).toBeVisible({ timeout: 5_000 });
		await assertEveryControlExplained(form, 'EventEditor (class)');
	});

	test('/races — the add-a-race editor', async ({ page }) => {
		await page.goto('/races');
		await page.getByTestId('race-submit').click({ timeout: 15_000 });
		const form = page.locator('.modal form.editor-form');
		await expect(form).toBeVisible({ timeout: 5_000 });
		await assertEveryControlExplained(form, 'RaceListingEditor');
	});

	test('/challenges — the challenge editor', async ({ page }) => {
		await page.goto('/challenges');
		await page.getByRole('button', { name: /Create challenge/ }).first().click({ timeout: 15_000 });
		const form = page.locator('.modal form.editor-form');
		await expect(form).toBeVisible({ timeout: 5_000 });
		await assertEveryControlExplained(form, 'ChallengeEditor');
	});

	test('/runs/[id] — the fundraiser editor', async ({ page }) => {
		// The editor is reached from the owner's own run, and renders whether or
		// not payouts are set up — only Save is gated on that.
		await getAdminClient().from('instructor_payout_accounts').delete().eq('user_id', USER_A.id);
		const runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 5_000,
			duration_s: 1_500,
			is_public: true
		});
		try {
			await page.goto(`/runs/${runId}`);
			await page.getByTestId('fundraiser-create-cta').click({ timeout: 15_000 });
			const form = page.locator('.modal form.editor-form');
			await expect(form).toBeVisible({ timeout: 5_000 });
			await assertEveryControlExplained(form, 'FundraiserEditor');
		} finally {
			await getAdminClient().from('runs').delete().eq('id', runId);
		}
	});
});
