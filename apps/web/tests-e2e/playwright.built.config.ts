import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

/**
 * Dedicated Playwright config for the BUILT app with error reporting on.
 *
 * Why separate from playwright.config.ts: every other lane runs `vite dev`,
 * and `hooks.client.ts` initialises Sentry only when `!dev &&
 * PUBLIC_SENTRY_DSN && hasAcceptedConsent()` — so no lane had ever run the
 * consented path. That is how web@1.12.0 shipped a client that threw
 * `svelte.dev/e/kit/app_stores_removed` at hydration and stayed blank for
 * every reader who accepted error reporting (decisions § 1896). This lane
 * production-builds the app with a dummy DSN and serves the output the way
 * CloudFront does (scripts/serve-build.mjs), so the one condition the bug
 * needed is the one condition every test here runs under.
 *
 * No Supabase, no globalSetup: the pages it loads are anonymous, and the
 * spec routes every request off this origin away so nothing leaves the
 * runner — Sentry's ingest included. The Supabase URL below is loopback for
 * the same reason; nothing is listening on it and nothing needs to be.
 *
 * The build is part of the webServer command rather than a CI step so the
 * lane is one command locally too: `pnpm test:e2e:built` from apps/web. It
 * writes `apps/web/build`, the same directory `pnpm build` does.
 */
const HERE = import.meta.dirname;
const WEB_DIR = resolve(HERE, '..');

// :7777 is the sharded lane, :7778 live-hub, :7779 export-hub, :7780 sso.
const DEV_PORT = '7781';
const BASE_URL = `http://127.0.0.1:${DEV_PORT}`;

/** Well-formed, and never reached: the spec answers every sentry.io request itself. */
const DUMMY_SENTRY_DSN = 'https://public@o0.ingest.sentry.io/0';

export default defineConfig({
	testDir: './built',

	timeout: 30_000,
	expect: { timeout: 10_000 },
	retries: process.env.CI ? 1 : 0,
	forbidOnly: !!process.env.CI,
	workers: 1,
	fullyParallel: false,
	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	webServer: {
		command: `pnpm exec vite build && node tests-e2e/scripts/serve-build.mjs ${DEV_PORT}`,
		cwd: WEB_DIR,
		url: BASE_URL,
		reuseExistingServer: !process.env.CI,
		// A cold production build is ~70 s on the hosted runner (build-web).
		timeout: 300_000,
		// process.env wins over apps/web/.env* for both vite and SvelteKit, so
		// these hold locally as well as on CI. The two Supabase keys are static
		// and required by src/env.ts; the DSN is dynamic and lands in
		// `_app/env.js`, exactly where release-web.yml's build puts the real one.
		env: {
			PUBLIC_SUPABASE_URL: 'http://127.0.0.1:24321',
			PUBLIC_SUPABASE_ANON_KEY: 'e2e-built-placeholder-anon-key',
			PUBLIC_SENTRY_DSN: DUMMY_SENTRY_DSN,
			PUBLIC_MAPTILER_KEY: '',
			PUBLIC_TILE_STYLE_URL: '',
			BASE_PATH: ''
		},
		stdout: 'ignore',
		stderr: 'pipe'
	},

	use: {
		baseURL: BASE_URL,
		trace: 'on-first-retry',
		screenshot: 'only-on-failure',
		video: 'retain-on-failure',
		locale: 'en-GB',
		timezoneId: 'UTC',
		// The built app ships a service worker (static/sw.js, registered for
		// push), and a request a worker makes is not one `context.route`
		// sees. Blocking it keeps every request on the path the spec routes.
		serviceWorkers: 'block'
	},

	projects: [
		{
			name: 'chromium',
			use: { ...devices['Desktop Chrome'] }
		}
	]
});
