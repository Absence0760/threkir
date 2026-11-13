import { expect, test } from '../fixtures/test';

import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import { acceptCookieConsent } from '../fixtures/helpers';

/**
 * /runs name search (issue #1374): one AppSearchField in the run list's
 * FilterBar, over the runner's own run names (`metadata.title`), case- and
 * accent-insensitive, with a clear button. A search narrows like a filter, so
 * it reads the whole history: the older run below is far past the first page
 * of fifty the unfiltered list starts with.
 */

const tag = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const DAY_MS = 86_400_000;

test.describe('/runs — name search', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let oldId = '';
	let newId = '';

	test.beforeAll(async () => {
		oldId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 900 * DAY_MS).toISOString(),
			duration_s: 1500,
			distance_m: 5000,
			metadata: { title: `Café Tempo ${tag}` },
		});
		newId = await insertRun({
			user_id: USER_A.id,
			started_at: new Date(Date.now() - 2 * DAY_MS).toISOString(),
			duration_s: 1800,
			distance_m: 6000,
			metadata: { title: `Hill Reps ${tag}` },
		});
	});

	test.afterAll(async () => {
		for (const id of [oldId, newId]) if (id) await deleteRun(id).catch(() => {});
	});

	test.beforeEach(async ({ page, context }) => {
		await acceptCookieConsent(context, { runs_filters_v1: null });
		await page.goto('/runs');
		await page.getByLabel('Date range').selectOption('all');
	});

	test('a search finds a run by part of its name, across the whole history', async ({ page }) => {
		const search = page.getByRole('searchbox', { name: 'Search run names' });
		await expect(search).toBeVisible({ timeout: 10_000 });

		await search.fill(`cafe tempo ${tag}`);
		await expect(page.getByTestId('runs-surface')).toHaveAttribute('data-list-state', 'loaded-full', {
			timeout: 15_000,
		});
		await expect(page.locator(`a[href="/runs/${oldId}"]`)).toBeVisible({ timeout: 15_000 });
		await expect(page.locator(`a[href="/runs/${newId}"]`)).toHaveCount(0);
	});

	test('clear empties the search, returns focus to it, and the list comes back', async ({ page }) => {
		const search = page.getByTestId('runs-search');
		const clear = page.getByRole('button', { name: 'Clear search' });
		await expect(search).toBeVisible({ timeout: 10_000 });
		// AppSearchField draws its clear only while there is text to clear.
		await expect(clear).toHaveCount(0);

		await search.fill(`hill reps ${tag}`);
		await expect(page.locator(`a[href="/runs/${newId}"]`)).toBeVisible({ timeout: 15_000 });
		await expect(page.locator(`a[href="/runs/${oldId}"]`)).toHaveCount(0);

		await expect(clear).toBeVisible();
		await expect(clear).toHaveAttribute('data-testid', 'runs-search-clear');
		await clear.click();
		await expect(search).toHaveValue('');
		await expect(search).toBeFocused();
		await expect(clear).toHaveCount(0);
		await expect(page.getByTestId('runs-empty-filtered')).toHaveCount(0);
		await expect(page.locator(`a[href="/runs/${newId}"]`)).toBeVisible({ timeout: 15_000 });
	});

	test('a search nothing matches says so, and Show all runs clears it', async ({ page }) => {
		const search = page.getByTestId('runs-search');
		await search.fill(`no run is called this ${tag}`);
		const empty = page.getByTestId('runs-empty-filtered');
		await expect(empty).toBeVisible({ timeout: 15_000 });

		await page.getByTestId('runs-empty-show-all').click();
		await expect(search).toHaveValue('');
		await expect(empty).toHaveCount(0);
	});
});
