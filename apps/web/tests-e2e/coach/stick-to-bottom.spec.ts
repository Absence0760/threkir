import type { Locator, Page } from '@playwright/test';

import { expect, test } from '../fixtures/test';
import { USER_A } from '../fixtures/users';

/**
 * A streaming coach reply follows the reader down only while they are at
 * the bottom of the chat. Issue #1214: every token pinned the log to the
 * bottom, so scrolling up to read the start of a long answer was undone
 * by the next token.
 *
 * `route.fulfill` hands the client the whole SSE body at once, which can't
 * leave a stream open while the test scrolls. The page's `fetch` is
 * wrapped instead, so `/api/coach` answers with a ReadableStream the test
 * feeds one token at a time.
 */

const STICK_THRESHOLD_PX = 48;

async function installControllableStream(page: Page) {
	await page.evaluate(() => {
		const w = window as unknown as {
			__coachToken: (text: string) => void;
			__coachEnd: () => void;
		};
		const encoder = new TextEncoder();
		let controller: ReadableStreamDefaultController<Uint8Array> | null = null;
		const send = (event: string, data: unknown) =>
			controller?.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
		w.__coachToken = (text) => send('token', { text });
		w.__coachEnd = () => {
			send('done', { assistant_message_id: null });
			controller?.close();
		};
		const realFetch = window.fetch.bind(window);
		window.fetch = (input, init) => {
			const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
			if (!url.endsWith('/api/coach')) return realFetch(input, init);
			const body = new ReadableStream<Uint8Array>({
				start(c) {
					controller = c;
					send('meta', { tier: 'pro', limits: { daily_limit: 20 } });
				}
			});
			return Promise.resolve(
				new Response(body, { status: 200, headers: { 'content-type': 'text/event-stream' } })
			);
		};
	});
}

async function streamParagraphs(page: Page, from: number, to: number) {
	await page.evaluate(
		([a, b]) => {
			const w = window as unknown as { __coachToken: (text: string) => void };
			for (let i = a; i <= b; i++) w.__coachToken(`Paragraph ${i} of the coach reply.\n\n`);
		},
		[from, to]
	);
	await expect(page.locator('.bubble', { hasText: `Paragraph ${to} of` })).toBeVisible();
}

function distanceFromBottom(log: Locator) {
	return log.evaluate((el) => el.scrollHeight - el.scrollTop - el.clientHeight);
}

test.describe('/coach — stick to bottom while a reply streams', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('scrolling up holds position mid-stream; Jump to latest resumes following', async ({
		page
	}) => {
		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await installControllableStream(page);

		await composer.fill('e2e stick to bottom');
		await page.locator('form.composer button[type="submit"]').click();

		const log = page.locator('.scroll[role="log"]');
		const jump = page.getByRole('button', { name: 'Jump to latest' });

		// Following: a reply taller than the log keeps the newest text in view.
		await streamParagraphs(page, 1, 40);
		await expect.poll(() => distanceFromBottom(log)).toBeLessThanOrEqual(STICK_THRESHOLD_PX);
		await expect(jump).toBeHidden();

		// The reader scrolls up to the start of the reply.
		await log.hover();
		await page.mouse.wheel(0, -100_000);
		await expect.poll(() => log.evaluate((el) => el.scrollTop)).toBe(0);

		// More tokens arrive: the position holds and the jump button appears.
		await streamParagraphs(page, 41, 60);
		expect(await log.evaluate((el) => el.scrollTop)).toBe(0);
		await expect(jump).toBeVisible();

		// The jump button returns to the newest text and hides itself.
		await jump.click();
		await expect.poll(() => distanceFromBottom(log)).toBeLessThanOrEqual(STICK_THRESHOLD_PX);
		await expect(jump).toBeHidden();

		// Following is back on: the next tokens keep the bottom in view.
		await streamParagraphs(page, 61, 80);
		await expect.poll(() => distanceFromBottom(log)).toBeLessThanOrEqual(STICK_THRESHOLD_PX);

		await page.evaluate(() => (window as unknown as { __coachEnd: () => void }).__coachEnd());
	});

	test('sending a new message scrolls to the bottom even after the reader scrolled up', async ({
		page
	}) => {
		await page.goto('/coach');
		const composer = page.getByPlaceholder(/Ask about today/);
		await expect(composer).toBeVisible({ timeout: 10_000 });
		await installControllableStream(page);

		await composer.fill('e2e first turn');
		await page.locator('form.composer button[type="submit"]').click();
		const log = page.locator('.scroll[role="log"]');
		await streamParagraphs(page, 1, 40);
		await page.evaluate(() => (window as unknown as { __coachEnd: () => void }).__coachEnd());
		await expect(page.locator('form.composer button[type="submit"]')).not.toHaveText('…');

		await log.hover();
		await page.mouse.wheel(0, -100_000);
		await expect.poll(() => log.evaluate((el) => el.scrollTop)).toBe(0);

		await installControllableStream(page);
		await composer.fill('e2e second turn');
		await page.locator('form.composer button[type="submit"]').click();
		await expect(page.locator('.bubble', { hasText: 'e2e second turn' })).toBeVisible();
		await expect.poll(() => distanceFromBottom(log)).toBeLessThanOrEqual(STICK_THRESHOLD_PX);
		await expect(page.getByRole('button', { name: 'Jump to latest' })).toBeHidden();

		await page.evaluate(() => (window as unknown as { __coachEnd: () => void }).__coachEnd());
	});
});
