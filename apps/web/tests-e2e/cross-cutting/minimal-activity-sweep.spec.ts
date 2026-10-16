import type { Locator, Page } from '@playwright/test';

import { browserDateOf } from '../fixtures/dates';
import { degenerateStrings } from '../fixtures/degenerate-text';
import { acceptCookieConsent } from '../fixtures/helpers';
import { seedMinimalActivity, type MinimalActivity } from '../fixtures/minimal-activity';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { expect, test } from '../fixtures/test';

/**
 * Every authenticated surface that derives something from activity, visited
 * by an account whose only activity is the least it can be (#1161 round 3):
 * a 3 m / 10 s run, a 0 m run with a single fix, a one-set gym session and a
 * 2-point route (`fixtures/minimal-activity.ts`).
 *
 * #1155 was exactly this shape: a new account's first short run rounded the
 * training-load axis onto a duplicate keyed-each key and `/dashboard` rendered
 * "500 Internal Error" in prod, while every spec seeded with a realistic run
 * stayed green. Each page here must
 *
 * - pass the crash net (`fixtures/test.ts`), and
 * - print no NaN, infinity or negative zero, by the same pattern the mobile
 *   sweep uses (`fixtures/degenerate-text.ts`), in its text, its accessible
 *   names and tooltips, or a style / SVG geometry attribute (the 0 m run's
 *   mileage bar was `height: NaN%`).
 *
 * The table is enumerated from `src/routes`: a route belongs in it when its
 * page reads runs, gym sessions or routes and derives something from them.
 * Adding one is one line.
 *
 * A page that lands on its not-found or load-error branch, or is still on a
 * skeleton, prints only nav text and would pass both scans. So every row waits
 * for the signed-in shell's main region with no `*-load-error` alert in it, and
 * a row that names one seeded item also waits for the element only its
 * success branch draws.
 */

interface SweepRoute {
	name: string;
	path: (s: MinimalActivity, user: SagaUser) => string;
	ready?: (page: Page, s: MinimalActivity) => Locator;
}

const runHeading = (page: Page) => page.locator('.detail-header h1');

const day = (s: MinimalActivity) => browserDateOf(s.tinyRun.startedAt);
const year = (s: MinimalActivity) => day(s).slice(0, 4);
const month = (s: MinimalActivity) => String(Number(day(s).slice(5, 7)));

const ROUTES: readonly SweepRoute[] = [
	{ name: 'dashboard', path: () => '/dashboard' },
	{ name: 'dashboard week', path: (s) => `/dashboard/period/week/${day(s)}` },
	{ name: 'dashboard month', path: (s) => `/dashboard/period/month/${day(s)}` },
	{ name: 'dashboard all time', path: (s) => `/dashboard/period/all/${day(s)}` },
	{ name: 'history', path: () => '/history' },
	{ name: 'runs list', path: () => '/runs' },
	{ name: 'runs heatmap', path: () => '/runs/heatmap' },
	{ name: 'run detail, 3 m in 10 s', path: (s) => `/runs/${s.tinyRun.id}`, ready: runHeading },
	{ name: 'run detail, 0 m with one fix', path: (s) => `/runs/${s.zeroRun.id}`, ready: runHeading },
	{ name: 'recap year', path: (s) => `/recap/${year(s)}` },
	{ name: 'recap month', path: (s) => `/recap/${year(s)}/${month(s)}` },
	{ name: 'plans', path: () => '/plans' },
	{ name: 'new plan', path: () => '/plans/new' },
	{ name: 'coach', path: () => '/coach' },
	{ name: 'races', path: () => '/races' },
	{ name: 'routes list', path: () => '/routes' },
	{
		name: 'route detail, 2 points',
		path: (s) => `/routes/${s.routeId}`,
		ready: (page, s) => page.getByRole('heading', { level: 1, name: s.routeName, exact: true })
	},
	{
		name: 'route roadbook, 2 points',
		path: (s) => `/routes/${s.routeId}/roadbook`,
		ready: (page, s) => page.locator('.rb-header').getByRole('link', { name: s.routeName })
	},
	{ name: 'gym', path: () => '/gym' },
	{
		name: 'gym session, one set',
		path: (s) => `/gym/${s.gymWorkoutId}`,
		ready: (page, s) => page.getByRole('heading', { level: 1, name: s.gymTitle, exact: true })
	},
	{ name: 'gym records', path: () => '/gym/records' },
	{ name: 'gym exercise', path: (s) => `/gym/exercise?name=${encodeURIComponent(s.exerciseName)}` },
	{ name: 'gym routines', path: () => '/gym/routines' },
	{ name: 'nutrition', path: () => '/nutrition' },
	{ name: 'nutrition targets', path: () => '/nutrition/targets' },
	{ name: 'challenges', path: () => '/challenges' },
	{ name: 'own profile', path: (_, user) => `/u/${user.id}` },
	{ name: 'training settings', path: () => '/settings/training' },
	{ name: 'gear settings', path: () => '/settings/gear' }
];

