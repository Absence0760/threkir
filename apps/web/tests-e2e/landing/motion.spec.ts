import { expect, test, type Page } from '@playwright/test';

/**
 * `/` — the landing page's motion contract (conventions.md § Motion).
 *
 *   1. The resting state is the markup's own: reduced motion, or motion that
 *      has finished, leaves every word and section visible.
 *   2. Only code that can reveal an element hides it, and every reveal lands.
 *   3. Motion that starts on its own and runs past five seconds has an
 *      in-page stop (WCAG 2.2.2), and that stop reaches all of it.
 *   4. No copy is ever set on the rendered art, so every ink stays measured
 *      against the ramp the contrast guards read.
 */

async function runningInfinite(page: Page): Promise<number> {
	return page.evaluate(
		() =>
			document
				.getAnimations()
				.filter(
					(a) =>
						a.playState === 'running' &&
						a.effect?.getTiming().iterations === Infinity &&
						(a.effect as KeyframeEffect).target?.closest?.('.motion-scope'),
				).length,
	);
}

async function scrollThrough(page: Page) {
	await page.evaluate(async () => {
		for (let y = 0; y < document.body.scrollHeight; y += 300) {
			window.scrollTo(0, y);
			await new Promise((r) => setTimeout(r, 80));
		}
	});
}

test.describe('/ (landing) motion', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	test('every revealed section settles fully opaque', async ({ page }) => {
		await page.goto('/');
		await scrollThrough(page);
		await page.waitForTimeout(1500);
		const unsettled = await page
			.locator('section#features article.feature, section#features .section-head, section#apps li.platform, section.closing-cta .closing-copy')
			.evaluateAll((els) =>
				els
					.filter((el) => getComputedStyle(el).opacity !== '1' || (el as HTMLElement).style.opacity !== '')
					.map((el) => el.className),
			);
		expect(unsettled, 'a revealed element was left transparent').toEqual([]);
	});

	test('reduced motion: nothing is hidden and nothing loops', async ({ page }) => {
		await page.emulateMedia({ reducedMotion: 'reduce' });
		await page.goto('/');
		// The staggered headline words carry delays; the global reduced-motion
		// rule has to zero those as well as the durations.
		const hidden = await page
			.locator('.enter, section#features article.feature, section#apps li.platform')
			.evaluateAll((els) =>
				els.filter((el) => Number(getComputedStyle(el).opacity) < 1).length,
			);
		expect(hidden, 'content invisible under reduced motion').toBe(0);
		expect(await runningInfinite(page), 'a loop still runs under reduced motion').toBe(0);
		// Nothing moves, so there is nothing to pause.
		await expect(page.getByRole('button', { name: 'Pause animations' })).toHaveCount(0);
	});

	test('the pause control stops every looping animation, and resumes them', async ({ page }) => {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/');
		const toggle = page.getByRole('button', { name: 'Pause animations' });
		// Disabled until hydrated, so a click cannot land on a dead button.
		await expect(toggle).toBeEnabled();
		await expect(toggle).toHaveAttribute('aria-pressed', 'false');
		expect(await runningInfinite(page), 'the page has no loops to pause').toBeGreaterThan(0);

		// The phone's recording clock is script-driven, not CSS, so the store
		// has to reach it too. It only runs while on screen, so bring it into
		// view and prove it runs before proving that it stops.
		const clock = page.locator('figure.shot .elapsed');
		await clock.scrollIntoViewIfNeeded();
		const start = await clock.textContent();
		await expect(clock, 'the clock does not run at all').not.toHaveText(start ?? '', {
			timeout: 4000,
		});

		await toggle.click();
		await expect(toggle).toHaveAttribute('aria-pressed', 'true');
		await expect(page.locator('html')).toHaveAttribute('data-motion', 'paused');
		expect(await runningInfinite(page), 'a loop kept running while paused').toBe(0);
		const paused = await clock.textContent();
		await page.waitForTimeout(2300);
		expect(await clock.textContent(), 'the clock ticked while paused').toBe(paused);

		await toggle.click();
		await expect(toggle).toHaveAttribute('aria-pressed', 'false');
		await expect(page.locator('html')).not.toHaveAttribute('data-motion', 'paused');
		expect(await runningInfinite(page)).toBeGreaterThan(0);
		await expect(clock).not.toHaveText(paused ?? '', { timeout: 4000 });
	});

	test('pausing before scrolling means sections arrive at rest, not animating in', async ({
		page,
	}) => {
		// The reveals are one-shot, but "Pause animations" should mean nothing
		// starts moving — so a reveal checks the pause when it would begin, not
		// only when it was mounted.
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/');
		const toggle = page.getByRole('button', { name: 'Pause animations' });
		await expect(toggle).toBeEnabled();
		await toggle.click();
		await expect(toggle).toHaveAttribute('aria-pressed', 'true');
		await scrollThrough(page);
		const started = await page.evaluate(
			() =>
				document
					.getAnimations()
					.filter((a) => {
						const target = (a.effect as KeyframeEffect).target;
						// Time-based, one-shot animations only: the rail and step
						// nodes run on a scroll timeline, which the reader drives.
						return (
							!!target?.closest?.('section#features, section#apps, section.closing-cta') &&
							a.timeline === document.timeline &&
							a.effect?.getTiming().iterations !== Infinity
						);
					}).length,
		);
		expect(started, 'a reveal animated while paused').toBe(0);
		const hidden = await page
			.locator('section#features article.feature, section#apps li.platform')
			.evaluateAll((els) => els.filter((el) => getComputedStyle(el).opacity !== '1').length);
		expect(hidden).toBe(0);
	});

	test('the pause control stays on the landing page, not on /learn', async ({ page }) => {
		await page.goto('/learn');
		await expect(page.getByRole('button', { name: 'Pause animations' })).toHaveCount(0);
	});

	for (const width of [1440, 390]) {
		test(`no copy sits on the rendered terrain at ${width}px`, async ({ page }) => {
			await page.setViewportSize({ width, height: 900 });
			await page.goto('/');
			const art = page.locator('.hero .terrain img');
			await expect(art).toHaveAttribute('alt', '');
			await expect
				.poll(() => art.evaluate((img: HTMLImageElement) => img.naturalWidth))
				.toBeGreaterThan(0);
			const actions = await page.locator('.hero-actions').boundingBox();
			const terrain = await page.locator('.hero .terrain').boundingBox();
			expect(actions && terrain).toBeTruthy();
			expect(
				actions!.y + actions!.height,
				'the hero buttons overlap the terrain art',
			).toBeLessThanOrEqual(terrain!.y + 1);
		});
	}

	test('the features section is headed, so the outline does not skip a level', async ({ page }) => {
		await page.goto('/');
		const levels = await page
			.locator('main.hero h1, section#features h2, section#features h3')
			.evaluateAll((els) => els.map((el) => Number(el.tagName.slice(1))));
		expect(levels.slice(0, 3)).toEqual([1, 2, 3]);
	});

	test('the page never scrolls sideways at 390px', async ({ page }) => {
		await page.setViewportSize({ width: 390, height: 844 });
		await page.goto('/');
		await scrollThrough(page);
		const overflow = await page.evaluate(
			() => document.documentElement.scrollWidth - document.documentElement.clientWidth,
		);
		expect(overflow, 'horizontal overflow in px').toBeLessThanOrEqual(0);
	});
});
