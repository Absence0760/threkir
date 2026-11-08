import { readFile } from 'node:fs/promises';

import { expect, test } from '../fixtures/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * Park course SEO (issue #1313, decisions § 2394): the indexable
 * `/share/course/<region>/<park>/<course>` page, the in-app course page's
 * canonical onto it, and the course GPX carrying its geometry credit.
 *
 * The head shapes are unit-tested in share_course_meta.test.ts; this pins the
 * route wiring against a real row. Every row is planted (service role) under a
 * unique slug and removed afterwards.
 */

const M_PER_DEG_LAT = 111_320;

interface Planted {
	parkId: string;
	parkSlug: string;
	parkName: string;
	segmentId: string;
	courseName: string;
}

async function plantCourse(baseLat: number, lng: number): Promise<Planted> {
	const admin = getAdminClient();
	const tag = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
	const parkSlug = `e2e-seo-park-${tag}`;
	const parkName = `E2E SEO State Park ${tag}`;
	const courseName = `E2E SEO Loop ${tag}`;
	const { data: seg, error: segErr } = await admin
		.from('global_segments')
		.insert({
			name: courseName,
			waypoints: [
				{ lat: baseLat, lng },
				{ lat: baseLat + 1000 / M_PER_DEG_LAT, lng },
			],
			distance_m: 1000,
			surface: 'trail',
			country_code: 'US',
		})
		.select('id')
		.single();
	if (segErr) throw segErr;
	const { data: park, error: parkErr } = await admin
		.from('parks')
		.insert({
			slug: parkSlug,
			name: parkName,
			agency: 'state',
			region_code: 'US-VA',
			country_code: 'US',
			timezone: 'America/New_York',
			website_url: 'https://example.gov/e2e-park',
		})
		.select('id')
		.single();
	if (parkErr) throw parkErr;
	const { error: courseErr } = await admin.from('park_courses').insert({
		park_id: park.id,
		global_segment_id: seg.id,
		slug: 'lake-loop',
		course_shape: 'out_and_back',
		geometry_source: 'osm',
		checkpoints: [{ lat: baseLat + 500 / M_PER_DEG_LAT, lng }],
	});
	if (courseErr) throw courseErr;
	return { parkId: park.id, parkSlug, parkName, segmentId: seg.id, courseName };
}

async function teardown(p: Planted | null) {
	if (!p) return;
	const admin = getAdminClient();
	await admin.from('parks').delete().eq('id', p.parkId).then(() => {}, () => {});
	await admin.from('global_segments').delete().eq('id', p.segmentId).then(() => {}, () => {});
}

test.describe('park course SEO', () => {
	test.describe('signed out', () => {
		test.use({ storageState: { cookies: [], origins: [] } });

		test('the share page carries the course head and JSON-LD, and names no runner', async ({
			page,
		}) => {
			let planted: Planted | null = null;
			try {
				planted = await plantCourse(36.6, -77.7);
				const key = `us-va/${planted.parkSlug}/lake-loop`;
				await page.goto(`/share/course/${key}`);

				await expect(page).toHaveTitle(`${planted.courseName} at ${planted.parkName} — Threkir`);
				await expect(page.getByRole('heading', { level: 1, name: planted.courseName })).toBeVisible();
				await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
					'href',
					new RegExp(`/share/course/${key}$`),
				);
				await expect(page.locator('meta[name="description"]')).toHaveAttribute(
					'content',
					/^1\.0 km out-and-back course at E2E SEO State Park .*, Virginia\./,
				);

				const ld = JSON.parse(
					(await page.locator('script[type="application/ld+json"]').first().textContent()) as string,
				);
				expect(ld['@type']).toBe('SportsActivityLocation');
				expect(ld.name).toBe(planted.courseName);
				expect(ld.containedInPlace['@type']).toBe('Park');
				expect(ld.containedInPlace.name).toBe(planted.parkName);
				expect(ld.geo.latitude).toBe(36.6);

				await expect(page.getByTestId('share-course-attribution')).toContainText('OpenStreetMap');
				await expect(page.getByTestId('share-course-safety')).toBeVisible();
				await expect(page.getByTestId('share-course-boards')).toHaveAttribute(
					'href',
					`/parks/${key}`,
				);
				// The crawler surface is the course: no board and no runner link.
				await expect(page.locator('a[href^="/u/"]')).toHaveCount(0);
			} finally {
				await teardown(planted);
			}
		});

		test('an unknown course renders the branded not-found page with a valid head', async ({
			page,
		}) => {
			await page.goto('/share/course/us-va/no-such-park/no-such-course');
			await expect(page).toHaveTitle('Park course — Threkir');
			await expect(page.getByRole('heading', { name: 'Course not found.' })).toBeVisible();
			await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
				'href',
				/\/share\/course\/us-va\/no-such-park\/no-such-course$/,
			);
		});

		test('the in-app course page canonicals onto the share page', async ({ page }) => {
			let planted: Planted | null = null;
			try {
				planted = await plantCourse(36.7, -77.8);
				await page.goto(`/parks/us-va/${planted.parkSlug}/lake-loop`);
				await expect(page.getByRole('heading', { level: 1, name: planted.courseName })).toBeVisible();
				await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
					'href',
					new RegExp(`/share/course/us-va/${planted.parkSlug}/lake-loop$`),
				);
			} finally {
				await teardown(planted);
			}
		});
	});

	test.describe('signed in', () => {
		test.use({ storageState: USER_A.storageStatePath });

		test('the course GPX carries the line, its checkpoint and the OpenStreetMap credit', async ({
			page,
		}) => {
			let planted: Planted | null = null;
			try {
				planted = await plantCourse(36.8, -77.9);
				await page.goto(`/parks/us-va/${planted.parkSlug}/lake-loop`);
				await expect(page.getByRole('heading', { level: 1, name: planted.courseName })).toBeVisible();
				const [download] = await Promise.all([
					page.waitForEvent('download'),
					page.getByTestId('park-course-gpx').click(),
				]);
				const gpx = await readFile((await download.path()) as string, 'utf-8');
				expect(gpx).toContain(`<name>${planted.courseName}</name>`);
				expect(gpx).toContain('<copyright author="OpenStreetMap contributors">');
				expect(gpx).toContain('<link href="https://www.openstreetmap.org/copyright">');
				expect(gpx).toContain('<name>Checkpoint 1</name>');
				expect(gpx.match(/<trkpt /g)?.length).toBe(2);
			} finally {
				await teardown(planted);
			}
		});
	});
});
