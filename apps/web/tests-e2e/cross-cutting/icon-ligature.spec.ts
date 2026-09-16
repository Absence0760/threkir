import { expect, test } from '@playwright/test';

import { RUNNER_PUBLIC_ROUTE_ID } from '../fixtures/seeded-data';
import { USER_A } from '../fixtures/users';

/**
 * Resolved-cascade half of the icon-ligature guard.
 *
 * `src/lib/icon_ligature_guard.test.ts` proves `app.css` declares the reset.
 * It cannot prove the reset WINS: a descendant rule setting `letter-spacing`
 * on a `.material-symbols` selector, or a component scoping one at higher
 * specificity, would pass the source scan and still ship `TE MAX` where the
 * terrain icon goes.
 *
 * The measurement is the same one that found the defect. A shaped ligature is
 * one glyph, so the span's `scrollWidth` sits inside its `clientWidth`. An
 * unshaped one lays out every letter of `vertical_align_bottom` and overflows
 * a box that is `1.25em` wide and `overflow: hidden` — visible to
 * `scrollWidth`, invisible to a screenshot diff and to the page height.
 *
 * The four pages below are the ones that carried the ten broken icons; the
 * assertion is written against every icon each page renders, so it also covers
 * icons those pages grow later.
 */

const PAGES_THAT_CARRIED_THE_DEFECT = [
	{ name: 'route detail (surface + elevation tiles)', path: `/routes/${RUNNER_PUBLIC_ROUTE_ID}` },
	{ name: 'plans list (status pill)', path: '/plans' },
	{ name: 'gym list', path: '/gym' },
	{ name: 'segments list', path: '/segments' },
];

test.describe('icon ligatures shape into glyphs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	for (const { name, path } of PAGES_THAT_CARRIED_THE_DEFECT) {
		test(`no icon renders as its own name on ${name}`, async ({ page }) => {
			await page.goto(path);
			// The font must have arrived, or every icon is legitimately
			// unshaped and the assertion would be measuring `font-display`.
			await page.evaluate(() => document.fonts.ready);
			await expect(page.locator('.material-symbols').first()).toBeAttached({ timeout: 10_000 });

			const unshaped = await page.evaluate(() => {
				const bad: string[] = [];
				for (const el of document.querySelectorAll('.material-symbols')) {
					const name = el.textContent?.trim() ?? '';
					// Single-glyph content (an emoji, a bare arrow) is not a
					// ligature and has nothing to shape.
					if (name.length < 3) continue;
					// 3px of slack absorbs sub-pixel rounding on the 1.25em box.
					if (el.scrollWidth > el.clientWidth + 3) {
						const cs = getComputedStyle(el);
						bad.push(`${name} (letter-spacing: ${cs.letterSpacing}, text-transform: ${cs.textTransform})`);
					}
				}
				return [...new Set(bad)];
			});

			expect(
				unshaped,
				`These icons rendered their ligature name instead of a glyph. Something is setting letter-spacing or text-transform on a .material-symbols span — the reset in app.css is being overridden, not missing.`,
			).toEqual([]);
		});
	}
});
