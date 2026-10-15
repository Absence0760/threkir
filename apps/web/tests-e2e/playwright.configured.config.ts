import { resolve } from 'node:path';

import { defineConfig, devices } from '@playwright/test';

/**
 * Dedicated Playwright config for surfaces that render only on a build with an
 * optional integration's public id set.
 *
 * Why separate from playwright.config.ts:
 *   - Every other lane builds with `PUBLIC_STRAVA_CLIENT_ID` empty, and the
 *     sharded suite pins what that build does: `clubs/strava-clubs.spec.ts`
 *     asserts "Your Strava clubs" stays inert and never asks Strava, and the
 *     integrations specs pin the unconfigured Strava card. Setting the id there
 *     would flip all of them. This lane boots a dev server of its own with a
 *     dummy id, so the configured half is observed too (followups: "Observe
 *     the configured path in a browser").
 *   - The id only has to be non-empty: nothing here reaches Strava. Every
 *     `strava-clubs` Edge Function call is answered by `mockRoute` in the
 *     spec, and the OAuth redirect the id builds is never followed.
 *   - One unsharded CI job (e2e-web-configured), same shape as the
 *     export-hub lane: signed in against the local Supabase stack, its own
 *     port, its own globalSetup.
 *
 * Its specs live under tests-e2e/configured and are excluded from the main
 * config via testIgnore, so they never run against a build without the id.
 * A future configured-only surface (another integration's public id) belongs
 * here rather than in a lane of its own.
 *
 * Local run: `pnpm test:e2e:configured` from apps/web.
 */
const HERE = import.meta.dirname;
const WEB_DIR = resolve(HERE, '..');

// :7777 is the sharded lane, :7778 live-hub, :7779 export-hub, :7780 sso,
// :7781 the built app.
const DEV_PORT = '7782';

export default defineConfig({
	testDir: './configured',

	globalSetup: './fixtures/auth.ts',

	timeout: 30_000,
	expect: { timeout: 10_000 },
	retries: process.env.CI ? 1 : 0,
	forbidOnly: !!process.env.CI,
	workers: 1,
	fullyParallel: false,
	reporter: process.env.CI ? [['github'], ['list']] : 'list',

	webServer: {
		command: `pnpm exec vite dev --port ${DEV_PORT}`,
		cwd: WEB_DIR,
		url: `http://localhost:${DEV_PORT}`,
		reuseExistingServer: !process.env.CI,
		timeout: 120_000,
		stdout: 'ignore',
		stderr: 'pipe',
		// process.env wins over the .env files, so this overrides the empty
		// `PUBLIC_STRAVA_CLIENT_ID=` every CI lane writes. Empty
		// PUBLIC_TILE_STYLE_URL + OSRM_URL force the committed
		// `.env.development` localhost dev services off, as in every lane. § 137.
		env: {
			PUBLIC_STRAVA_CLIENT_ID: 'e2e-fixture-client-id',
			PUBLIC_TILE_STYLE_URL: '',
			OSRM_URL: ''
		}
	},

	use: {
		baseURL: `http://localhost:${DEV_PORT}`,
		trace: 'on-first-retry',
		screenshot: 'only-on-failure',
		video: 'retain-on-failure',
		locale: 'en-GB',
		timezoneId: 'UTC'
	},

	projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }]
});
