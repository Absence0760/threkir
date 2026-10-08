import { expect, test, type Page } from '@playwright/test';
import { USER_A } from '../fixtures/users';

/**
 * Area-scoped message catalogues (decisions § 1802).
 *
 * A locale is no longer one chunk: it is a core catalogue plus one per area
 * (lib/i18n/areas.ts), and the root layout's `load` fetches the areas a route
 * needs before it renders, because `m()` is synchronous and an area arriving
 * after first render would show raw key names. These tests drive exactly that
 * window: a COLD deep link straight into an area page, in a language other
 * than English, where nothing has been fetched yet — and then a client-side
 * hop into a second area, which has to load in the reader's language too.
 *
 * The negative assertions look for the area's own key namespace in the page
 * text. A raw key is the failure this split can produce, so the test names it
 * rather than only checking that one translated string is present.
 */

async function expectNoRawKeys(page: Page, namespaces: string[]): Promise<void> {
	const text = await page.locator('body').innerText();
	for (const ns of namespaces) {
		expect(text, `a raw ${ns}.* key reached the page`).not.toMatch(
			new RegExp(`\\b${ns}\\.[a-zA-Z_]+[.a-zA-Z_]*\\b`),
		);
	}
}

test.describe('area catalogues on a cold deep link', () => {
	test('an anonymous Japanese reader lands on /login in Japanese', async ({ browser }) => {
		const context = await browser.newContext({
			locale: 'ja-JP',
			storageState: { cookies: [], origins: [] },
		});
		const page = await context.newPage();
		await page.goto('/login');
		await expect(page.locator('html')).toHaveAttribute('lang', 'ja');
		// `login.headline.signin` lives in the `login` area catalogue, not core.
		await expect(page.locator('h1')).toHaveText('アカウントにサインイン');
		await expect(page.getByRole('button', { name: 'Google で続行' })).toBeVisible();
		await expectNoRawKeys(page, ['login']);
		await context.close();
	});

	test('a German reader deep-linked into /gym, then into /runs, reads German in both areas', async ({
		browser,
	}) => {
		const context = await browser.newContext({
			locale: 'de-DE',
			storageState: USER_A.storageStatePath,
		});
		// A stored choice wins over the browser language, and the seeded storage
		// state may carry one from the picker specs; pin it so this reads German.
		await context.addInitScript(() => {
			try {
				localStorage.setItem('locale', 'de');
			} catch {
				/* storage unavailable — the browser locale above still says de */
			}
		});
		const page = await context.newPage();

		await page.goto('/gym');
		await expect(page.locator('html')).toHaveAttribute('lang', 'de');
		// `gym.log` is a `gym` area key.
		await expect(page.getByTestId('gym-log')).toHaveText('Workout erfassen', { timeout: 10_000 });
		await expectNoRawKeys(page, ['gym']);

		// Client-side navigation into a second area: the root load re-runs for
		// the new route and fetches the `runs` area — in German, because the
		// locale is already applied, before /runs renders.
		await page.getByRole('link', { name: 'Läufe', exact: true }).first().click();
		await expect(page).toHaveURL(/\/runs$/);
		await expect(page.getByRole('heading', { level: 1, name: 'Laufverlauf' })).toBeAttached();
		await expectNoRawKeys(page, ['runs', 'history']);

		await context.close();
	});
});
