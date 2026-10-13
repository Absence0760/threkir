import type { Browser, Page } from '@playwright/test';

import { expect, test } from '../fixtures/mock-route';
import { getAdminClient } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { USER_A, USER_B, USER_C_PRO, type SeededUser } from '../fixtures/users';
import { readMaybeRow, readRow, readRows } from '../fixtures/db-read';

/**
 * Audience sharing (decisions § 1874): a run or route can be shared with
 * the owner's followers, or with named people, without becoming public.
 *
 * Seed follow graph:
 *   USER_A (runner) <-> USER_B (Alex Chen)   mutual — Alex FOLLOWS runner
 *   USER_A  -> USER_C (Morgan Lee)           Morgan does NOT follow runner
 * So Alex is in the followers level and Morgan is not, while both are people
 * runner may name (a follow edge either way).
 *
 * The seed opens the audience-sharing gate (private.feature_flags); prod
 * starts closed until the CISO sign-off, which audience_sharing_test.sql pins.
 *
 * The track planted here starts inside runner's seeded privacy zone
 * (-37.8136, 144.9631, r = 200 m) and leaves it, so a recipient reading it
 * through clip-public-track must get one point fewer than was stored — the
 * clipped-track rule (§ 33) holds for a named recipient exactly as for a
 * stranger reading a public run.
 */

const TRACK = [
	{ lat: -37.8136, lng: 144.9631, ele: 10 },
	{ lat: -37.8236, lng: 144.9731, ele: 11 },
	{ lat: -37.8336, lng: 144.9831, ele: 12 }
];

