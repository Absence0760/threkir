import { expect, test } from '../fixtures/test';

import { getAdminClient } from '../fixtures/local-supabase';
import { insertRun, deleteRun } from '../fixtures/simulate';
import { USER_A } from '../fixtures/users';
import { readRow, readRows } from '../fixtures/db-read';

/**
 * Catalogue segments timed by their start and end lines (#1308, decisions
 * § 2402), through the owner-on-view fallback scorer on /runs/[id].
 *
 *   1. A planted segment gets its lines from its own polyline (the
 *      global_segments trigger). A run crossing both is timed between the
 *      interpolated crossings and recorded as `matched_by = 'gate'`.
 *   2. A run scored by the circles-only matcher (an old `zone` effort, a
 *      count stamp with no matcher version) shows the board's "measured the
 *      old way" note; the owner's next view re-matches it by delete then
 *      insert, and the note goes.
 */

const uniq = (prefix: string) => `${prefix} ${Date.now()}-${Math.random().toString(36).slice(2, 6)}`;
const M_PER_DEG_LAT = 111_320;

/** North along `lng` at `speed` m/s, one fix every `stepM`, from `fromM` before the segment start. */
function buildTrack(baseLat: number, lng: number, fromM: number, toM: number, stepM: number, speed: number) {
	const t0 = Date.parse('2026-05-01T08:00:00Z');
	const pts: { lat: number; lng: number; ts: string }[] = [];
	for (let d = fromM; d <= toM + 1e-6; d += stepM) {
		pts.push({
			lat: baseLat + d / M_PER_DEG_LAT,
			lng,
			ts: new Date(t0 + ((d - fromM) / speed) * 1000).toISOString(),
		});
	}
	return pts;
}

async function plantSegment(baseLat: number, lng: number, lengthM: number): Promise<string> {
	const { data, error } = await getAdminClient()
		.from('global_segments')
		.insert({
			name: uniq('e2e-gate-seg'),
			waypoints: [
				{ lat: baseLat, lng },
				{ lat: baseLat + lengthM / M_PER_DEG_LAT, lng },
			],
			distance_m: lengthM,
			surface: 'road',
			country_code: 'AU',
		})
		.select('id, start_gate_source, end_gate_source')
		.single();
	if (error) throw error;
	expect(data.start_gate_source).toBe('derived');
	expect(data.end_gate_source).toBe('derived');
	return data.id;
}

async function removeSegment(id: string) {
	if (!id) return;
	try {
		await getAdminClient().from('global_segments').delete().eq('id', id);
	} catch {
		// Best-effort teardown: a failed cleanup must not mask the result.
	}
}

test.describe('catalogue segments timed by their lines', () => {
	test.use({ storageState: USER_A.storageStatePath });

	test('a run crossing both lines is timed between the crossings and marked as a line match', async ({
		page,
	}) => {
		const BASE_LAT = -37.62;
		const LNG = 144.62;
		let segmentId = '';
		let runId = '';
		try {
			segmentId = await plantSegment(BASE_LAT, LNG, 800);
			// Fixes every 30 m starting 50 m before the start line, so neither
			// line falls on a fix: the crossings are interpolated. 800 m at
			// 2.5 m/s is 320 s (5:20).
			runId = await insertRun({
				user_id: USER_A.id,
				started_at: '2026-05-01T08:00:00Z',
				duration_s: 380,
				distance_m: 950,
				is_public: true,
				track: buildTrack(BASE_LAT, LNG, -50, 900, 30, 2.5),
			});

			await page.goto(`/runs/${runId}`);
			const row = page.locator(`.efforts a.effort-row[href="/segments/${segmentId}"]`);
			await expect(row).toBeVisible({ timeout: 15_000 });
			await expect(row.locator('.time')).toHaveText('5:20');

			const eff = await readRows(
				'global_segment_efforts by global_segment_id',
				getAdminClient()
					.from('global_segment_efforts')
					.select('time_seconds, matched_by')
					.eq('global_segment_id', segmentId),
			);
			expect(eff.length).toBe(1);
			expect(eff[0]?.matched_by).toBe('gate');
			expect(Math.abs(Number(eff[0]?.time_seconds) - 320)).toBeLessThan(0.05);
		} finally {
			if (runId) await deleteRun(runId).catch(() => {});
			await removeSegment(segmentId);
		}
	});

	test('an effort the old matcher wrote is re-matched on the owner\'s next view, and the board note goes', async ({
		page,
	}) => {
		const BASE_LAT = -37.66;
		const LNG = 144.66;
		const admin = getAdminClient();
		let segmentId = '';
		let runId = '';
		try {
			segmentId = await plantSegment(BASE_LAT, LNG, 800);
			const { count, error: countErr } = await admin
				.from('global_segments')
				.select('id', { count: 'exact', head: true })
				.eq('is_active', true);
			if (countErr || count == null) throw countErr ?? new Error('no catalogue count');
			// Scored against today's catalogue by the circles-only matcher:
			// the count stamp alone, no matcher version.
			runId = await insertRun({
				user_id: USER_A.id,
				started_at: '2026-05-01T08:00:00Z',
				duration_s: 380,
				distance_m: 950,
				is_public: true,
				metadata: { global_segments_scored_count: count },
				track: buildTrack(BASE_LAT, LNG, -50, 900, 30, 2.5),
			});
			const { error: effErr } = await admin.from('global_segment_efforts').insert({
				global_segment_id: segmentId,
				run_id: runId,
				user_id: USER_A.id,
				time_seconds: 333,
				started_at: '2026-05-01T08:00:18Z',
			});
			if (effErr) throw effErr;

			await page.goto(`/segments/${segmentId}`);
			await expect(page.getByTestId('segment-old-match-note')).toBeVisible({ timeout: 10_000 });

			await page.goto(`/runs/${runId}`);
			const row = page.locator(`.efforts a.effort-row[href="/segments/${segmentId}"]`);
			await expect(row).toBeVisible({ timeout: 15_000 });
			await expect
				.poll(
					async () => {
						const rows = await readRows(
							'global_segment_efforts by global_segment_id',
							admin
								.from('global_segment_efforts')
								.select('time_seconds, matched_by')
								.eq('global_segment_id', segmentId),
						);
						return rows.map((r) => `${r.matched_by}:${Math.round(Number(r.time_seconds))}`);
					},
					{ timeout: 15_000 },
				)
				.toEqual(['gate:320']);

			const run = await readRow('runs by id', admin.from('runs').select('metadata').eq('id', runId).single());
			expect((run.metadata as Record<string, unknown>).global_segments_matcher_version).toBe(2);

			await page.goto(`/segments/${segmentId}`);
			await expect(page.locator('.section ol li')).toHaveCount(1, { timeout: 10_000 });
			await expect(page.getByTestId('segment-old-match-note')).toHaveCount(0);
		} finally {
			if (runId) await deleteRun(runId).catch(() => {});
			await removeSegment(segmentId);
		}
	});
});
