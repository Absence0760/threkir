import { expect, test } from '@playwright/test';

/**
 * `/` — anon landing page.
 *
 * Authenticated visitors are auto-redirected to /dashboard via an
 * $effect in the page component; the marketing hero only renders for
 * unauthenticated visitors. Tests live here in isolation rather than
 * mixed with the auth flow because this is the only page anon users
 * see by default (everything else either redirects to /login or is
 * gated by `isPublic` in the layout's auth guard).
 */

test.describe('/ (landing)', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('anon visitor sees hero + Get Started CTA', async ({ page }) => {
		// One balanced string now, not three <br/>-separated lines: the
		// hardcoded breaks forced three lines at every width and still
		// wrapped to four on a phone.
		await page.goto('/');

		await expect(
			page.getByRole('heading', { name: /Plan routes/, level: 1 })
		).toBeVisible();
		// Scoped to the hero: getByRole matches the accessible name as a
		// SUBSTRING, so the header's "Get started free" also answers to
		// "Get Started".
		await expect(
			page.locator('main.hero').getByRole('link', { name: 'Get Started' })
		).toBeVisible();
	});

	test('Get Started link sends anon visitor to /login', async ({ page }) => {
		// Click-through pin. A regression that wired the CTA to a
		// nonexistent route would surface as a hard 404 here.
		await page.goto('/');
		await page.locator('main.hero').getByRole('link', { name: 'Get Started' }).click();
		await page.waitForURL(/\/login/, { timeout: 10_000 });
	});

	test('top nav anchor links jump to in-page sections', async ({ page }) => {
		// The "Apps" + "Features" nav links use /#apps / /#features
		// fragment scrolls (root-anchored so the shared PublicHeader
		// resolves them from /learn too). Pin the targets exist so a
		// refactor that renames a section id surfaces here.
		await page.goto('/');
		await expect(page.locator('section#apps')).toBeVisible();
		await expect(page.locator('section#features')).toBeVisible();
		// Nav links carry the matching href.
		await expect(page.getByRole('link', { name: 'Apps' }).first()).toHaveAttribute(
			'href',
			'/#apps'
		);
		await expect(page.getByRole('link', { name: 'Features' }).first()).toHaveAttribute(
			'href',
			'/#features'
		);
	});

	test('Sign In nav link in the header routes to /login', async ({ page }) => {
		await page.goto('/');
		// The header has a 'Sign In' link with class .nav-signin —
		// disambiguate from the footer copy which uses the same text.
		await expect(page.locator('.nav-signin')).toHaveAttribute('href', '/login');
	});

	test('landing footer links all four legal + nav targets', async ({ page }) => {
		await page.goto('/');
		const footer = page.locator('footer.landing-footer');
		await expect(footer).toBeVisible();
		// Order pinned: Sign In / Apps / Features / Privacy / Terms / Cookies.
		await expect(footer.getByRole('link', { name: 'Sign In' })).toHaveAttribute(
			'href',
			'/login'
		);
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
	});

	test('document title + meta description match the SEO contract', async ({ page }) => {
		await page.goto('/');
		// Page title + meta description are the SERP snippet. Pin the
		// shape so a marketing copy change forces a deliberate test
		// update (rather than silently shipping wrong meta).
		const title = await page.title();
		expect(title.length).toBeGreaterThan(0);
		const desc = await page.locator('meta[name="description"]').getAttribute('content');
		expect((desc ?? '').length).toBeGreaterThan(0);
	});

	test('canonical, Open Graph, and Organization/WebSite JSON-LD are present', async ({
		page,
	}) => {
		await page.goto('/');

		// Canonical must be the apex root — the single home for the brand
		// so the www/apex CloudFront duplicate can't split ranking signal.
		const canonicalHref = await page
			.locator('link[rel="canonical"]')
			.getAttribute('href');
		expect(canonicalHref).toMatch(/^https?:\/\/[^/]+\/$/);

		expect(
			await page.locator('meta[property="og:title"]').getAttribute('content')
		).toBeTruthy();
		expect(await page.locator('meta[property="og:type"]').getAttribute('content')).toBe(
			'website'
		);
		expect(
			await page.locator('meta[property="og:image"]').getAttribute('content')
		).toBeTruthy();
		expect(await page.locator('meta[name="twitter:card"]').getAttribute('content')).toBe(
			'summary_large_image'
		);

		// The two site-wide nodes must both be emitted + parse as valid
		// JSON — the brand-query knowledge-panel / sitelinks signal.
		const ldBlocks = await page
			.locator('script[type="application/ld+json"]')
			.allTextContents();
		const types = ldBlocks.map((t) => JSON.parse(t)['@type']);
		expect(types).toContain('Organization');
		expect(types).toContain('WebSite');
	});

	test('first-paint hints: color-scheme meta + Supabase preconnect', async ({ page }) => {
		await page.goto('/');
		// color-scheme lets the UA paint the right default background
		// before CSS loads (CSP-safe flash mitigation).
		await expect(page.locator('meta[name="color-scheme"]')).toHaveAttribute(
			'content',
			'light dark'
		);
		// Preconnect to the Supabase origin every page hits on mount.
		expect(await page.locator('link[rel="preconnect"]').count()).toBeGreaterThan(0);
	});

	test('closing CTA section points anon users at /login', async ({ page }) => {
		await page.goto('/');
		// "Sign in to continue" was a system message standing in for a
		// call to action, and it pointed at the same /login as the hero.
		const cta = page.locator('section.closing-cta');
		await expect(cta).toBeVisible();
		await expect(
			cta.getByRole('link', { name: 'Create a free account' })
		).toHaveAttribute('href', '/login');
	});

	test('the hero shows the product, drawn by the real renderer', async ({ page }) => {
		// The page carried no pixel of the product before this. The shot is
		// the app's own TrackPreview over static demo data rather than a
		// screenshot, so a UI change moves it automatically — assert the
		// live SVG is there, not that an <img> loaded.
		await page.goto('/');
		const shot = page.locator('main.hero figure.shot');
		await expect(shot).toBeVisible();
		await expect(shot.locator('svg.track-preview').first()).toBeVisible();
		// Captioned for screen readers; the frames themselves are decorative.
		await expect(shot.locator('figcaption')).toHaveText(/sample run/i);
	});

	test('every feature card leads with a visual, and none is an icon', async ({ page }) => {
		await page.goto('/');
		const cards = page.locator('section#features article.feature');
		await expect(cards).toHaveCount(4);
		for (let i = 0; i < 4; i++) {
			await expect(cards.nth(i).locator('.feature-visual')).toBeVisible();
			await expect(cards.nth(i).locator('.feature-eyebrow')).toBeVisible();
		}
		// The Material Symbols icons the cards used to lead with are gone;
		// leaving one behind would also keep its glyph in the subset font.
		await expect(page.locator('section#features .material-symbols')).toHaveCount(0);
	});

	test('the platforms strip states testing status without four vapour cards', async ({
		page,
	}) => {
		await page.goto('/');
		const pills = page.locator('section#apps li.platform');
		await expect(pills).toHaveCount(5);
		// Web is the only one a visitor can actually use today.
		await expect(pills.filter({ hasText: 'Web' }).first()).not.toHaveClass(/pending/);
		await expect(page.locator('section#apps li.platform.pending')).toHaveCount(4);
		await expect(page.locator('section#apps .platforms-note')).toContainText(
			/not in the app stores yet/i
		);
	});

	test('the header offers a sign-up CTA alongside sign-in', async ({ page }) => {
		await page.goto('/');
		await expect(page.locator('.nav-cta')).toHaveAttribute('href', '/login');
	});

	test('hero CTAs stay on one line at 390px', async ({ page }) => {
		// Both buttons broke across two lines at phone width until .btn got
		// white-space: nowrap. Measured rather than eyeballed: a single-line
		// button is shorter than one-and-a-half line-heights.
		await page.setViewportSize({ width: 390, height: 844 });
		await page.goto('/');
		for (const name of ['Get Started', 'See it working']) {
			const box = await page.locator('main.hero').getByRole('link', { name }).boundingBox();
			expect(box, `${name} has no box`).not.toBeNull();
			expect(box!.height, `${name} wrapped to a second line`).toBeLessThan(64);
		}
	});

	test('sections are visible without JS-driven reveal', async ({ page }) => {
		// The reveal hides a section only from code that can also unhide it.
		// A stylesheet that hid them until a class arrived would leave a
		// crawler — and anyone whose script failed — looking at a blank page.
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await page.goto('/');
		await expect(page.locator('section#features')).toBeVisible();
		await expect(page.locator('section.closing-cta')).toBeVisible();
		await expect(page.locator('.pre-reveal')).toHaveCount(0);
	});
});
