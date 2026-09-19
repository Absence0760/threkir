import { expect, test } from '@playwright/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import {
	expectIconButtonsClearTheBar,
	INLINE_DISCLOSURE,
	MIN_TAP_TARGET_PX
} from '../fixtures/tap-targets';
import { USER_A } from '../fixtures/users';

/**
 * Every icon button on /dashboard clears the tap-target bar, with headroom.
 *
 * This replaces a single assertion on `.pr-hide`, which policed one control and
 * left the ones around it — the seven metric disclosures among them — unmeasured.
 * It is a sweep, so a new glyph-only control on the page is audited the day it
 * lands rather than the day someone remembers to write a case for it.
 *
 * The regression the headroom half exists for: `.pr-hide` carried
 * `min-width/min-height: 44px` and measured 44.0 x 44.0 on all 480 samples of a
 * 12-load run, so the assertion tested the exact value the CSS declared and any
 * sub-pixel effect could fail a correct control. Source sizing goes through
 * `--tap-target-min`, which sits above the bar.
 *
 * Both viewports: on a phone width the PR table scrolls horizontally and the
 * stat tiles reflow, and a control can clear the bar at one width and not the
 * other.
 */

const VIEWPORTS = [
	{ name: 'desktop', width: 1280, height: 720 },
	{ name: 'phone', width: 375, height: 667 }
] as const;

test.describe('/dashboard tap targets', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId = '';

	test.beforeAll(async () => {
		// Guarantee a visible PR row, so `.pr-hide` is in every sweep.
		runId = await insertRun({
			user_id: USER_A.id,
			duration_s: 1080,
			distance_m: 5000
		});
	});

	test.afterAll(async () => {
		if (runId) await deleteRun(runId);
	});

	for (const vp of VIEWPORTS) {
		test(`every icon button clears ${MIN_TAP_TARGET_PX}px at ${vp.name} width`, async ({
			page
		}) => {
			await page.setViewportSize({ width: vp.width, height: vp.height });
			await page.goto('/dashboard');
			const main = page.locator('#main-content');
			await expect(main.locator('.pr-hide').first()).toBeVisible({ timeout: 10_000 });

			const measured = await expectIconButtonsClearTheBar(main, { minCount: 6 });

			// The sweep is only as good as what it caught: the PR hide control
			// and the metric disclosures must both be in it, or the selector has
			// drifted off them and the spec is green on nothing.
			const classesOf = (c: string) =>
				measured.filter((t) => t.classes.split(/\s+/).includes(c));
			expect(classesOf('pr-hide').length).toBeGreaterThan(0);
			expect(classesOf('metric-info').length).toBeGreaterThan(0);

			// An exemption is a claim about one named control, not a hole:
			// anything under the product bar has to be on the registry in
			// fixtures/tap-targets.ts with its reason beside it.
			const subBar = measured
				.filter((t) => t.width < MIN_TAP_TARGET_PX || t.height < MIN_TAP_TARGET_PX)
				.filter((t) => !t.classes.split(/\s+/).some((c) => c in INLINE_DISCLOSURE))
				.map((t) => `${t.label} (${t.classes})`);
			expect(subBar).toEqual([]);
		});
	}
});
