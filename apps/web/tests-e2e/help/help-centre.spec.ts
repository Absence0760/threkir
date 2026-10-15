import { expect, test } from '../fixtures/test';

import { deleteEvent, insertEvent } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';

/**
 * The in-app help centre (docs/features/help.md): /help contents, search,
 * a guide page's anchors, the per-page "How this works" link and the keyboard
 * path to all of it. The pure layers (markup parser, index, search ranking,
 * guide guards) are unit-tested under src/lib/help; this pins the wiring.
 *
 * Uses the seeded `using-help` guide, which the framework ships, so the specs
 * do not depend on any one content guide's wording.
 */

const SYDNEY_RUN_CLUB_ID = 'c1111111-0000-0000-0000-000000000001';

test.describe('/help — in-app help centre', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('contents lists guides by category and the audience chips narrow them', async ({ page }) => {
		await page.goto('/help');
		await expect(page.getByRole('heading', { level: 1, name: 'Help' })).toBeVisible();
		// English guides in an English app are not a fallback, so no guide says it is in English.
		await expect(page.getByTestId('help-language-note')).toHaveCount(0);
		await expect(page.getByRole('heading', { level: 2, name: 'Your account' })).toBeVisible();

		const card = page.getByRole('link', { name: /Finding help in the app/ });
		await expect(card).toBeVisible();

		// The page is prerendered, so the chips are on screen before Svelte binds
		// their handlers; a press that early is lost (see fixtures/helpers.ts).
		await page.waitForLoadState('networkidle');
		const all = page.getByRole('button', { name: 'All', exact: true });
		const spectators = page.getByRole('button', { name: 'Spectators' });
		await expect(all).toHaveAttribute('aria-pressed', 'true');
		await spectators.click();
		await expect(spectators).toHaveAttribute('aria-pressed', 'true');
		await expect(all).toHaveAttribute('aria-pressed', 'false');
		// A guide written for everyone stays listed under every group.
		await expect(card).toBeVisible();
	});

	test('search ranks a title match first and ignores case and accents', async ({ page }) => {
		await page.goto('/help');
		await page.getByRole('searchbox', { name: 'Search the guides' }).fill('FINDING help');
		await page.getByRole('button', { name: 'Search', exact: true }).click();

		await expect(page).toHaveURL(/\/help\/search\?q=FINDING\+help$/);
		const results = page.getByTestId('help-search-results').getByRole('link');
		await expect(results.first()).toContainText('Finding help in the app');

		await page.goto('/help/search?q=cafe');
		await expect(page.getByTestId('help-search-results')).toContainText('Finding help in the app');

		await page.goto('/help/search?q=zzqxv');
		await expect(page.getByText('No guides match “zzqxv”')).toBeVisible();
		await expect(page.getByTestId('help-search-results')).toHaveCount(0);
	});

	test('a guide page renders badges, On this page anchors and notes', async ({ page }) => {
		await page.goto('/help/using-help');
		const guide = page.getByTestId('help-guide');
		await expect(guide.getByRole('heading', { level: 1, name: 'Finding help in the app' })).toBeVisible();
		await expect(guide.getByText('Works on')).toBeVisible();

		const onPage = page.getByRole('navigation', { name: 'On this page' });
		await onPage.getByRole('link', { name: 'Searching the guides' }).click();
		await expect(page).toHaveURL(/\/help\/using-help#searching-the-guides$/);
		await expect(page.getByRole('heading', { level: 2, name: 'Searching the guides' })).toBeInViewport();

		await expect(guide.getByText('Tip', { exact: true }).first()).toBeVisible();
		await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', 'noindex');
	});

	test('a guide illustration renders inline, themed, and is announced by its alt text', async ({ page }) => {
		await page.goto('/help/privacy-zones');
		const figure = page.getByTestId('help-illustration');
		await expect(figure).toHaveAttribute('data-illustration', 'privacy-zones');
		const art = figure.getByRole('img', { name: /A route line starts at a house inside a circle/ });
		await expect(art).toBeVisible();
		const svg = art.locator('svg');
		await expect(svg).toHaveAttribute('aria-hidden', 'true');
		await expect(svg.locator('text')).toHaveCount(0);
		const fill = await svg.locator('circle').first().evaluate((el) => getComputedStyle(el).fill);
		expect(fill).not.toBe('rgb(255, 0, 162)');
		expect(fill).not.toBe('none');
	});

	test('an unknown guide id says so and links back to the contents', async ({ page }) => {
		await page.goto('/help/no-such-guide');
		await expect(page.getByRole('heading', { name: 'Guide not found' })).toBeVisible();
		await page.getByRole('link', { name: 'All guides' }).click();
		await expect(page).toHaveURL(/\/help$/);
	});

	test('the keyboard reaches help from the account menu and searches it', async ({ page }) => {
		await page.goto('/dashboard');
		await page.locator('.profile-btn').click();
		const help = page.getByRole('menuitem', { name: 'Help' });
		await page.keyboard.press('End');
		await page.keyboard.press('ArrowUp');
		await expect(help).toBeFocused();
		await page.keyboard.press('Enter');
		await expect(page).toHaveURL(/\/help$/);

		const box = page.getByRole('searchbox', { name: 'Search the guides' });
		await box.focus();
		await page.keyboard.type('search');
		await page.keyboard.press('Enter');
		await expect(page).toHaveURL(/\/help\/search\?q=search$/);

		await page.goto('/help');
		await page.waitForLoadState('networkidle');
		const organisers = page.getByRole('button', { name: 'Organisers' });
		await organisers.focus();
		await page.keyboard.press('Space');
		await expect(organisers).toHaveAttribute('aria-pressed', 'true');
	});

	test.describe('How this works', () => {
		let eventId: string | null = null;

		test.afterEach(async () => {
			if (eventId) {
				try {
					await deleteEvent(eventId);
				} catch (_) {
					/* best-effort */
				}
				eventId = null;
			}
		});

		test('the event page links to a guide that covers it', async ({ page }) => {
			const title = `e2e help link ${Date.now()}`;
			eventId = await insertEvent({
				club_id: SYDNEY_RUN_CLUB_ID,
				author_id: USER_A.id,
				title,
				duration_min: 60,
				starts_at: new Date(Date.now() + 7 * 24 * 3600 * 1000).toISOString(),
			});

			await page.goto(`/clubs/richmond-run-club/events/${eventId}`);
			await expect(page.getByRole('heading', { name: title })).toBeVisible({ timeout: 10_000 });

			const entry = page.getByTestId('help-link');
			await expect(entry).toBeVisible();
			// One guide: a plain link. Several: a disclosure listing them.
			if ((await entry.evaluate((el) => el.tagName)) === 'DETAILS') {
				await entry.locator('summary').press('Enter');
				await entry.getByRole('link').first().click();
			} else {
				await entry.press('Enter');
			}
			await expect(page).toHaveURL(/\/help\/[a-z0-9-]+$/);
			await expect(page.getByTestId('help-guide').getByRole('heading', { level: 1 })).toBeVisible();
		});
	});
});