/**
 * What the page paints or announces, plus every style and SVG geometry
 * attribute: the strings a NaN or a negative zero can reach a reader through,
 * and the attributes a NaN reaches a chart through.
 */
async function renderedStrings(page: Page): Promise<{ text: string[]; geometry: string[] }> {
	return page.evaluate(() => {
		const text: string[] = document.body.innerText
			.split('\n')
			.map((l) => l.trim())
			.filter((l) => l.length > 0);
		for (const el of Array.from(document.querySelectorAll('svg text'))) {
			const t = el.textContent?.trim();
			if (t) text.push(t);
		}
		for (const el of Array.from(document.querySelectorAll('[aria-label], [title], [alt]'))) {
			for (const attr of ['aria-label', 'title', 'alt']) {
				const v = el.getAttribute(attr)?.trim();
				if (v) text.push(v);
			}
		}
		for (const el of Array.from(document.querySelectorAll('input, textarea'))) {
			const v = (el as HTMLInputElement).value.trim();
			if (v) text.push(v);
		}
		const geometryAttrs = [
			'style', 'd', 'points', 'transform', 'x', 'y', 'x1', 'x2', 'y1', 'y2',
			'cx', 'cy', 'r', 'width', 'height', 'viewBox'
		];
		const geometry: string[] = [];
		for (const el of Array.from(document.querySelectorAll('[style], svg, svg *'))) {
			for (const attr of geometryAttrs) {
				const v = el.getAttribute(attr);
				if (v && /NaN|Infinity/.test(v)) {
					geometry.push(`<${el.tagName.toLowerCase()} ${attr}="${v.slice(0, 200)}">`);
				}
			}
		}
		return { text, geometry };
	});
}

test.describe('an account with minimal activity', () => {
	test.describe.configure({ timeout: 60_000 });

	let user: SagaUser;
	let seeded: MinimalActivity;

	test.beforeAll(async () => {
		[user] = await createSagaUsers(1, { displayNames: ['Minimal Activity Runner'] });
		seeded = await seedMinimalActivity(user);
	});

	test.afterAll(async () => {
		if (seeded) await seeded.cleanup();
		if (user) await deleteSagaUsers([user]);
	});

	for (const route of ROUTES) {
		test(`${route.name} renders without a crash or a broken number`, async ({ browser }) => {
			const path = route.path(seeded, user);
			const ctx = await browser.newContext({ storageState: user.storageStatePath });
			await acceptCookieConsent(ctx);
			const page = await ctx.newPage();

			try {
				await page.goto(path);
				await page.waitForLoadState('networkidle');

				const landed = new URL(page.url()).pathname;
				expect(landed, `${path} sent the signed-in account away`).not.toMatch(
					/^\/(login|onboarding)\b/
				);
				await expect(page.getByText('Internal Error', { exact: true })).toHaveCount(0);
				await expect(page.locator('#main-content')).toBeVisible();
				await expect(page.locator('[data-testid$="load-error"]')).toHaveCount(0);
				if (route.ready) {
					await expect(
						route.ready(page, seeded),
						`${path} never drew its seeded item, so it is on a not-found, error or loading branch`
					).toBeVisible();
				}

				const { text, geometry } = await renderedStrings(page);
				expect(text, `${path} rendered no text, so the sweep proved nothing`).not.toEqual([]);
				expect(degenerateStrings(text), `${path} printed a NaN, infinity or negative zero`).toEqual(
					[]
				);
				expect(geometry, `${path} drew with a NaN or infinite attribute`).toEqual([]);
			} finally {
				await ctx.close();
			}
		});
	}
});
