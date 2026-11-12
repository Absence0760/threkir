import type { Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * /plans/[id] — the page leads with today's session and this week, and
 * everything else sits behind a named expander that starts shut and remembers
 * its state (#905 workstream 3, decisions § 1660; shut since #1186, § 2375).
 *
 * Before this, a runner opening their plan read the phase pills, the plan
 * progress bar, the adherence banners, the rules card and the race-day panel
 * before reaching the one thing they came for — today's card was the eighth
 * block on the page.
 *
 * Pinned on DOM order rather than pixels — the same shape `publish-placement`
 * uses — so re-hoisting a secondary block above today fails here at any
 * viewport. The second test pins the default and the persistence: every
 * expander starts shut, so the current week is drawn once (the strip), and one
 * a runner opens stays open on the next visit.
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
		await acceptCookieConsent(context);
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

	test('every expander starts shut, and one a runner opens stays open across a reload', async ({
		page
	}) => {
		// Asserted on the `<details>` element's own `open`, not on whether the
		// body is visible: Chromium hides a closed details through
		// `::details-content`, which Playwright still reports as visible.
		const isOpen = (name: string) =>
			page
				.getByRole('region', { name })
				.locator('details')
				.evaluate((el) => (el as HTMLDetailsElement).open);

		await page.goto(`/plans/${RICHMOND_HALF_PLAN_ID}`);
		await expect(page.locator('section.today')).toBeVisible({ timeout: 10_000 });
		for (const name of ['Plan progress', 'Calendar', 'Week by week', 'Share & publish']) {
			expect(await isOpen(name), name).toBe(false);
		}

		const stored = () => page.evaluate((k) => localStorage.getItem(k), DISCLOSURE_KEY);
		const calendar = page.getByRole('region', { name: 'Calendar' });

		await calendar.locator('summary').click();
		await expect.poll(() => isOpen('Calendar')).toBe(true);
		await expect(calendar.locator('.cal')).toBeVisible();
		await expect.poll(stored).toContain('"calendar":true');

		await page.reload();
		await expect(page.locator('section.today')).toBeVisible({ timeout: 10_000 });
		expect(await isOpen('Calendar')).toBe(true);

		// One opened section is not a page-wide one — the siblings stay shut.
		expect(await isOpen('Week by week')).toBe(false);
		expect(await isOpen('Plan progress')).toBe(false);

		// Shutting it again persists the same way.
		await page.getByRole('region', { name: 'Calendar' }).locator('summary').click();
		await expect.poll(stored).toContain('"calendar":false');
		await page.reload();
		await expect(page.locator('section.today')).toBeVisible({ timeout: 10_000 });
		expect(await isOpen('Calendar')).toBe(false);
	});
});