/**
 * The public live-event page links a signed-out spectator to the guides
 * (decisions § 1866), so the help centre must answer them rather than
 * bounce them to /login. Waiting past the auth guard's first effect is what
 * gives a redirect the chance to happen.
 */
test.describe('/help — signed out', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('a signed-out reader opens the contents, a spectator guide and search', async ({ page }) => {
		await page.goto('/help');
		await expect(page.getByTestId('help-guide-card').first()).toBeVisible({ timeout: 10_000 });
		await expect(page).toHaveURL(/\/help$/);

		await page.goto('/help/follow-a-race-live');
		const guide = page.getByTestId('help-guide');
		await expect(guide.getByRole('heading', { level: 1, name: 'Follow a race live' })).toBeVisible({
			timeout: 10_000,
		});
		await page.waitForLoadState('networkidle');
		await expect(page).toHaveURL(/\/help\/follow-a-race-live$/);

		await page.goto('/help/search?q=race');
		await expect(page.getByTestId('help-search-results')).toBeVisible({ timeout: 10_000 });
		await expect(page).not.toHaveURL(/\/login/);
	});
});

/**
 * A guide illustration in the two contexts the light-English case above does
 * not reach. Dark: the placeholders must resolve to the dark theme's tokens,
 * not the light ones and never the authoring magenta (#ff00a1–#ff00a7). A
 * translated locale: the alt text is a translated block string, carried by the
 * fetched per-locale guide JSON, so a merge that dropped it would announce the
 * figure in English. Signed out, so no stored theme or locale preference on an
 * account outranks the one the spec sets.
 */
test.describe('/help — illustration in dark mode and German', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	const PLACEHOLDER = /^rgb\(255, 0, 16[1-7]\)$/;

	test('dark: the figure keeps its alt and paints with the dark theme tokens', async ({ page }) => {
		await page.emulateMedia({ colorScheme: 'dark' });
		await page.goto('/help/privacy-zones');
		const figure = page.getByTestId('help-illustration');
		const art = figure.getByRole('img', { name: /A route line starts at a house inside a circle/ });
		await expect(art).toBeVisible({ timeout: 10_000 });

		const paint = await figure.evaluate((fig) => {
			const resolve = (token: string) => {
				const probe = document.createElement('span');
				probe.style.color = `var(${token})`;
				fig.appendChild(probe);
				const c = getComputedStyle(probe).color;
				probe.remove();
				return c;
			};
			const circles = fig.querySelectorAll('svg circle');
			return {
				map: getComputedStyle(fig.querySelector('svg rect')!).fill,
				endpoint: getComputedStyle(circles[circles.length - 1]).fill,
				tint: resolve('--color-bg-tertiary'),
				primary: resolve('--color-primary'),
				surface: getComputedStyle(fig).backgroundColor
			};
		});
		expect(paint.map).not.toMatch(PLACEHOLDER);
		expect(paint.endpoint).not.toMatch(PLACEHOLDER);
		expect(paint.map).toBe(paint.tint);
		expect(paint.endpoint).toBe(paint.primary);
		// The dark tokens, not the light ones: the light surface is white.
		expect(paint.surface).not.toBe('rgb(255, 255, 255)');
	});

	test('de: the figure is announced by its German alt text', async ({ context, page }) => {
		await context.addInitScript(() => {
			localStorage.setItem('locale', 'de');
		});
		await page.goto('/help/privacy-zones');
		const figure = page.getByTestId('help-illustration');
		await expect(figure).toHaveAttribute('data-illustration', 'privacy-zones');
		await expect(
			figure.getByRole('img', { name: /Eine Routenlinie beginnt an einem Haus in einem Kreis/ })
		).toBeVisible({ timeout: 15_000 });
		await expect(figure.getByRole('img', { name: /A route line starts/ })).toHaveCount(0);
		await expect(page.getByTestId('help-language-note')).toHaveCount(0);
	});
});
