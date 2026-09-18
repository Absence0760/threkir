import { expect, test, type Locator } from '@playwright/test';

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
