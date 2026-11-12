import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { expect, test } from '../fixtures/test';
import { readRows } from '../fixtures/db-read';
import { getAdminClient, loadSupabaseEnv } from '../fixtures/local-supabase';
import { deleteRun, insertRun } from '../fixtures/simulate';
import { createSagaUsers, deleteSagaUsers, type SagaUser } from '../fixtures/saga-users';
import { USER_A } from '../fixtures/users';
import { decodeTrack, type CourseRunFixture } from '../../src/lib/parks/course_run_fixture';

/**
 * A run over the real Beaver Lake Trail reaches its board (issue #1342 step
 * 5c, in place of the hand test). The course is planted with the committed
 * Pocahontas line and checkpoints, so the database derives its lines from
 * the real geometry; the run is the clean synthetic Beaver Lake run of
 * fixtures/park_course_runs.json, uploaded as a phone sync uploads it. Then
 * the segment-match Edge Function is called the way the job worker calls it,
 * with the server key and the job's `{run_id}`, and the effort it writes is
 * what the course page's board shows. The share page stays nameless.
 *
 * The runner is a saga user: a park course effort awards durable badges.
 */

const ROOT = resolve(import.meta.dirname, '../../../..');
const PARK_DIR = 'scripts/parks/catalogue/us-va/pocahontas';
const fixture = JSON.parse(readFileSync(resolve(ROOT, 'fixtures/park_course_runs.json'), 'utf8')) as CourseRunFixture;
const manifest = JSON.parse(readFileSync(resolve(ROOT, PARK_DIR, 'manifest.json'), 'utf8')) as {
	attribution: string;
	courses: { slug: string; name: string; geojson: string; distance_m: number; checkpoints: { lat: number; lng: number }[] }[];
};
const beaver = manifest.courses.find((c) => c.slug === 'beaver-lake-trail');
const clean = fixture.cases.find((c) => c.key === 'beaver_clean');

