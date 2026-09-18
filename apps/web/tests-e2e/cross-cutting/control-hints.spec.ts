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

const SYDNEY_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/** Walk the plan calendar back to its first month, then forward to one holding a workout. */
async function walkToAWorkoutMonth(page: import('@playwright/test').Page): Promise<void> {
	const prev = page.locator('.cal .nav[aria-label="Previous month"]');
	const next = page.locator('.cal .nav[aria-label="Next month"]');
	const cells = page.locator('.cal .cell.has-workout');
	for (let i = 0; i < 24; i++) {
		if ((await prev.getAttribute('disabled')) !== null) break;
		await prev.click();
	}
	for (let i = 0; i < 24; i++) {
		if ((await cells.count()) > 0) return;
		if ((await next.getAttribute('disabled')) !== null) break;
		await next.click();
	}
	await expect(cells.first()).toBeVisible();
}

test.describe('every swept gym and session control renders its explanation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/gym/routines/new — the routine editor', async ({ page }) => {
		await page.goto('/gym/routines/new');
		const form = page.locator('.routine-editor');
		await expect(form).toBeVisible({ timeout: 15_000 });

		// The advanced block is a <details>, and the three progression fields
		// only mount under the scheme that uses them. Open it and pick the two
		// schemes that carry their own fields.
		await form.locator('details.advanced summary').first().click();
		const scheme = form.getByTestId('routine-progression').first();
		await scheme.selectOption('percent_cycle');
		await expect(form.getByTestId('routine-progression-percent').first()).toBeVisible();
		await assertEveryControlExplained(form, 'RoutineEditor (percent cycle)');

		await scheme.selectOption('rpe_autoreg');
		await expect(form.getByTestId('routine-progression-rpe').first()).toBeVisible();
		await assertEveryControlExplained(form, 'RoutineEditor (auto-regulated)');
	});

	test('/gym — the log-a-workout editor', async ({ page }) => {
		await page.goto('/gym');
		await page.getByTestId('gym-log').click({ timeout: 15_000 });
		const form = page.locator('.gym-editor');
		await expect(form).toBeVisible({ timeout: 5_000 });
		await assertEveryControlExplained(form, 'GymEditor');
	});

	test('/sessions — the session-plan editor', async ({ page }) => {
		await page.goto('/sessions');
		await page.getByRole('button', { name: 'New session' }).click({ timeout: 15_000 });
		const form = page.locator('.session-editor');
		await expect(form).toBeVisible({ timeout: 5_000 });

		// A new plan starts with no blocks and one movement, so add a block to
		// bring the block-name field on screen, and switch the movement to reps
		// so the count field renders in place of the duration one.
		await form.getByRole('button', { name: 'Add block' }).click();
		await assertEveryControlExplained(form, 'SessionPlanEditor');
		await form.locator('.item-grid select').first().selectOption('reps');
		await assertEveryControlExplained(form, 'SessionPlanEditor (reps)');
	});

	test('/nutrition/log — the food-log editor', async ({ page }) => {
		// The portion dialog is behind a live food-database search, so this
		// covers the search card and the manual-entry panel; the portion field
		// is left to the source guard.
		await page.goto('/nutrition/log');
		const editor = page.locator('.food-log-editor');
		await expect(editor).toBeVisible({ timeout: 15_000 });
		await editor.getByRole('button', { name: /Enter manually|Manual/ }).click();
		await expect(editor.getByTestId('manual-entry')).toBeVisible({ timeout: 5_000 });
		await assertEveryControlExplained(editor, 'FoodLogEditor');
	});

	test('/plans/[id] — the workout editor', async ({ page }) => {
		await page.goto(`/plans/${SYDNEY_HALF_PLAN_ID}`);
		await expect(page.locator('.cal')).toBeVisible({ timeout: 15_000 });
		await walkToAWorkoutMonth(page);
		await page.locator('.cal .cell.has-workout').first().click();
		const form = page.locator('.modal .editor-form');
		await expect(form).toBeVisible({ timeout: 5_000 });

		// The structure block only mounts for a kind that has one, and its two
		// shapes render different fields, so walk an interval workout through
		// both rather than reading whichever kind the seed happened to put
		// under the cursor.
		await form.locator('select').first().selectOption('interval');
		await expect(form.locator('fieldset.structure')).toBeVisible({ timeout: 5_000 });
		await assertEveryControlExplained(form, 'WorkoutEditor (repeats)');

		await form.getByRole('radio', { name: 'Steady' }).check();
		await assertEveryControlExplained(form, 'WorkoutEditor (steady)');
	});
});

test.describe('every swept filter and preference control renders its explanation', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('/nutrition/targets — the two defaults', async ({ page }) => {
		await page.goto('/nutrition/targets');
		const card = page.locator('.defaults-card');
		await expect(card).toBeVisible({ timeout: 15_000 });
		await assertEveryControlExplained(card, '/nutrition/targets');
	});

	test('/segments — the catalogue filters', async ({ page }) => {
		await page.goto('/segments');
		const filters = page.locator('.filters');
		await expect(filters).toBeVisible({ timeout: 15_000 });
		await assertEveryControlExplained(filters, '/segments');
	});

	test('/races — the calendar filters and the paste-a-result form', async ({ page }) => {
		await page.goto('/races');
		const filters = page.locator('.filters');
		await expect(filters).toBeVisible({ timeout: 15_000 });
		await assertEveryControlExplained(filters, '/races (filters)');

		// The paste form lives in the per-race import modal, which only opens
		// from a listing, so the filter pass above cannot reach it.
		const importBtn = page.getByTestId('race-import').first();
		if ((await importBtn.count()) > 0) {
			await importBtn.click();
			const form = page.locator('.modal form.editor-form');
			await expect(form).toBeVisible({ timeout: 5_000 });
			await assertEveryControlExplained(form, '/races (paste a result)');
		}
	});
});
