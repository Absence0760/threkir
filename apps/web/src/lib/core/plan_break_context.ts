import { fetchRuns } from './data';
import { effective, loadSettings } from '../settings/settings';
import { formatISO, parseISO } from '../training/training';
import type { BreakContext } from '../training/plan_break_state';

export const PLAN_BREAK_DISMISSED_KEY = 'plan_break_dismissed';

/// Null when either read failed: auxiliary (L4), so an unknown break costs
/// the offer, never the page.
export async function loadBreakContext(userId: string, todayIso: string): Promise<BreakContext | null> {
	try {
		const [rows, settings] = await Promise.all([
			fetchRuns({
				limit: 1,
				columns: ['started_at'] as const,
				startedAtBefore: parseISO(todayIso).toISOString(),
				throwOnError: true
			}),
			loadSettings(userId)
		]);
		return {
			runDatesIso: rows.map((r) => formatISO(new Date(r.started_at))),
			dismissedPref: effective<unknown>(settings, PLAN_BREAK_DISMISSED_KEY) ?? null
		};
	} catch (e) {
		console.error('plan break: reading the latest run or settings failed', e);
		return null;
	}
}
