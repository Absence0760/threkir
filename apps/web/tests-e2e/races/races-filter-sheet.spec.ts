import { expect, test } from '../fixtures/test';

import { USER_A } from '../fixtures/users';

/**
 * /races on FilterBar (issue #1374): the search (in every view, decisions
 * § 2519) and the All · Races · Courses chips on the bar, everything else in a Filters sheet that holds each
 * control's explanation beside it (the owner moved the hints off the page),
 * the active filters as removable chips on the chip line, and a sheet that
 * traps focus while open and hands it back to the Filters button on close.
 */

test.describe('/races — FilterBar and the Filters sheet', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('the page shows no filter hints; the sheet shows one beside every control', async ({ page }) => {
		await page.goto('/races');
		const toggle = page.getByTestId('races-filters-toggle');
		await expect(toggle).toBeVisible({ timeout: 10_000 });
		await expect(page.locator('.filter-hint')).toHaveCount(0);

		await toggle.click();
		const sheet = page.getByTestId('races-filters-panel');
		await expect(sheet).toBeVisible();
		await expect(sheet.getByRole('heading', { level: 2, name: 'Filters' })).toBeVisible();

		// Each control's description is an element inside the sheet itself.
		const outside = await sheet.evaluate((el) => {
			const bad: string[] = [];
			for (const c of el.querySelectorAll('input, select, [role="group"]')) {
				const ids = (c.getAttribute('aria-describedby') ?? '').split(/\s+/).filter(Boolean);
				if (ids.length === 0) bad.push(`${c.tagName} has no description`);
				for (const id of ids) {
					const target = el.ownerDocument.getElementById(id);
					if (!target || !el.contains(target)) bad.push(`${c.tagName} -> #${id} is outside the sheet`);
				}
			}
			return bad;
		});
		expect(outside).toEqual([]);
		await expect(sheet.getByRole('group', { name: 'When' })).toHaveAccessibleDescription(/last 30 days/);
		await expect(sheet.getByRole('group', { name: 'Distance' })).toHaveAccessibleDescription(/recorded distance/);
		await expect(sheet.getByRole('searchbox', { name: 'Near a place…' })).toHaveAccessibleDescription(
			/Looks the place up on the map/,
		);
		// The search and Show chips stay on the bar; their explanations open here.
		await expect(sheet.getByTestId('races-sheet-notes')).toContainText(
			'Finds races by name, and park courses by name, park or state',
		);
		await expect(sheet.getByTestId('races-sheet-notes')).toContainText('the park courses alone');
	});

	test('the sheet traps focus, Escape closes it, and focus returns to Filters', async ({ page }) => {
		await page.goto('/races');
		const toggle = page.getByTestId('races-filters-toggle');
		await toggle.click({ timeout: 10_000 });
		const sheet = page.getByTestId('races-filters-panel');
		await expect(sheet).toBeVisible();
		await expect(toggle).toHaveAttribute('aria-expanded', 'true');

		for (let i = 0; i < 25; i++) {
			await page.keyboard.press('Tab');
			const inside = await sheet.evaluate((el) => el.contains(document.activeElement));
			expect(inside, `Tab ${i + 1} left the sheet`).toBe(true);
		}

		await page.keyboard.press('Escape');
		await expect(sheet).toHaveCount(0);
		await expect(toggle).toBeFocused();
		await expect(toggle).toHaveAttribute('aria-expanded', 'false');
	});

	test('a filter set in the sheet counts on the button and shows as a removable chip', async ({ page }) => {
		await page.goto('/races');
		const toggle = page.getByTestId('races-filters-toggle');
		await expect(toggle).toHaveAccessibleName('Filters', { timeout: 10_000 });

		await toggle.click();
		await page.getByTestId('races-when-recent').click();
		await page.getByTestId('races-dist-10k').click();
		await page.getByTestId('races-filters-done').click();
		await expect(page.getByTestId('races-filters-panel')).toHaveCount(0);
		await expect(toggle).toBeFocused();

		await expect(page.getByTestId('races-filter-count')).toHaveText('2');
		await expect(toggle).toHaveAccessibleName('Filters, 2 on');
		const line = page.getByTestId('races-active-filters');
		await expect(line.getByRole('button')).toHaveCount(2);

		await page.getByRole('button', { name: '10K, remove filter' }).click();
		await expect(page.getByTestId('races-filter-count')).toHaveText('1');
		await page.getByRole('button', { name: 'Recent results, remove filter' }).click();
		await expect(page.getByTestId('races-filter-count')).toHaveCount(0);
		await expect(line).toHaveCount(0);
	});

	test('the Show chips are toggle buttons on one line that never wraps, even at 320 px', async ({ page }) => {
		await page.setViewportSize({ width: 320, height: 700 });
		await page.goto('/races');
		const show = page.getByRole('group', { name: 'Show' });
		await expect(show).toBeVisible({ timeout: 10_000 });
		await expect(show.getByRole('button', { name: 'All' })).toHaveAttribute('aria-pressed', 'true');
		await expect(show.getByRole('link')).toHaveCount(0);

		// Turn two filters on so the line carries removable chips as well.
		await page.getByTestId('races-filters-toggle').click();
		await page.getByTestId('races-when-recent').click();
		await page.getByTestId('races-dist-half').click();
		await page.getByTestId('races-filters-done').click();

		const tops = await page
			.getByTestId('races-chip-line')
			.locator('button')
			.evaluateAll((els) => els.map((e) => Math.round(e.getBoundingClientRect().top)));
		expect(tops.length).toBe(5);
		expect(new Set(tops).size, 'every chip on the line sits on the same row').toBe(1);
		const fits = await page.evaluate(
			() => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
		);
		expect(fits, 'the chip line scrolls inside itself rather than widening the page').toBe(true);
	});

	// decisions § 2519: the search stays in every view; Courses drops only the
	// race filters, which have nothing to narrow there.
	test('the Courses view keeps the search and the Show chips, without race filters', async ({ page }) => {
		await page.goto('/races?show=courses');
		await expect(page.getByTestId('races-show-courses')).toHaveAttribute('aria-pressed', 'true', {
			timeout: 10_000,
		});
		const search = page.getByRole('searchbox', { name: 'Search parks and courses…' });
		await expect(search).toBeVisible();
		await expect(search).toHaveAccessibleDescription(/park courses by name, park or state/);
		await expect(page.getByTestId('races-filters-toggle')).toHaveCount(0);
		await expect(page.getByTestId('races-any-time').getByTestId('races-near')).toBeVisible();
	});
});
