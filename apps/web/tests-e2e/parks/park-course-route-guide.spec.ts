import { readFile } from 'node:fs/promises';

import { expect, test } from '../fixtures/test';
import { getAdminClient } from '../fixtures/local-supabase';
import { USER_A } from '../fixtures/users';

/**
 * A park course's route guide (issue #1344, decisions § 2448): the course
 * page and its share page show the steps in order under the "not yet checked
 * on the ground" note, the note becomes the checked date once
 * `route_guide_checked_at` is set, and the course GPX carries the guide as
 * its track description. Template selection is unit-tested against
 * fixtures/route_guide_cases.json; this pins the wiring against a real row.
 *
 * Fixtures sit at (52.3, 12.7), which no seed row or other spec touches.
 */

const TAG = crypto.randomUUID().slice(0, 8);
const PARK_SLUG = `e2e-guide-park-${TAG}`;
const COURSE_NAME = `E2E Guide Loop ${TAG}`;
const GUIDE = {
	version: 1,
	lang: 'en',
	getting_there: 'Park by the boathouse.',
	steps: [
		{ kind: 'start', at_m: 0, name: 'Lake Trail' },
		{ kind: 'direction', at_m: 0, rotation: 'clockwise' },
		{ kind: 'junction', at_m: 400, turn: 'left', name: 'Ridge Trail' },
		{ kind: 'checkpoint', at_m: 500, order: 1, of: 1 },
		{ kind: 'finish', at_m: 1000 },
	],
};
let parkId: string | null = null;
let segmentId: string | null = null;

test.describe('park course route guide (web)', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test.beforeAll(async () => {
		const admin = getAdminClient();
		const seg = await admin
			.from('global_segments')
			.insert({
				name: COURSE_NAME,
				waypoints: [
					{ lat: 52.3, lng: 12.7 },
					{ lat: 52.3045, lng: 12.7 },
					{ lat: 52.3, lng: 12.7001 },
				],
				distance_m: 1000,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id')
			.single();
		if (seg.error) throw seg.error;
		segmentId = seg.data.id;
		const park = await admin
			.from('parks')
			.insert({
				slug: PARK_SLUG,
				name: `E2E Guide Park ${TAG}`,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (park.error) throw park.error;
		parkId = park.data.id;
		const course = await admin.from('park_courses').insert({
			park_id: parkId,
			global_segment_id: segmentId,
			slug: 'guide-loop',
			course_shape: 'loop',
			geometry_source: 'osm',
			checkpoints: [{ lat: 52.3045, lng: 12.7 }],
			laps: 1,
			route_guide: GUIDE,
			route_guide_checked_at: null,
		});
		if (course.error) throw course.error;
	});

	test.afterAll(async () => {
		const admin = getAdminClient();
		if (parkId) await admin.from('parks').delete().eq('id', parkId);
		if (segmentId) await admin.from('global_segments').delete().eq('id', segmentId);
	});

	test('the course page lists the guide under the not-yet-checked note, and the GPX carries it', async ({
		page,
	}) => {
		await page.goto(`/parks/us-va/${PARK_SLUG}/guide-loop`);
		await expect(page.getByRole('heading', { level: 1, name: COURSE_NAME })).toBeVisible({ timeout: 15_000 });
		const guide = page.getByTestId('park-course-guide');
		await expect(guide.getByRole('heading', { name: 'Route guide' })).toBeVisible();
		await expect(page.getByTestId('park-course-guide-pending')).toHaveText(
			'Drafted from map data, not yet checked on the ground.',
		);
		await expect(page.getByTestId('park-course-guide-getting-there')).toHaveText('Park by the boathouse.');
		const steps = page.getByTestId('park-course-guide-steps').getByRole('listitem');
		await expect(steps.first()).toHaveText('Start on Lake Trail.');
		await expect(steps.nth(1)).toHaveText('Run the loop clockwise.');
		await expect(steps.nth(2)).toHaveText('Pass every checkpoint in order, or the run is not timed.');
		await expect(steps.nth(3)).toContainText('turn left onto Ridge Trail.');
		await expect(steps).toHaveCount(6);

		const [download] = await Promise.all([
			page.waitForEvent('download'),
			page.getByTestId('park-course-gpx').click(),
		]);
		const gpx = await readFile((await download.path()) as string, 'utf-8');
		expect(gpx).toContain(
			'<desc>Drafted from map data, not yet checked on the ground.\nPark by the boathouse.\nStart on Lake Trail.\n',
		);
		expect(gpx).toContain('400 m: turn left onto Ridge Trail.');
	});

	test('the share page shows the same guide', async ({ page }) => {
		await page.goto(`/share/course/us-va/${PARK_SLUG}/guide-loop`);
		await expect(page.getByTestId('share-course-guide-pending')).toBeVisible({ timeout: 15_000 });
		await expect(
			page.getByTestId('share-course-guide-steps').getByRole('listitem').first(),
		).toHaveText('Start on Lake Trail.');
	});

	test('a guide checked on the ground says when instead', async ({ page }) => {
		const admin = getAdminClient();
		const checked = await admin
			.from('park_courses')
			.update({ route_guide_checked_at: '2026-12-01' })
			.eq('park_id', parkId as string);
		if (checked.error) throw checked.error;
		await page.goto(`/parks/us-va/${PARK_SLUG}/guide-loop`);
		await expect(page.getByTestId('park-course-guide-checked')).toContainText('Checked on the ground on', {
			timeout: 15_000,
		});
		await expect(page.getByTestId('park-course-guide-pending')).toHaveCount(0);
	});
});