test.describe('a run over a real park course', () => {
	let runner: SagaUser | null = null;
	let parkId: string | null = null;
	let segmentId: string | null = null;
	let runId: string | null = null;

	test.afterEach(async () => {
		const admin = getAdminClient();
		if (runId) await deleteRun(runId).catch(() => {});
		if (parkId) await admin.from('parks').delete().eq('id', parkId).then(() => {}, () => {});
		if (segmentId) await admin.from('global_segments').delete().eq('id', segmentId).then(() => {}, () => {});
		if (runner) await deleteSagaUsers([runner]);
		runner = null;
		parkId = null;
		segmentId = null;
		runId = null;
	});

	test.use({ storageState: USER_A.storageStatePath });

	test('is timed on the server and shows on the course board, and the share page names no runner', async ({
		page,
		browser,
	}) => {
		if (!beaver || !clean || !clean.want.effort) throw new Error('the Beaver Lake fixture case is missing');
		const admin = getAdminClient();
		const tag = `${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
		[runner] = (await createSagaUsers(1, { displayNames: [`Beaver Runner ${tag}`] })) as [SagaUser];

		const gj = JSON.parse(readFileSync(resolve(ROOT, PARK_DIR, beaver.geojson), 'utf8'));
		const line = gj.features.find((f: { geometry?: { type?: string } }) => f.geometry?.type === 'LineString');
		const parkSlug = `e2e-pocahontas-${tag}`;
		const courseName = `Beaver Lake Trail ${tag}`;
		const { data: seg, error: segErr } = await admin
			.from('global_segments')
			.insert({
				name: courseName,
				waypoints: line.geometry.coordinates.map((p: number[]) => ({ lat: p[1], lng: p[0] })),
				distance_m: beaver.distance_m,
				surface: 'trail',
				country_code: 'US',
			})
			.select('id, start_gate_source, end_gate_source')
			.single();
		if (segErr) throw segErr;
		segmentId = seg.id;
		expect([seg.start_gate_source, seg.end_gate_source]).toEqual(['derived', 'derived']);
		const { data: park, error: parkErr } = await admin
			.from('parks')
			.insert({
				slug: parkSlug,
				name: `E2E Pocahontas ${tag}`,
				agency: 'state',
				region_code: 'US-VA',
				country_code: 'US',
				timezone: 'America/New_York',
			})
			.select('id')
			.single();
		if (parkErr) throw parkErr;
		parkId = park.id;
		const { error: courseErr } = await admin.from('park_courses').insert({
			park_id: park.id,
			global_segment_id: seg.id,
			slug: 'beaver-lake-trail',
			course_shape: 'loop',
			geometry_source: 'osm',
			checkpoints: beaver.checkpoints,
			laps: 1,
			attribution: manifest.attribution,
		});
		if (courseErr) throw courseErr;

		// The fixture's run, an hour ago, so it is this season's.
		const startMs = Math.floor((Date.now() - 3_600_000) / 1000) * 1000;
		const track = decodeTrack(clean.track, startMs);
		runId = await insertRun({
			user_id: runner.id,
			started_at: new Date(startMs).toISOString(),
			duration_s: Math.round((Date.parse(track[track.length - 1].ts as string) - startMs) / 1000),
			distance_m: 4_000,
			is_public: true,
			track,
		});
		const jobs = await readRows(
			'segment_match jobs by run_id',
			admin.from('jobs').select('id').eq('kind', 'segment_match').eq('payload->>run_id', runId),
		);
		expect(jobs.length).toBeGreaterThan(0);

		const { url, serviceKey } = loadSupabaseEnv();
		const res = await fetch(`${url}/functions/v1/segment-match`, {
			method: 'POST',
			headers: { 'content-type': 'application/json', apikey: serviceKey },
			body: JSON.stringify({ run_id: runId }),
		});
		expect(res.status, await res.clone().text()).toBe(200);

		const efforts = await readRows(
			'global_segment_efforts by run_id',
			admin
				.from('global_segment_efforts')
				.select('time_seconds, started_at, matched_by, user_id')
				.eq('global_segment_id', seg.id)
				.eq('run_id', runId),
		);
		expect(efforts).toHaveLength(1);
		const effort = efforts[0] as { time_seconds: number | string; started_at: string; matched_by: string; user_id: string };
		const recorded = clean.matched['beaver-lake-trail'];
		expect(effort.matched_by).toBe('gate');
		expect(effort.user_id).toBe(runner.id);
		expect(Math.abs(Number(effort.time_seconds) - recorded.time_seconds)).toBeLessThan(0.01);
		expect(Math.abs(Number(effort.time_seconds) - clean.want.truth_s)).toBeLessThanOrEqual(clean.want.tolerance_s);
		expect(Date.parse(effort.started_at) - startMs).toBe(recorded.started_offset_ms);

		const total = Math.round(Number(effort.time_seconds));
		const shown = `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
		await page.goto(`/parks/us-va/${parkSlug}/beaver-lake-trail`);
		await expect(page.getByRole('heading', { level: 1, name: courseName })).toBeVisible();
		const rows = page.getByTestId('park-board').locator('li');
		await expect(rows).toHaveCount(1);
		await expect(rows.nth(0)).toContainText(`Beaver Runner ${tag}`);
		await expect(rows.nth(0).locator('.value')).toHaveText(shown);

		const anon = await browser.newContext({ storageState: { cookies: [], origins: [] } });
		try {
			const share = await anon.newPage();
			await share.goto(`/share/course/us-va/${parkSlug}/beaver-lake-trail`);
			await expect(share.getByRole('heading', { level: 1, name: courseName })).toBeVisible();
			await expect(share.getByText(`Beaver Runner ${tag}`)).toHaveCount(0);
			await expect(share.getByText(shown)).toHaveCount(0);
			await expect(share.locator('a[href^="/u/"]')).toHaveCount(0);
		} finally {
			await anon.close();
		}
	});
});
