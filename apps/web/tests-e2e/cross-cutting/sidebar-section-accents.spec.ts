import { expect, test, type Page } from '@playwright/test';

import { USER_A } from '../fixtures/users';

/**
 * The sidebar's seven per-section identity accents (decisions § 529).
 *
 * Each nav row names a `--section-<x>` / `--section-<x>-ink` pair in app.css
 * via an inline `style="--accent: var(...)"`, and the icon glyph paints the
 * INK while its disc tints with the FILL. Two things can only be checked in a
 * real browser: that the inline var() chain resolves at all (a typo'd token
 * name yields an unset custom property and the glyph silently falls back to
 * the inherited text colour — no build error, no unit-test failure), and that
 * the ink half actually flips when the theme does.
 *
 * The contrast arithmetic is NOT here: `color-mix(..., transparent)` over a
 * gradient has no single computed background to measure, so every composited
 * figure is pinned in src/lib/contrast_guard.test.ts against the tokens read
 * out of app.css. What this file pins is the cascade and the identity.
 */

const SECTIONS = [
	'dashboard',
	'history',
	'runs',
	'gym',
	'nutrition',
	'coach',
	'social',
] as const;

async function tokens(page: Page, names: string[]): Promise<string[]> {
	return page.evaluate((ns) => {
		const cs = getComputedStyle(document.documentElement);
		// Round-trip each declared value through a probe element so it comes
		// back in the same rgb() serialisation getComputedStyle().color uses.
		const probe = document.createElement('span');
		document.body.appendChild(probe);
		const out = ns.map((n) => {
			probe.style.color = cs.getPropertyValue(n).trim();
			return getComputedStyle(probe).color;
		});
		probe.remove();
		return out;
	}, names);
}

/**
 * Gym and Nutrition join the sidebar once the session's visibility read lands
 * (decisions § 1739 amendment). USER_A's seed logs both, so both resolve shown
 * and must be in the list before anything is measured; reading earlier would
 * check five or six sections and call it seven.
 */
async function navSettled(page: Page): Promise<void> {
	for (const href of ['/gym', '/nutrition']) {
		await expect(page.locator(`nav.sidebar .nav-link[href="${href}"]`)).toBeVisible({
			timeout: 15_000,
		});
	}
}

function glyphColours(page: Page): Promise<string[]> {
	return page
		.locator('nav.sidebar .nav-link .nav-icon')
		.evaluateAll((els) => els.map((el) => getComputedStyle(el).color));
}

test.describe('sidebar section accents', () => {
	test.use({ storageState: USER_A.storageStatePath });

	for (const theme of ['light', 'dark'] as const) {
		test(`each nav glyph resolves its own section ink — ${theme}`, async ({ page }) => {
			await page.addInitScript(
				(t) => window.localStorage.setItem('run_app.theme', t),
				theme,
			);
			await page.goto('/dashboard');
			await expect(page.locator('html')).toHaveAttribute('data-theme', theme);
			await navSettled(page);

			const links = page.locator('nav.sidebar .nav-link');
			// The AI Coach row hides when the Coach is off, so the set is the
			// sections present, not always all seven.
			const hrefs = await links.evaluateAll((els) =>
				els.map((el) => el.getAttribute('href') ?? ''),
			);
			const present = SECTIONS.filter((s) => hrefs.includes(`/${s}`));
			expect(present.length).toBeGreaterThanOrEqual(6);

			const glyphs = await glyphColours(page);
			expect(glyphs).toHaveLength(hrefs.length);

			// Identity: no two sections share a glyph colour. The ACTIVE row is
			// the exception by design — it paints --section-on-accent on the full
			// accent — so it is compared separately below.
			const activeIndex = hrefs.indexOf('/dashboard');
			const idle = glyphs.filter((_, i) => i !== activeIndex);
			expect(new Set(idle).size).toBe(idle.length);

			// Cascade: every idle glyph is exactly its own section's ink token.
			const expected = await tokens(
				page,
				present.map((s) => `--section-${s}-ink`),
			);
			for (const [i, section] of present.entries()) {
				const at = hrefs.indexOf(`/${section}`);
				if (at === activeIndex) continue;
				expect(glyphs[at], `--section-${section}-ink in ${theme}`).toBe(expected[i]);
			}

			// An unresolved var() would leave the glyph on the inherited sidebar
			// text colour, which is the one value it must never be.
			const [sidebarText] = await tokens(page, ['--sidebar-text-muted']);
			for (const g of idle) expect(g).not.toBe(sidebarText);

			// The active row takes the shared on-accent foreground.
			const [onAccent] = await tokens(page, ['--section-on-accent']);
			expect(glyphs[activeIndex]).toBe(onAccent);
		});
	}

	test('the ink half flips with the theme while the accents stay put', async ({ page }) => {
		await page.addInitScript(() => window.localStorage.setItem('run_app.theme', 'light'));
		await page.goto('/dashboard');
		await navSettled(page);
		const light = await glyphColours(page);

		// The glyph inherits its colour from .nav-icon-wrap, which transitions
		// `color`, so a read straight after the flip returns the light value
		// mid-transition. Wait for the sidebar's transitions to finish first.
		await page.evaluate(async () => {
			window.localStorage.setItem('run_app.theme', 'dark');
			document.documentElement.dataset.theme = 'dark';
			const nav = document.querySelector('nav.sidebar');
			if (!nav) return;
			for (const el of nav.querySelectorAll('.nav-icon')) void getComputedStyle(el).color;
			await Promise.all(nav.getAnimations({ subtree: true }).map((a) => a.finished));
		});
		const dark = await glyphColours(page);

		expect(dark).toHaveLength(light.length);
		// gym / nutrition / dashboard revert to their pastel accent in dark and
		// the other four lighten a step, so most rows must move — a token pair
		// wired to the light rung in both themes is the regression this catches.
		const moved = dark.filter((c, i) => c !== light[i]).length;
		expect(moved).toBeGreaterThanOrEqual(light.length - 1);
		expect(new Set(dark).size).toBeGreaterThanOrEqual(light.length - 1);
	});
});
