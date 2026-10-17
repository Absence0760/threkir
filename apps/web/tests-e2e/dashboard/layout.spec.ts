import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /dashboard — the shape of the page, and the honesty of the mileage axis.
 *
 * Every card used to be a full-width slab in one flex column, so a desktop
 * screen showed a single column of twenty of them. The cards of equal weight
 * now flow in auto-fit bands. What is worth pinning is not the pixel layout
 * but the two properties a later CSS edit could quietly undo: that a wide
 * viewport puts band-mates on ONE row, and that a phone puts them on
 * separate ones.
 */

const MOBILE = { width: 390, height: 844 };
const DESKTOP = { width: 1440, height: 900 };

test.describe('/dashboard layout', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('band-mates share a row on desktop and stack on a phone', async ({ page }) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		await expect(page.locator('.metric-band').first()).toBeVisible();

		// Two cards in the same band, both rendered: their top edges must
		// agree, which is the whole claim of the band. Each trend group is its
		// own band and most of their cards self-hide, so take the first band
		// this account fills with two.
		const bands = page.locator('.metric-band').filter({
			has: page.locator(':scope > section:nth-of-type(2)')
		});
		test.skip((await bands.count()) === 0, 'this account renders no band with two cards');
		const cards = bands.first().locator(':scope > section');

		const first = await cards.nth(0).boundingBox();
		const second = await cards.nth(1).boundingBox();
		expect(first).not.toBeNull();
		expect(second).not.toBeNull();
		expect(
			Math.abs(first!.y - second!.y),
			'band-mates must sit on one row at 1440px'
		).toBeLessThan(4);
		expect(second!.x, 'and side by side, not stacked').toBeGreaterThan(first!.x);

		// A phone has no room for two columns of cards; the band's minmax
		// floor has to give way rather than squeeze both into 190px.
		await page.setViewportSize(MOBILE);
		await page.waitForTimeout(300);
		const firstNarrow = await cards.nth(0).boundingBox();
		const secondNarrow = await cards.nth(1).boundingBox();
		expect(
			secondNarrow!.y,
			'on a phone the second card must drop below the first'
		).toBeGreaterThan(firstNarrow!.y);
	});

	test('the mileage window is all twelve weeks or none', async ({ page }) => {
		await page.setViewportSize(DESKTOP);
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const bars = page.locator('.bar-col');
		const drawn = await bars.count();

		// The property, stated as the code states it: a partial window is the
		// defect. Either nothing in the last twelve weeks — in which case the
		// card shows its own copy rather than twelve empty slots — or all
		// twelve buckets, including the weeks with no run in them. Which of
		// the two depends on how old the seeded runs are on the day the suite
		// runs, and that is exactly why this asserts the invariant instead of
		// a count.
		if (drawn === 0) {
			await expect(page.locator('.chart')).toHaveCount(0);
			return;
		}
		expect(drawn, 'a continuous window is twelve buckets, not just the busy ones').toBe(12);

		// At least one real bar, or the empty branch above should have run.
		const empties = await page.locator('.bar-col.empty').count();
		expect(empties).toBeLessThan(12);

		// The axis label is formatted in its own right, not cut out of the
		// full date: `split(' ')[0]` gave "Aug" for every week of August in
		// en-US, and the untranslated whole date in ja. In the suite's locale
		// a weekly label is a day of the month.
		for (const label of await page.locator('.bar-label').allInnerTexts()) {
			expect(label.trim(), 'a weekly axis label must be a day number').toMatch(/^\d{1,2}$/);
		}
	});

	test('the mileage chart stays inside its card at 300px, whichever bar is read', async ({
		page
	}) => {
		// Each bar used to carry its own tooltip centred on its column. Twelve
		// columns in a phone-width card are narrower than a "Sep 7 · 8.00 km"
		// label, so the outer bars' labels overhung the card, and the last
		// one ran past the viewport and scrolled the page sideways at rest —
		// an opacity-0 box still has layout. The reflow sweep caught it only
		// on a day whose latest week had a run (the label is shorter at zero),
		// which is why this asserts containment directly, for the two edge
		// bars, while one of them is being read.
		await page.setViewportSize({ width: 300, height: 720 });
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const bars = page.locator('.bar-col');
		const count = await bars.count();
		test.skip(count === 0, 'no run in the mileage window on the day the seed was reset');

		// Containment in the card alone only failed where the font's digits ran
		// wide enough to cross the card's padding, so it passed on one machine
		// and failed on CI. The cause is font-independent: a flex column that
		// floors at its label's min-content. Equal columns say the track is
		// sized by the chart, and the labels still shown must not touch, since
		// shrinking the columns is what lets them run together.
		const axis = await page.locator('.chart').evaluate((chart) => {
			const cols = [...chart.querySelectorAll('.bar-col')].map((c) => c.getBoundingClientRect().width);
			const labels = [...chart.querySelectorAll('.bar-label')];
			const shown = labels
				.filter((l) => getComputedStyle(l).visibility !== 'hidden')
				.map((l) => l.getBoundingClientRect());
			return {
				colSpread: Math.max(...cols) - Math.min(...cols),
				gaps: shown.slice(1).map((r, i) => r.left - shown[i].right),
				latestShown: getComputedStyle(labels[labels.length - 1]).visibility !== 'hidden'
			};
		});
		expect(axis.colSpread, 'every column takes an equal share, whatever its label').toBeLessThan(0.5);
		for (const gap of axis.gaps) {
			expect(gap, 'the axis labels still shown must not run together').toBeGreaterThanOrEqual(2);
		}
		expect(axis.latestShown, 'the current period keeps its label').toBe(true);

		const card = page.locator('section.card-elevated', { has: page.locator('.chart') });
		const readout = page.getByTestId('mileage-readout');

		for (const index of [0, count - 1]) {
			await bars.nth(index).hover();
			await expect(readout, `reading bar ${index} fills the readout`).toContainText('·');

			const overhang = await card.evaluate((el) => {
				const box = el.getBoundingClientRect();
				return [...el.querySelectorAll('*')]
					.map((child) => child.getBoundingClientRect())
					.filter((r) => r.width > 0 && (r.left < box.left - 0.5 || r.right > box.right + 0.5))
					.map((r) => `${Math.round(r.left)}..${Math.round(r.right)}`);
			});
			expect(overhang, `bar ${index}: nothing in the card may draw outside it`).toEqual([]);

			const { scrollWidth, clientWidth } = await page.evaluate(() => ({
				scrollWidth: document.documentElement.scrollWidth,
				clientWidth: document.documentElement.clientWidth
			}));
			expect(scrollWidth, `bar ${index}: the page must not scroll sideways`).toBeLessThanOrEqual(
				clientWidth
			);
		}
	});

	test('a Today | Trends divider separates today from the trend groups', async ({ page }) => {
		// multi_modal.md § Home: "Today" cards, then a thin divider, then
		// "Trends". The divider is only worth anything if it sits BETWEEN the
		// two — below the week lead that opens the page, above every group.
		await page.setViewportSize(MOBILE);
		await page.goto('/dashboard');

		const divider = page.getByTestId('dash-trends-divider');
		await expect(divider).toBeVisible({ timeout: 10_000 });
		await expect(divider).toHaveText('Trends');
		await expect(divider, 'the divider is a quiet label, not a shouting header').toHaveCSS(
			'text-transform',
			'none'
		);

		// Volume, Performance and Recent always mount for an account with runs.
		const groups = page.locator('section.trend-group');
		expect(await groups.count()).toBeGreaterThanOrEqual(3);

		const dividerBox = await divider.boundingBox();
		const lead = await page.getByTestId('dash-week-lead').boundingBox();
		const firstGroup = await groups.first().boundingBox();
		expect(lead!.y, 'today sits above the divider').toBeLessThan(dividerBox!.y);
		expect(firstGroup!.y, 'the trend groups sit below it').toBeGreaterThan(dividerBox!.y);
	});

	test('a trend group folds to its heading and stays folded on the next visit', async ({
		page
	}) => {
		await page.goto('/dashboard');
		await page.waitForLoadState('networkidle');

		const volume = page.locator('section.trend-group', {
			has: page.locator('#dash-trend-volume-title')
		});
		const mileage = page.getByRole('heading', { name: 'Distance', exact: true, level: 2 });
		const recentRuns = page.getByRole('heading', { name: /recent runs/i, level: 2 });
		await expect(mileage).toBeVisible({ timeout: 10_000 });

		// Open by default: a returning runner finds every card where it was.
		await expect(volume.locator('details')).toHaveAttribute('open', '');

		await volume.locator('summary').click();
		await expect(mileage, 'the folded group hides its cards').toBeHidden();
		await expect(
			volume.getByRole('heading', { name: 'Volume', level: 2 }),
			'and keeps its one-line heading'
		).toBeVisible();
		await expect(recentRuns, 'a fold is per group, not page-wide').toBeVisible();

		// Remembered on this device for this account (disclosure_state.ts).
		await page.reload();
		await page.waitForLoadState('networkidle');
		await expect(page.locator('#dash-trend-volume-title')).toBeVisible({ timeout: 10_000 });
		await expect(mileage).toBeHidden();
		await expect(recentRuns).toBeVisible();

		await volume.locator('summary').click();
		await expect(mileage).toBeVisible();
	});
});
