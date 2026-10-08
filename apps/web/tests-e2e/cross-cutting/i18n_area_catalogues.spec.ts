import { expect, test, type BrowserContext, type Page } from '@playwright/test';
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

/**
 * Server-rendered pages (decisions § 1812). `/learn` is prerendered in
 * production and every page is server-rendered under the dev server this
 * suite runs against, always in English: there is no request-time renderer in
 * production to know the reader's language. Before § 1812 such a page hydrated
 * in English — fetching the route's ENGLISH catalogue parts to do it — and
 * only switched on mount. Now the first load applies the reader's locale
 * before hydrating, so the only parts requested are the reader's own.
 *
 * Every h1 text the document ever holds is recorded from before the first
 * byte is parsed: the server's English, then whatever hydration writes. The
 * contract is that the first thing the app writes is already the translation,
 * and that nothing after it is English or a key name.
 */
async function recordHeadings(context: BrowserContext): Promise<void> {
	await context.addInitScript(() => {
		const seen: string[] = [];
		(window as unknown as { __h1: string[] }).__h1 = seen;
		const record = () => {
			const text = document.querySelector('h1')?.textContent?.trim();
			if (text && seen.at(-1) !== text) seen.push(text);
		};
		new MutationObserver(record).observe(document, {
			subtree: true,
			childList: true,
			characterData: true,
		});
	});
}

function englishPartRequests(page: Page): string[] {
	const hits: string[] = [];
	page.on('request', (request) => {
		const url = decodeURIComponent(request.url());
		// The English core is the bundled fallback every reader has; any other
		// English part is a download a Japanese reader has no use for.
		if (/i18n-catalogue\/en\/(?!core\b)/.test(url)) hits.push(url);
	});
	return hits;
}

test.describe('a server-rendered page hydrates in the reader locale', () => {
	for (const { path, english, japanese, namespace } of [
		{ path: '/learn', english: 'Learn to run', japanese: 'ランニングを学ぶ', namespace: 'learn' },
		{ path: '/login', english: 'Sign in to your account', japanese: 'アカウントにサインイン', namespace: 'login' },
	]) {
		test(`${path} fetches no English catalogue part and writes Japanese first`, async ({ browser }) => {
			const context = await browser.newContext({
				locale: 'ja-JP',
				storageState: { cookies: [], origins: [] },
			});
			await recordHeadings(context);
			const page = await context.newPage();
			const englishParts = englishPartRequests(page);

			await page.goto(path);
			await expect(page.locator('html')).toHaveAttribute('lang', 'ja');
			await expect(page.locator('h1').first()).toHaveText(japanese);

			const headings = await page.evaluate(() => (window as unknown as { __h1: string[] }).__h1);
			const written = headings[0] === english ? headings.slice(1) : headings;
			expect(written[0], `the first heading the app wrote on ${path}`).toBe(japanese);
			expect(written.filter((h) => h !== japanese), 'a heading other than the translation').toEqual([]);
			expect(englishParts, 'English catalogue parts requested by a Japanese reader').toEqual([]);
			await expectNoRawKeys(page, [namespace]);
			await context.close();
		});
	}
});

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
		// `gym.log` is a `gym` area key. The accessible name, not the text: the
		// button's icon ligature (`add`) is text content, hidden from the name.
		await expect(page.getByTestId('gym-log')).toHaveAccessibleName('Workout erfassen', {
			timeout: 10_000,
		});
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
