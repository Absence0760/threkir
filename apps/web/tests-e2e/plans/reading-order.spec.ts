import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * /plans/[id] — the page leads with today's session and this week, and
 * everything else sits behind a named expander that remembers its state
 * (#905 workstream 3, decisions § 1658).
 *
 * Before this, a runner opening their plan read the phase pills, the plan
 * progress bar, the adherence banners, the rules card and the race-day panel
 * before reaching the one thing they came for — today's card was the eighth
 * block on the page.
 *
 * Pinned on DOM order rather than pixels — the same shape `publish-placement`
 * uses — so re-hoisting a secondary block above today fails here at any
 * viewport. The second test pins the persistence: an expander a runner shuts
 * stays shut on the next visit, which is what makes naming them worth it.
 */

const RICHMOND_HALF_PLAN_ID = 'a1a1eada-aaaa-0000-0000-000000000001';

/**
 * The blob `util/disclosure_state.ts` writes. Named here because the toggle is
 * persisted from the `toggle` event, which lands a task after the click flips
 * the element — so a reload fired on the DOM state alone races the write, and
 * the spec would pass or fail on scheduling. Waiting on the blob also pins the
 * per-account key scoping, which is what keeps a shared browser from handing
 * the next account this one's layout.
 */
const DISCLOSURE_KEY = `run_app.disclosure_v1:plan_detail:${USER_A.id}`;

/** True when `first` precedes `second` in document order; null if either is absent. */
function precedes(page: Page, first: string, second: string): Promise<boolean | null> {
	return page.evaluate(
		({ a, b }: { a: string; b: string }) => {
			const x = document.querySelector(a);
			const y = document.querySelector(b);
			if (!x || !y) return null;
			return (x.compareDocumentPosition(y) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
		},
		{ a: first, b: second }
	);
}

test.describe('/plans/[id] reading order', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeEach(async ({ context }) => {
		await context.addInitScript(() => {
			localStorage.setItem(
				'cookie_consent',
				JSON.stringify({ choice: 'accepted', timestamp: Date.now() })
			);
		});
	});

	test("today's session and this week come before every named expander", async ({ page }) => {
		await page.goto(`/plans/${RICHMOND_HALF_PLAN_ID}`);
		await expect(page.locator('section.today')).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('section.strip')).toBeVisible();

		// The lead, in order: today's session, then this week.
		expect(await precedes(page, 'section.today', 'section.strip')).toBe(true);

		// Every secondary block follows the lead.
		for (const secondary of [
			'section.progress-section',
			'section.calendar-section',
			'section.weeks',
			'section.publish-section'
		]) {
			expect(await precedes(page, 'section.strip', secondary), secondary).toBe(true);
		}

		// Each one is a real disclosure carrying a name, not a bare chevron.
		for (const name of ['Plan progress', 'Calendar', 'Week by week', 'Share & publish']) {
			const region = page.getByRole('region', { name });
			await expect(region).toBeVisible();
			await expect(region.locator('> details > summary')).toHaveCount(1);
		}
	});

	test('an expander a runner shuts stays shut across a reload', async ({ page }) => {
		// Asserted on the `<details>` element's own `open`, not on whether the
		// body is visible: Chromium hides a closed details through
		// `::details-content`, which Playwright still reports as visible.
		const isOpen = (name: string) =>
			page
				.getByRole('region', { name })
				.locator('details')
				.evaluate((el) => (el as HTMLDetailsElement).open);

		await page.goto(`/plans/${RICHMOND_HALF_PLAN_ID}`);
		const calendar = page.getByRole('region', { name: 'Calendar' });
		await expect(calendar.locator('.cal')).toBeAttached({ timeout: 10_000 });
		expect(await isOpen('Calendar')).toBe(true);

		const stored = () => page.evaluate((k) => localStorage.getItem(k), DISCLOSURE_KEY);

		try {
			await calendar.locator('summary').click();
			await expect.poll(() => isOpen('Calendar')).toBe(false);
			await expect.poll(stored).toContain('"calendar":false');

			await page.reload();
			await expect(page.locator('section.today')).toBeVisible({ timeout: 10_000 });
			expect(await isOpen('Calendar')).toBe(false);

			// One collapse is not a page-wide one — the siblings are untouched.
			expect(await isOpen('Week by week')).toBe(true);
			expect(await isOpen('Plan progress')).toBe(true);
		} finally {
			// Restore, and prove re-opening persists the same way.
			await page.getByRole('region', { name: 'Calendar' }).locator('summary').click();
			await expect.poll(stored).toContain('"calendar":true');
			await page.reload();
			await expect(page.locator('section.today')).toBeVisible({ timeout: 10_000 });
			expect(await isOpen('Calendar')).toBe(true);
		}
	});
});
