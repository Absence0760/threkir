import { randomUUID } from 'node:crypto';

import { expect, test } from '../fixtures/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { allSitemapLocs } from '../fixtures/sitemap';

/**
 * The sitemap lists every public row, not the first 1,000.
 *
 * PostgREST cuts a response at `db.max-rows` (1,000 in config.toml) with a
 * 200 and no flag. The sitemap used to read each kind with `.limit(10_000)`,
 * so past 1,000 races (or runs, routes, events, clubs) the rest were dropped
 * from the crawl manifest without a word. This seeds more race listings than
 * the cap, dated far in the past so the old newest-first read would have cut
 * exactly these, and requires every one to reach a child sitemap.
 */
const SEEDED = 1_050;

test.describe('/sitemap.xml past db.max-rows', () => {
	test.use({ storageState: { cookies: [], origins: [] } });

	const stamp = Date.now();
	const ids = Array.from({ length: SEEDED }, () => randomUUID());

	test.beforeAll(async () => {
		const admin = getAdminClient();
		// Batched so no single insert is near the response cap either.
		for (let i = 0; i < ids.length; i += 500) {
			const { error } = await admin.from('race_listings').insert(
				ids.slice(i, i + 500).map((id, j) => ({
					id,
					provider: 'manual',
					name: `E2E sitemap race ${stamp} ${i + j}`,
					race_date: '2001-01-01',
					distance_m: 5_000,
				})),
			);
			if (error) throw new Error(`seeding race listings failed: ${error.message}`);
		}
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		for (let i = 0; i < ids.length; i += 500) {
			await admin.from('race_listings').delete().in('id', ids.slice(i, i + 500));
		}
	});

	test('every seeded race reaches a child sitemap, each once', async ({ request }) => {
		const locs = await allSitemapLocs(request);
		const raceIds = locs
			.map((loc) => /\/share\/race\/([0-9a-f-]{36})$/.exec(loc)?.[1])
			.filter((id): id is string => !!id);
		expect(raceIds.length).toBeGreaterThan(1_000);
		const listed = new Set(raceIds);
		expect(listed.size).toBe(raceIds.length);
		const missing = ids.filter((id) => !listed.has(id));
		expect(missing, `${missing.length} of ${SEEDED} seeded races missing`).toEqual([]);
	});
});
