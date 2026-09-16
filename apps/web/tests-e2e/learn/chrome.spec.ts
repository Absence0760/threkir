import { expect, test } from '@playwright/test';

/**
 * /learn shares the landing page's public chrome (issue #212).
 *
 * The hub, category, and guide pages render the same PublicHeader
 * (wordmark + Apps / Features / Learn / Sign In) and PublicFooter
 * (legal links) the landing page uses, so the marketing surface keeps
 * one identity when a visitor clicks "Learn" from the homepage. Pin
 * the shared pieces on all three learn routes so a regression back to
 * a hand-rolled header surfaces here.
 */

const LEARN_PAGES = ['/learn', '/learn/category/getting-started', '/learn/couch-to-5k'];

test.describe('/learn shared public chrome', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const path of LEARN_PAGES) {
		test(`${path} renders the landing header (wordmark + nav links)`, async ({ page }) => {
			await page.goto(path);

			const nav = page.locator('nav.landing-nav');
			await expect(nav).toBeVisible();

			// Wordmark image logo linking home — not the old plain-text
			// "Threkir" learn-logo.
			const logo = nav.locator('a.landing-logo');
			await expect(logo).toHaveAttribute('href', '/');
			await expect(logo.locator('img[alt="Threkir"]').first()).toBeVisible();

			// Same nav as the landing page. The in-page Apps + Features
			// anchors are gone from the bar, so nothing here is a fragment.
			await expect(nav.getByRole('link', { name: 'Learn' })).toHaveAttribute('href', '/learn');
			await expect(nav.locator('.nav-signin')).toHaveAttribute('href', '/login');
		});

		test(`${path} renders the landing footer with the legal links`, async ({ page }) => {
			await page.goto(path);

			const footer = page.locator('footer.landing-footer');
			await expect(footer).toBeVisible();
			await expect(footer.getByRole('link', { name: 'Privacy' })).toHaveAttribute(
				'href',
				'/privacy'
			);
			await expect(footer.getByRole('link', { name: 'Terms' })).toHaveAttribute(
				'href',
				'/terms'
			);
			await expect(footer.getByRole('link', { name: 'Cookies' })).toHaveAttribute(
				'href',
				'/cookie-notice'
			);
			await expect(footer.getByRole('link', { name: 'Health data' })).toHaveAttribute(
				'href',
				'/health-data-notice'
			);
		});
	}

	test('header Sign In routes to /login from /learn', async ({ page }) => {
		await page.goto('/learn');
		await page.locator('nav.landing-nav .nav-signin').click();
		await page.waitForURL(/\/login/, { timeout: 10_000 });
	});

	/**
	 * The landing page takes PublicHeader's `overlay` variant and /learn the
	 * `solid` one. They may differ in ground, border, and positioning — but
	 * NOT in box metrics: each variant used to set its own padding, and solid
	 * came out 15px shorter, so the wordmark and the Sign In pill jumped up
	 * 8px the moment a visitor clicked Learn. Same header, same places.
	 */
	for (const width of [1440, 700]) {
		test(`the header sits identically on / and /learn at ${width}px`, async ({ page }) => {
			await page.setViewportSize({ width, height: 900 });

			const measure = async (path: string) => {
				await page.goto(path);
				const box = async (sel: string) => {
					const b = await page.locator(sel).first().boundingBox();
					if (!b) throw new Error(`no box for ${sel} on ${path}`);
					return { x: Math.round(b.x), y: Math.round(b.y), h: Math.round(b.height) };
				};
				return {
					logo: await box('nav.landing-nav a.landing-logo'),
					signin: await box('nav.landing-nav .nav-signin'),
					navHeight: (await box('nav.landing-nav')).h,
				};
			};

			const landing = await measure('/');
			const learn = await measure('/learn');

			expect(learn.logo).toEqual(landing.logo);
			expect(learn.signin).toEqual(landing.signin);
			// Solid carries a 1px bottom border the overlay has no need for;
			// that single pixel is the only height difference allowed.
			expect(learn.navHeight - landing.navHeight).toBeLessThanOrEqual(1);
		});
	}

	// The bar stays on screen as the page scrolls, and from there it is over
	// arbitrary content rather than the dark ramp it opens on, so it paints its
	// own glass (contrast measured in learn_band_guard.test.ts).
	for (const path of ['/', '/learn']) {
		test(`${path}: the header stays pinned with its glass once scrolled`, async ({ page }) => {
			await page.setViewportSize({ width: 1440, height: 900 });
			await page.goto(path);
			const nav = page.locator('nav.landing-nav');
			await expect(nav).not.toHaveClass(/landing-nav--scrolled/);

			await page.mouse.wheel(0, 1600);
			await expect(nav).toHaveClass(/landing-nav--scrolled/);
			await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(400);
			const box = await nav.boundingBox();
			expect(box!.y, 'the header scrolled away').toBe(0);
			await expect(nav.locator('.nav-signin')).toBeInViewport();
			const alpha = await nav.evaluate((el) => {
				const m = getComputedStyle(el).backgroundColor.match(/rgba?\(([^)]+)\)/);
				const parts = m ? m[1].split(',').map(Number) : [];
				return parts.length === 4 ? parts[3] : parts.length === 3 ? 1 : 0;
			});
			expect(alpha, 'the scrolled header paints no ground of its own').toBeGreaterThan(0.5);
		});
	}

	test('an in-page jump stops below the pinned header', async ({ page }) => {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/');
		const settled = page.evaluate(
			() =>
				new Promise<void>((resolve) => {
					// Resolves once the jump's smooth scroll has stopped: no scroll
					// event for a beat after at least one arrived.
					let quiet: ReturnType<typeof setTimeout>;
					addEventListener('scroll', () => {
						clearTimeout(quiet);
						quiet = setTimeout(resolve, 200);
					});
				}),
		);
		await page.locator('main.hero').getByRole('link', { name: 'See it working' }).click();
		await settled;
		const heading = page.locator('section#features h2');
		await expect(heading).toBeInViewport();
		const nav = await page.locator('nav.landing-nav').boundingBox();
		const target = await page.locator('section#features').boundingBox();
		expect(target!.y, 'the jump landed under the header').toBeGreaterThanOrEqual(nav!.y + nav!.height - 1);
	});
});