const uniqueTitle = (prefix: string) =>
	`${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;

async function openAs(browser: Browser, user: SeededUser): Promise<{ page: Page; close: () => Promise<void> }> {
	const ctx = await browser.newContext({ storageState: user.storageStatePath });
	const page = await ctx.newPage();
	return { page, close: () => ctx.close() };
}

/// Open /runs/[id] as `user` and answer whether the run rendered for them.
/// When it did, also return what clip-public-track served them.
async function viewRun(browser: Browser, user: SeededUser, runId: string, title: string) {
	const { page, close } = await openAs(browser, user);
	try {
		const clip = page
			.waitForResponse((r) => r.url().includes('/functions/v1/clip-public-track'), { timeout: 15_000 })
			.catch(() => null);
		await page.goto(`/runs/${runId}`);
		const heading = page.getByRole('heading', { name: title });
		const notFound = page.getByRole('heading', { name: 'Run not found' });
		await expect(heading.or(notFound)).toBeVisible({ timeout: 15_000 });
		if (await notFound.isVisible()) return { visible: false as const };
		await expect(page.getByTestId('run-shared-with-you')).toBeVisible();
		const response = await clip;
		const body = response ? ((await response.json()) as { points?: unknown[] }) : null;
		return { visible: true as const, status: response?.status() ?? null, points: body?.points?.length ?? null };
	} finally {
		await close();
	}
}

test.describe('audience sharing — runs', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let runId: string | null = null;

	test.afterEach(async () => {
		if (runId) {
			try {
				await deleteRun(runId);
			} catch {
				/* best-effort; run_shares cascades with the run */
			}
		}
		runId = null;
	});

	test('a run shared with one person opens for them, clipped, for nobody else, and revoking ends it', async ({
		page,
		browser
	}) => {
		const title = uniqueTitle('E2E shared run');
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 2_800,
			duration_s: 900,
			is_public: false,
			metadata: { activity_type: 'run', title },
			track: TRACK
		});

		await page.goto(`/runs/${runId}`);
		await page.getByTestId('run-audience-btn').click();
		const dialog = page.getByTestId('audience-dialog');
		await expect(dialog).toBeVisible({ timeout: 10_000 });
		await dialog.getByTestId('audience-level-specific').click();
		await dialog.getByTestId('audience-search').fill('morgan');
		await dialog.getByTestId('audience-people').getByRole('button', { name: /Morgan Lee/ }).click();
		await expect(dialog.getByTestId('audience-shared-list')).toContainText('Morgan Lee', { timeout: 10_000 });

		const admin = getAdminClient();
		const grants = await readRows(
			'run_shares by run_id',
			admin.from('run_shares').select('recipient_id, owner_id').eq('run_id', runId)
		);
		expect(grants).toEqual([{ recipient_id: USER_C_PRO.id, owner_id: USER_A.id }]);
		const row = await readRow(
			'runs by id',
			admin.from('runs').select('is_public, followers_only').eq('id', runId).single()
		);
		expect(row).toEqual({ is_public: false, followers_only: false });

		// The named recipient opens it, through the clipped path.
		const asMorgan = await viewRun(browser, USER_C_PRO, runId, title);
		expect(asMorgan.visible).toBe(true);
		if (asMorgan.visible) {
			expect(asMorgan.status).toBe(200);
			expect(asMorgan.points).toBe(TRACK.length - 1);
		}

		// A follower holds no grant and the run is not followers-only.
		expect((await viewRun(browser, USER_B, runId, title)).visible).toBe(false);

		// Revoke: access ends on the recipient's next read.
		await dialog.getByRole('button', { name: 'Stop sharing with Morgan Lee' }).click();
		await expect(dialog.getByTestId('audience-shared-list')).toHaveCount(0, { timeout: 10_000 });
		const after = await readMaybeRow(
			'run_shares by run_id',
			admin.from('run_shares').select('id').eq('run_id', runId).maybeSingle()
		);
		expect(after).toBeNull();
		expect((await viewRun(browser, USER_C_PRO, runId, title)).visible).toBe(false);
	});

	test('followers can open a followers-only run, others cannot, and Share never makes it public', async ({
		page,
		browser,
		context
	}) => {
		const title = uniqueTitle('E2E followers run');
		runId = await insertRun({
			user_id: USER_A.id,
			distance_m: 2_800,
			duration_s: 900,
			is_public: false,
			metadata: { activity_type: 'run', title },
			track: TRACK
		});
		await context.grantPermissions(['clipboard-read', 'clipboard-write']);

		await page.goto(`/runs/${runId}`);
		await page.getByTestId('run-audience-btn').click();
		const dialog = page.getByTestId('audience-dialog');
		await dialog.getByTestId('audience-level-followers').click();
		await expect(dialog.getByTestId('audience-level-followers')).toHaveAttribute('aria-pressed', 'true', {
			timeout: 10_000
		});
		await dialog.getByRole('button', { name: 'Close' }).click();
		await expect(page.getByTestId('run-visibility-chip')).toContainText('Followers');

		// Share hands out the in-app link; it must not open the public flip.
		await page.getByRole('button', { name: 'Copy link', exact: true }).click();
		await expect(page.locator('.toast', { hasText: /Link copied/ })).toBeVisible({ timeout: 10_000 });
		await expect(page.getByTestId('share-confirm-dialog')).toBeHidden();

		const admin = getAdminClient();
		const row = await readRow(
			'runs by id',
			admin.from('runs').select('is_public, followers_only').eq('id', runId).single()
		);
		expect(row).toEqual({ is_public: false, followers_only: true });

		const asAlex = await viewRun(browser, USER_B, runId, title);
		expect(asAlex.visible).toBe(true);
		if (asAlex.visible) expect(asAlex.points).toBe(TRACK.length - 1);
		expect((await viewRun(browser, USER_C_PRO, runId, title)).visible).toBe(false);

		// Nor does it reach the public share page or the follower's feed path.
		const pub = await readMaybeRow(
			'public_runs by id',
			admin.from('public_runs').select('id').eq('id', runId).maybeSingle()
		);
		expect(pub).toBeNull();
	});
});

test.describe('audience sharing — routes', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let routeId: string | null = null;

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (routeId) {
			await admin.from('direct_messages').delete().eq('route_id', routeId);
			await admin.from('routes').delete().eq('id', routeId);
		}
		routeId = null;
	});

	test('sending a private route to one person shares it with them instead of making it public', async ({
		page,
		browser
	}) => {
		const admin = getAdminClient();
		const name = uniqueTitle('E2E private route');
		const inserted = await readRow(
			'routes insert',
			admin
				.from('routes')
				.insert({
					user_id: USER_A.id,
					name,
					waypoints: TRACK.map(({ lat, lng }) => ({ lat, lng })),
					distance_m: 2_800,
					is_public: false
				})
				.select('id')
				.single()
		);
		routeId = inserted.id as string;

		await page.goto(`/routes/${routeId}`);
		await page.getByTestId('route-send-dm-btn').click();
		// No public-flip confirm: the send grants access to the one recipient.
		await expect(page.getByTestId('share-confirm-dialog')).toBeHidden();
		const send = page.getByTestId('send-route-dialog');
		await expect(send).toBeVisible({ timeout: 10_000 });
		await expect(send.getByTestId('send-route-note')).toContainText('It stays private');
		await send.getByTestId('send-route-search').fill('morgan');
		await send.getByRole('button', { name: /Morgan Lee/ }).click();
		await expect(page.getByTestId('send-route-sent')).toContainText('Morgan Lee', { timeout: 10_000 });

		const route = await readRow(
			'routes by id',
			admin.from('routes').select('is_public').eq('id', routeId).single()
		);
		expect(route.is_public).toBe(false);
		const grants = await readRows(
			'route_shares by route_id',
			admin.from('route_shares').select('recipient_id').eq('route_id', routeId)
		);
		expect(grants).toEqual([{ recipient_id: USER_C_PRO.id }]);
		const dm = await readRow(
			'direct_messages by route_id',
			admin.from('direct_messages').select('body').eq('route_id', routeId).single()
		);
		expect(dm.body).toContain(`/routes/${routeId}`);
		expect(dm.body).not.toContain('/share/route/');

		// Morgan opens it, clipped; Alex (no grant, not followers-only) cannot.
		const morgan = await openAs(browser, USER_C_PRO);
		try {
			const clip = morgan.page.waitForResponse((r) => r.url().includes('clip_route_for_viewer'), {
				timeout: 15_000
			});
			await morgan.page.goto(`/routes/${routeId}`);
			await expect(morgan.page.getByRole('heading', { name })).toBeVisible({ timeout: 15_000 });
			await expect(morgan.page.getByTestId('route-shared-with-you')).toBeVisible();
			const points = (await (await clip).json()) as unknown[];
			expect(points.length).toBe(TRACK.length - 1);
			await expect(morgan.page.getByTestId('route-share-btn')).toHaveCount(0);
		} finally {
			await morgan.close();
		}
		const alex = await openAs(browser, USER_B);
		try {
			await alex.page.goto(`/routes/${routeId}`);
			await expect(alex.page.getByRole('heading', { name: 'Route not found' })).toBeVisible({
				timeout: 15_000
			});
		} finally {
			await alex.close();
		}
	});
});
