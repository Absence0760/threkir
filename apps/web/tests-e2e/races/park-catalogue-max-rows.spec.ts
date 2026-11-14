import { randomUUID } from 'node:crypto';

import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Races & courses and /parks read the whole park catalogue and search, order
 * and count it in the browser. PostgREST stops an unranged read at
 * `db.max-rows` (1000, the CLI default `apps/backend/supabase/config.toml`
 * keeps) with a 200 and no flag, so one read past that many courses lost the
 * rest from the list, its count and its search (issue #1374). The reads walk
 * by keyset cursor now; this plants one more course than a single read can
 * return and expects every one of them to reach both pages.
 *
 * The park sits in region ZZ-ZZZ so it sorts after every other park and its
 * courses never push another spec's planted course out of the first eight.
 */

const MAX_ROWS = 1000;
const COUNT = MAX_ROWS + 1;
const CHUNK = 250;

interface Planted {
	tag: string;
	parkId: string;
	parkName: string;
	segmentIds: string[];
}

async function insertChunked(table: 'global_segments' | 'park_courses', rows: object[]) {
	const admin = getAdminClient();
	for (let i = 0; i < rows.length; i += CHUNK) {
		// No `.select()`: a representation of more than max-rows rows would be
		// cut the same way the read was.
		const { error } = await admin.from(table).insert(rows.slice(i, i + CHUNK) as never);
		if (error) throw error;
	}
}

async function plantCatalogue(): Promise<Planted> {
	const admin = getAdminClient();
	const tag = `maxrows${Date.now()}${Math.random().toString(36).slice(2, 6)}`;
	const parkName = `Max Rows Park ${tag}`;
	const { data: park, error: parkErr } = await admin
		.from('parks')
		.insert({
			slug: `e2e-${tag}`,
			name: parkName,
			agency: 'state',
			region_code: 'ZZ-ZZZ',
			country_code: 'ZZ',
			timezone: 'Etc/UTC',
		})
		.select('id')
		.single();
	if (parkErr) throw parkErr;
	const segmentIds = Array.from({ length: COUNT }, () => randomUUID());
	const planted: Planted = { tag, parkId: park.id, parkName, segmentIds };
	try {
		await insertChunked(
			'global_segments',
			segmentIds.map((id, i) => ({
				id,
				name: `Max Rows Loop ${String(i).padStart(4, '0')}`,
				waypoints: [
					{ lat: 10 + i / 1000, lng: 10 },
					{ lat: 10 + i / 1000 + 0.01, lng: 10 },
				],
				distance_m: 1000 + i,
				surface: 'trail',
				country_code: 'ZZ',
			})),
		);
		await insertChunked(
			'park_courses',
			segmentIds.map((id, i) => ({
				park_id: park.id,
				global_segment_id: id,
				slug: `loop-${String(i).padStart(4, '0')}`,
				course_shape: 'loop',
				geometry_source: 'osm',
			})),
		);
	} catch (e) {
		await teardown(planted);
		throw e;
	}
	return planted;
}

async function teardown(p: Planted | null) {
	if (!p) return;
	const admin = getAdminClient();
	await admin.from('parks').delete().eq('id', p.parkId).then(() => {}, () => {});
	for (let i = 0; i < p.segmentIds.length; i += CHUNK) {
		await admin
			.from('global_segments')
			.delete()
			.in('id', p.segmentIds.slice(i, i + CHUNK))
			.then(() => {}, () => {});
	}
}

test.describe('park catalogue past db.max-rows', () => {
	test.use({ storageState: USER_A.storageStatePath });

	let planted: Planted | null = null;
	test.beforeAll(async () => {
		test.setTimeout(120_000);
		planted = await plantCatalogue();
	});
	test.afterAll(async () => {
		await teardown(planted);
	});

	test('Run any time counts and finds every course past one read', async ({ page }) => {
		const p = planted!;
		await page.goto('/races');
		const search = page.getByTestId('races-search');
		await search.fill(p.tag);
		const seeAll = page.getByTestId('races-any-time-all');
		await expect(seeAll).toHaveText(/^See all 1,?001 courses/, { timeout: 30_000 });

		// The last course by slug is the one a single read past the cap could
		// not reach whatever order the server chose; the search finds it.
		await search.fill(`${p.tag} loop 1000`);
		const cards = page.getByTestId('races-any-time-course');
		await expect(cards).toHaveCount(1, { timeout: 10_000 });
		await expect(cards.first()).toContainText('Max Rows Loop 1000');
	});

	test('/parks counts every course of a park past one read', async ({ page }) => {
		const p = planted!;
		await page.goto(`/parks?q=${encodeURIComponent(p.tag)}`);
		const card = page.getByTestId('park-card').filter({ hasText: p.parkName });
		await expect(card).toHaveCount(1, { timeout: 30_000 });
		await expect(card.getByTestId('park-card-facts')).toContainText(/1,?001 courses/);
	});
});
