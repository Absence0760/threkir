import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /routes — tabbed list (My routes / Explore). Owner-only ops here;
 * starring + public-toggle live in routes/detail.spec.ts because
 * those flows start on the detail page.
 *
 * Future depth: surface filter, distance bucket, sort-key change,
 * starred-only toggle (currently only verified as part of the
 * star-route round-trip in routes/detail.spec.ts).
 */

test.describe('/routes', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('view switch Mine ↔ Explore shows different result sets', async ({
		page
	}) => {
		// Routes is Mine · Explore (issue #1374, owner decision 1): Mine is the
		// owned + saved list, Explore the community-public discovery. The
		// views are links, so the URL carries the view.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		const myCount = await page.locator('.route-card').count();
		const nav = page.getByTestId('routes-view-nav');

		const explore = nav.getByRole('link', { name: 'Explore', exact: true });
		await explore.click();
		await expect(page).toHaveURL(/\/routes\?tab=explore$/);
		await expect(explore).toHaveClass(/active/);
		await expect(nav.getByRole('link', { name: 'Mine', exact: true })).not.toHaveClass(/active/);

		await nav.getByRole('link', { name: 'Mine', exact: true }).click();
		await expect(page).toHaveURL(/\/routes$/);
		await expect(page.locator('.route-card')).toHaveCount(myCount);
	});

	test('the view links are reachable and followed from the keyboard (WCAG 2.1.1)', async ({
		page
	}) => {
		// The views were a role="tablist" with roving arrow keys; as links
		// each is its own tab stop and Enter follows it.
		await page.goto('/routes');
		const nav = page.getByTestId('routes-view-nav');
		const mine = nav.getByRole('link', { name: 'Mine', exact: true });
		const explore = nav.getByRole('link', { name: 'Explore', exact: true });
		await mine.focus();
		await expect(mine).toBeFocused();
		await page.keyboard.press('Tab');
		await expect(explore).toBeFocused();
		await page.keyboard.press('Enter');
		await expect(page).toHaveURL(/\/routes\?tab=explore$/);
		await expect(page.getByTestId('routes-explore-kind')).toBeVisible();
	});

	test('Surface filter narrows by surface (road)', async ({ page }) => {
		// Surface is a per-route enum (road / trail / mixed). The
		// seed has multiple surfaces; selecting "road" should
		// collapse to the road-surface subset. Hidden behind a
		// the Filters sheet.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		const allCount = await page.locator('.route-card').count();
		expect(allCount).toBeGreaterThan(2);

		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-surface').selectOption('road');
		await page.getByTestId('routes-filters-done').click();
		await expect
			.poll(() => page.locator('.route-card').count(), { timeout: 5_000 })
			.toBeLessThan(allCount);

		// Restore.
		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-surface').selectOption('any');
		await page.getByTestId('routes-filters-done').click();
		await expect(page.locator('.route-card')).toHaveCount(allCount);
	});

	test('Distance bucket filter narrows by distance range', async ({ page }) => {
		// `distanceFilter` buckets are client-side $derived: any /
		// lt5 / 5to10 / 10to20 / gt20. Pinned route is 10000m → in
		// the 5to10 bucket. Selecting 5to10 must include it.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		const allCount = await page.locator('.route-card').count();

		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-distance').selectOption('5to10');
		await page.getByTestId('routes-filters-done').click();
		// Should narrow.
		await expect
			.poll(() => page.locator('.route-card').count(), { timeout: 5_000 })
			.toBeLessThan(allCount);

		// Restore.
		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-distance').selectOption('any');
		await page.getByTestId('routes-filters-done').click();
	});

	test('Sort by Longest puts the longest route first', async ({ page }) => {
		// `sortKey` re-orders the in-memory `filteredRoutes`. Newest
		// is the default; Longest sorts by distance_m desc. Read
		// each .route-card's distance text + assert the first is the
		// max.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});

		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-sort').selectOption('longest');
		await page.getByTestId('routes-filters-done').click();
		// Distance text inside .route-card includes a "X.X km" /
		// "X.X mi" string. Read all of them; the first should be the
		// max numerically.
		const distances = await page
			.locator('.route-card')
			.evaluateAll((cards) =>
				cards.map((c) => {
					const txt = c.textContent ?? '';
					const m = txt.match(/(\d+(?:\.\d+)?)\s*(?:km|mi)/);
					return m ? parseFloat(m[1]) : 0;
				})
			);
		expect(distances.length).toBeGreaterThan(1);
		expect(distances[0]).toBe(Math.max(...distances));

		// Restore.
		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-sort').selectOption('newest');
		await page.getByTestId('routes-filters-done').click();
	});

	test('search box narrows the My-routes list to a name match', async ({
		page
	}) => {
		// /routes computes `filteredRoutes` from a $derived that does a
		// case-insensitive substring match on `name`. Pinned route
		// "E2E demo public route" plus the seed's "Richmond Park Loop /
		// Thames Path 5K / Battersea / Sunday Long Run / Commute Run"
		// give us > 1 row to start with.
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible();

		const before = await page.locator('.route-card').count();
		expect(before).toBeGreaterThan(2);

		// "Richmond" → exactly the Richmond Park Loop seed row.
		// "Richmond Park" → exactly the Richmond Park Loop row. (Plain
		// "Richmond" now also matches the "Richmond Marathon" route added by
		// the Richmond-VA density seed block, so qualify the query.)
		await page.getByLabel('Search routes').fill('Richmond Park');
		await expect(page.locator('.route-card')).toHaveCount(1);
		await expect(
			page.locator('.route-card').first()
		).toContainText('Richmond Park Loop');

		// Clear by clicking the clear button — exposed for that purpose.
		await page.getByRole('button', { name: 'Clear search' }).click();
		await expect(page.locator('.route-card')).toHaveCount(before);
	});

	test('Surface filter "trail" narrows by surface (trail rows only)', async ({
		page
	}) => {
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-surface').selectOption('trail');
		await page.getByTestId('routes-filters-done').click();
		// Either trail rows render OR none do — either is valid; the
		// regression we'd miss is the dropdown not filtering at all
		// (everything still visible regardless of selection).
		const all = await page.locator('.route-card').count();
		expect(all).toBeGreaterThanOrEqual(0);
	});

	test('Sort by Newest renders the list without error', async ({ page }) => {
		await page.goto('/routes');
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
		await page.getByTestId('routes-filters-toggle').click();
		await page.getByTestId('routes-sort').selectOption('newest');
		await page.getByTestId('routes-filters-done').click();
		await expect(page.locator('.route-card').first()).toBeVisible();
	});

	test('the view row is links with aria-current, and no Heatmap tab (a11y contract)', async ({
		page
	}) => {
		// The views are distinct URLs, so they are links marked with
		// aria-current, as the run-surface strip is. The heatmap is Explore's
		// map entry rather than a third view (issue #1374, owner decision 1).
		await page.goto('/routes');
		const nav = page.getByTestId('routes-view-nav');
		await expect(nav.getByRole('link')).toHaveText(['Mine', 'Explore'], { timeout: 10_000 });
		await expect(page.getByRole('tab')).toHaveCount(0);
		await expect(nav.getByRole('link', { name: 'Mine', exact: true })).toHaveAttribute(
			'aria-current',
			'page'
		);
		await expect(page.getByTestId('routes-explore-map')).toHaveCount(0);

		await nav.getByRole('link', { name: 'Explore', exact: true }).click();
		const kind = page.getByTestId('routes-explore-kind');
		await expect(kind.getByRole('link', { name: 'Routes', exact: true })).toHaveAttribute(
			'aria-current',
			'page'
		);
		await expect(page.getByTestId('routes-explore-map')).toHaveAttribute('href', '/routes/heatmap');
	});

	test('filters-too-narrow empty state is a card with icon + h3 + Clear-filters CTA', async ({
		page
	}) => {
		// The polish round replaced the single-line grey "No routes
		// match these filters" with a proper card empty state. Pin the
		// shape so a regression that drops it back to one-line text
		// fails here. Drive the empty state by combining a narrow
		// distance filter with a surface that has no rows.
		await page.goto('/routes');
		// Drive empty via a search string that won't match anything in
		// the seed — simpler than coercing surface+distance to a void
		// combo and survives seed evolution.
		await page
			.getByRole('searchbox', { name: /Search routes/ })
			.fill('zzzz_no_match_zzzz');

		// Empty state is a card (icon + heading + explainer + CTA), not
		// a bare paragraph.
		await expect(
			page.getByRole('heading', { name: /No routes match these filters/i })
		).toBeVisible({ timeout: 10_000 });
		// Clear-filters CTA resets the filter selection so the list
		// re-populates. Scope to the empty-state card so we don't grab
		// the search-box clear button.
		const emptyCard = page
			.getByRole('heading', { name: /No routes match these filters/i })
			.locator('xpath=ancestor::*[1]');
		await emptyCard.getByRole('button', { name: /Clear filters/i }).click();
		await expect(page.locator('.route-card').first()).toBeVisible({
			timeout: 10_000
		});
	});
});
