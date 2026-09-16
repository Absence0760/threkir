import { expect, test } from '@playwright/test';

/**
 * AuthShell — the split screen shared by every page between the landing page
 * and the app: /login (sign-in, sign-up, reset request), /auth/reset,
 * /auth/confirm-age and /auth/callback.
 *
 * The behaviour of each form has its own spec; this one holds what the shell
 * promises all of them: one main landmark owned by the page, a route home in
 * the panel, decorative art that never carries copy, and a phone layout that
 * does not scroll sideways.
 */

const PAGES = ['/login', '/login?signup=1', '/auth/reset', '/auth/confirm-age', '/auth/callback'];

test.describe('AuthShell', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	for (const path of PAGES) {
		test(`${path}: one main landmark, a route home, decorative art`, async ({ page }) => {
			await page.goto(path);
			await expect(page.locator('main#main-content')).toHaveCount(1);
			await expect(page.locator('main#main-content.auth-card')).toBeVisible();

			const panel = page.locator('aside.auth-panel');
			await expect(panel.getByRole('link', { name: 'Threkir' })).toHaveAttribute('href', '/');

			const art = panel.locator('.panel-terrain img');
			await expect(art).toHaveAttribute('alt', '');
			await expect
				.poll(() => art.evaluate((img: HTMLImageElement) => img.naturalWidth))
				.toBeGreaterThan(0);
		});
	}

	test('/login: exactly one named link home, on either side of the breakpoint', async ({ page }) => {
		await page.goto('/login');
		for (const viewport of [
			{ width: 1440, height: 900 },
			{ width: 390, height: 844 },
		]) {
			await page.setViewportSize(viewport);
			const home = page.locator('a[href="/"]:visible');
			await expect(home, `${viewport.width}px`).toHaveCount(1);
			// Visible AND named: an aria-hidden panel once left this link in the
			// tab order with no name.
			await expect(home).toHaveAccessibleName('Threkir');
		}
	});

	test('/login: the card\'s kicker reads once, not once per half', async ({ page }) => {
		// The panel used to repeat the card's own kicker, so "Welcome back"
		// sat on the screen twice at desktop width.
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/login');
		await expect(page.getByText('Welcome back', { exact: true })).toHaveCount(1);
	});

	test('the contour texture behind the form never takes a click', async ({ page }) => {
		// It covers the whole form side, fields included.
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/login');
		const email = page.getByPlaceholder('Email address');
		await email.click();
		await expect(email).toBeFocused();
	});

	// The terrain sits in flow AFTER the panel copy, so in any language and at
	// any height the words stop before the picture starts. A short laptop
	// screen is where an absolutely positioned picture would have crept up
	// under the bullets.
	for (const [width, height] of [
		[1440, 900],
		[1280, 720],
	]) {
		test(`sign-up panel copy never overlaps the art at ${width}x${height}`, async ({ page }) => {
			await page.setViewportSize({ width, height });
			await page.goto('/login?signup=1');
			await expect(page.locator('.brand-headline')).toBeVisible();
			const copy = await page.locator('.panel-copy').boundingBox();
			const art = await page.locator('.panel-art').boundingBox();
			expect(copy && art).toBeTruthy();
			expect(copy!.y + copy!.height, 'panel copy runs into the terrain art').toBeLessThanOrEqual(
				art!.y + 1,
			);
		});
	}

	test('on a phone the panel is a band the card rides over, with no sideways scroll', async ({
		page,
	}) => {
		await page.setViewportSize({ width: 390, height: 844 });
		await page.goto('/login?signup=1');
		const panel = await page.locator('aside.auth-panel').boundingBox();
		const card = await page.locator('main.auth-card').boundingBox();
		expect(panel && card).toBeTruthy();
		expect(card!.y, 'the card should overlap the band').toBeLessThan(panel!.y + panel!.height);
		await expect(page.locator('.panel-copy')).toBeHidden();
		const overflow = await page.evaluate(
			() => document.documentElement.scrollWidth - document.documentElement.clientWidth,
		);
		expect(overflow).toBeLessThanOrEqual(0);
		// Both OAuth buttons keep their label on one line inside the card, and
		// on every host. The page loads no text webfont, so a button renders in
		// whatever sans-serif the device falls back to: this machine's Noto Sans
		// fitted "Continue with Apple" + its pill at 390px while CI's Ubuntu
		// runner, rendering DejaVu Sans, wrapped it (run 35134263272). Widening
		// every glyph by DejaVu's margin makes the check mean the same thing
		// wherever it runs.
		await page.addStyleTag({ content: 'main.auth-card * { letter-spacing: 0.08em !important; }' });
		for (const name of [/Continue with Google/, /Continue with Apple/]) {
			const box = await page.getByRole('button', { name }).boundingBox();
			expect(box!.height, `${name} wrapped`).toBeLessThan(56);
		}
	});

	test('reduced motion leaves the shell finished on its first frame', async ({ page }) => {
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/login?signup=1');
		const hidden = await page
			.locator('main.auth-card, .brand-headline, .brand-bullets li, .panel-card, .panel-terrain')
			.evaluateAll((els) => els.filter((el) => Number(getComputedStyle(el).opacity) < 1).length);
		expect(hidden).toBe(0);
		// The readout's figures are where a count-up would land; under reduced
		// motion they are the markup's own text from the start.
		await expect(page.locator('.panel-card-clock')).toHaveText('24:17');
	});
});
