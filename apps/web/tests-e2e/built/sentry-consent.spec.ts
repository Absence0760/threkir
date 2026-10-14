import { expect, test, type Page } from '@playwright/test';

import { originOf } from '../fixtures/base-url';

/**
 * Accepting error reporting must leave the app rendering (decisions § 1896).
 *
 * web@1.12.0 resolved @sentry/sveltekit's Svelte 4 tracing variant, which
 * subscribes to `$app/stores` — on Kit 3 a stub that throws. The throw only
 * happens once `Sentry.init` runs, and `hooks.client.ts` runs it only in a
 * production build with a DSN and accepted consent, so every reader who
 * accepted got `svelte.dev/e/kit/app_stores_removed` at hydration and a blank
 * page, while every e2e lane (vite dev, no DSN) stayed green.
 *
 * These run against playwright.built.config.ts: a production build with a
 * dummy DSN, served the way CloudFront serves it. Every request off this
 * origin is answered here — Sentry's ingest with an empty 200, everything
 * else aborted — so nothing leaves the runner.
 *
 * Each test also proves Sentry actually initialised, by seeing it send. A
 * green run that never reached `Sentry.init` (consent stored under a key the
 * client no longer reads, a DSN the build dropped) would say nothing about
 * the bug, so that case fails instead of passing.
 */

// The key and shape `consent.set('accepted')` writes
// (src/lib/settings/consent.svelte.ts), and the only thing
// `hasAcceptedConsent()` reads.
const CONSENT_KEY = 'cookie_consent';

interface Observed {
	pageErrors: string[];
	kitErrors: string[];
	sentryRequests: string[];
}

function isSentryHost(hostname: string): boolean {
	return hostname === 'sentry.io' || hostname.endsWith('.sentry.io');
}

async function isolate(page: Page, origin: string, seen: Observed): Promise<void> {
	await page.route('**/*', async (route) => {
		const url = new URL(route.request().url());
		if (url.origin === origin) return route.continue();
		if (isSentryHost(url.hostname)) {
			seen.sentryRequests.push(url.pathname);
			return route.fulfill({ status: 200, contentType: 'application/json', body: '{}' });
		}
		return route.abort('blockedbyclient');
	});
}

function observe(page: Page, seen: Observed): void {
	page.on('pageerror', (error) => seen.pageErrors.push(error.stack ?? error.message));
	page.on('console', (message) => {
		if (message.type() === 'error' && message.text().includes('svelte.dev/e/kit')) {
			seen.kitErrors.push(message.text());
		}
	});
}

function fresh(): Observed {
	return { pageErrors: [], kitErrors: [], sentryRequests: [] };
}

/**
 * Sentry's session envelope goes out at init; a thrown probe error is the
 * fallback, so the check does not depend on session tracking staying on.
 * Called only after the error assertions, so the probe's own throw is never
 * mistaken for the app's.
 */
async function expectSentryInitialised(page: Page, seen: Observed): Promise<void> {
	if (seen.sentryRequests.length === 0) {
		await page.evaluate(() => {
			setTimeout(() => {
				throw new Error('e2e-built: Sentry init probe');
			});
		});
	}
	await expect
		.poll(() => seen.sentryRequests.length, {
			message:
				'Sentry never sent anything, so Sentry.init did not run and this test proved nothing ' +
				'about the consented path — check the consent key and that the build carries the DSN.'
		})
		.toBeGreaterThan(0);
}

function expectNoHydrationErrors(seen: Observed, path: string): void {
	expect(seen.kitErrors, `${path}: a removed SvelteKit API threw`).toEqual([]);
	expect(seen.pageErrors, `${path}: uncaught error on the page`).toEqual([]);
}

test.describe('built app with error reporting accepted', () => {
	test('the landing page, /help and /login render with Sentry initialised', async ({
		context,
		baseURL
	}) => {
		const origin = originOf(baseURL);
		await context.addInitScript(
			([key, value]) => localStorage.setItem(key, value),
			[CONSENT_KEY, JSON.stringify({ choice: 'accepted', timestamp: Date.now() })] as const
		);

		// `/` is prerendered, so its heading is in the HTML whether or not the
		// client starts; the uncaught-error check is what fails there. /help and
		// /login are the SPA shell, which renders nothing until hydration — a
		// throw leaves them blank and the heading never appears.
		for (const [path, heading] of [
			['/', null],
			['/help', 'Help'],
			['/login', null]
		] as const) {
			const page = await context.newPage();
			const seen = fresh();
			await isolate(page, origin, seen);
			observe(page, seen);

			await page.goto(path);
			await expect(page.getByRole('main').first()).toBeVisible();
			await expect(
				page.getByRole('heading', heading ? { level: 1, name: heading } : { level: 1 }).first()
			).toBeVisible();

			await expectSentryInitialised(page, seen);
			expectNoHydrationErrors(seen, path);
			await page.close();
		}
	});

	test('accepting through the consent banner reloads into a page that still renders', async ({
		page,
		baseURL
	}) => {
		const seen = fresh();
		await isolate(page, originOf(baseURL), seen);
		observe(page, seen);

		await page.goto('/login');
		await expect(page.getByRole('heading', { level: 1 }).first()).toBeVisible();
		const banner = page.getByRole('dialog', { name: 'Cookies + error monitoring' });
		await expect(banner).toBeVisible();
		expect(seen.sentryRequests, 'Sentry sent before consent was given').toEqual([]);

		// accept() stores the choice and reloads the page itself.
		const reloaded = page.waitForEvent('load');
		await banner.getByRole('button', { name: 'Accept', exact: true }).click();
		await reloaded;

		expect(
			await page.evaluate((key) => JSON.parse(localStorage.getItem(key) ?? 'null')?.choice, CONSENT_KEY)
		).toBe('accepted');
		await expect(page.getByRole('main').first()).toBeVisible();
		await expect(page.getByRole('heading', { level: 1 }).first()).toBeVisible();
		await expect(banner).toHaveCount(0);

		await expectSentryInitialised(page, seen);
		expectNoHydrationErrors(seen, '/login after accepting');
	});
});
