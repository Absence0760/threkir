import type { Page } from '@playwright/test';

import { CLIENT_ERROR_LOG_PREFIX } from '../../src/lib/core/client_error_log';
import { expect, test } from '../fixtures/test';

/**
 * The crash net's own proof (fixtures/test.ts). A net nobody has seen catch
 * anything is not a net, so every case here pins `mode: 'fail'` — these must
 * bite even in a run that sets `CRASH_NET=report`.
 *
 * Two shapes. `test.fail()` proves an unexcused crash turns the test red; its
 * body cannot fail on its own (no navigation, no wait that can time out), so
 * the only way it goes red is the net. The `allow` cases prove each detector
 * fires: an allow entry that excuses nothing fails the test as stale, so each
 * of those passes only if the crash it names was actually recorded.
 */

const PROBE = 'crash-net probe';

/** Throws from a timer, so it is uncaught, and resolves only after the throw. */
function throwUncaught(page: Page, message: string): Promise<void> {
	return page.evaluate(
		(m) =>
			new Promise<void>((resolve) => {
				setTimeout(() => {
					setTimeout(resolve);
					throw new Error(m);
				});
			}),
		message
	);
}

test.use({ storageState: { cookies: [], origins: [] }, crashNet: { mode: 'fail' } });

test('an uncaught exception fails the test', async ({ page }) => {
	test.fail();
	await throwUncaught(page, PROBE);
});

// Asks for `browser` alone, the shape of most saga specs. Fixtures are lazy,
// so this goes red only while the net arms itself without being asked for.
test('a test that never asks for page or context is still watched', async ({ browser }) => {
	test.fail();
	const context = await browser.newContext();
	try {
		await throwUncaught(await context.newPage(), PROBE);
	} finally {
		await context.close();
	}
});

test.describe('each detector records its crash', () => {
	test.describe('pageerror', () => {
		test.use({ crashNet: { mode: 'fail', allow: [{ match: PROBE, reason: 'thrown by this case' }] } });
		test('an uncaught exception is recorded', async ({ page }) => {
			await throwUncaught(page, PROBE);
		});
	});

	test.describe('Svelte runtime code', () => {
		test.use({
			crashNet: { mode: 'fail', allow: [{ match: 'svelte.dev/e/each_key_duplicate', reason: 'logged by this case' }] }
		});
		test('an error-level console line with a svelte.dev/e/ code is recorded', async ({ page }) => {
			await page.evaluate(() => console.error('https://svelte.dev/e/each_key_duplicate'));
		});
	});

	test.describe('client handleError log', () => {
		test.use({
			crashNet: { mode: 'fail', allow: [{ match: CLIENT_ERROR_LOG_PREFIX, reason: 'logged by this case' }] }
		});
		test('the hook log line is recorded', async ({ page }) => {
			await page.evaluate((p) => console.error(p, '500 Internal Error on /x'), CLIENT_ERROR_LOG_PREFIX);
		});
	});

	test.describe('error boundary in the DOM', () => {
		test.use({ crashNet: { mode: 'fail', allow: [{ match: 'error boundary rendered', reason: 'drawn by this case' }] } });
		test("SvelteKit's 500 page appearing is recorded", async ({ page }) => {
			await page.goto('/login');
			await page.evaluate(() => {
				document.body.innerHTML = '<h1>500</h1><p>Internal Error</p>';
			});
			await expect(page.getByText('Internal Error', { exact: true })).toBeVisible();
		});
	});

	test.describe('a context the test makes itself', () => {
		test.use({ crashNet: { mode: 'fail', allow: [{ match: PROBE, reason: 'thrown by this case' }] } });
		test('browser.newContext pages are watched too', async ({ browser }) => {
			const context = await browser.newContext();
			try {
				await throwUncaught(await context.newPage(), PROBE);
			} finally {
				await context.close();
			}
		});
	});
});

test('an ordinary console error and a 404 page are not crashes', async ({ page }) => {
	await page.evaluate(() => console.error('Failed to load resource: 404'));
	await page.goto('/login');
	await page.evaluate(() => {
		document.body.innerHTML = '<h1>404</h1><p>Not Found</p>';
	});
	await expect(page.getByText('Not Found', { exact: true })).toBeVisible();
});

test.describe('report mode', () => {
	test.use({
		crashNet: { mode: 'report', allow: [{ match: 'excuses nothing here', reason: 'proves a stale entry only reports' }] }
	});
	test('a crash and a stale allow entry are reported without failing the test', async ({ page }) => {
		await throwUncaught(page, PROBE);
	});
});

test.describe('opting out', () => {
	test.use({ crashNet: { off: 'proves the opt-out: this case throws on purpose' } });
	test('a test with the net off may crash', async ({ page }) => {
		await throwUncaught(page, PROBE);
	});
});
