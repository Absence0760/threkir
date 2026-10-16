import type { Page } from '@playwright/test';
import { expect, test } from '../fixtures/test';

/**
 * `/` — the landing page's motion contract (conventions.md § Motion).
 *
 *   1. The resting state is the markup's own: reduced motion, or motion that
 *      has finished, leaves every word and section visible.
 *   2. Only code that can reveal an element hides it, and every reveal lands.
 *   3. Every animation settles within five seconds of starting, so WCAG
 *      2.2.2 asks for no pause control and the page carries none
 *      (decisions § 1907).
 *   4. No copy is ever set on the rendered art, so every ink stays measured
 *      against the ramp the contrast guards read.
 */

/// Every clock-driven animation on the page that is still running, as
/// `target: end-time-ms`. Scroll- and view-linked ones are driven by the
/// reader, so they are left out.
async function runningTimed(page: Page): Promise<Array<{ target: string; endMs: number }>> {
	return page.evaluate(() =>
		document
			.getAnimations()
			.filter((a) => {
				const target = (a.effect as KeyframeEffect | null)?.target;
				return (
					a.playState === 'running' &&
					a.timeline === document.timeline &&
					!!target?.closest?.('.landing')
				);
			})
			.map((a) => {
				const timing = a.effect!.getComputedTiming();
				const target = (a.effect as KeyframeEffect).target as Element;
				return {
					target: `${target.tagName.toLowerCase()}.${target.getAttribute('class') ?? ''}`,
					endMs: Number(timing.endTime),
				};
			}),
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
		const loops = (await runningTimed(page)).filter((a) => a.endMs === Infinity);
		expect(loops, 'a loop runs under reduced motion').toEqual([]);
	});

	test('every animation settles within five seconds of starting, and then nothing runs', async ({
		page,
	}) => {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/');
		const tooLong = new Set<string>();
		const sample = async () => {
			const running = await runningTimed(page);
			for (const a of running) if (a.endMs > 5000) tooLong.add(`${a.target}: ${a.endMs}ms`);
			return running;
		};
		expect((await sample()).length, 'the hero runs no motion at all').toBeGreaterThan(0);
		await scrollThrough(page);
		// Sampled until the page is still, so an animation that only starts
		// after hydration (the shot's runner) is read too. The bound is the
		// assertion; the wait only has to outlast the latest start.
		await expect
			.poll(async () => (await sample()).map((a) => a.target), { timeout: 12_000 })
			.toEqual([]);
		expect([...tooLong], 'an animation runs past five seconds of starting').toEqual([]);
	});

	test('the phone clock ticks, then holds inside five seconds', async ({ page }) => {
		await page.setViewportSize({ width: 1440, height: 900 });
		await page.goto('/');
		const clock = page.locator('figure.shot .elapsed');
		await clock.scrollIntoViewIfNeeded();
		const start = await clock.textContent();
		// Generous: the ticker starts at hydration, which a cold dev server
		// can take seconds to reach. What is under test is that it stops.
		await expect(clock, 'the clock does not run at all').not.toHaveText(start ?? '', {
			timeout: 10_000,
		});
		await page.waitForTimeout(5000);
		const held = await clock.textContent();
		await page.waitForTimeout(2000);
		expect(await clock.textContent(), 'the clock is still ticking').toBe(held);
	});

	test('the public header carries no pause control', async ({ page }) => {
		await page.goto('/');
		await expect(page.locator('nav.landing-nav button')).toHaveCount(0);
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
