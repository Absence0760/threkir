// The per-row reading every plan surface shares: which state a planned workout
// is in on the runner's local day, and the one accessible name a calendar cell,
// a strip cell or a week row announces for it. Mobile twin:
// `planWorkoutStatusOf` / `planWorkoutSemanticsLabel` in
// apps/mobile_android/lib/widgets/plan_workout_status_style.dart.

import type { MessageKey } from '#lib/i18n/messages.ts';
import { planWorkoutStatus, type PlanWorkoutStatus } from './plan_current';
import { isWorkoutCompleted, isWorkoutSkipped } from './training';

type Row = {
	scheduled_date: string;
	kind: string;
	manually_completed?: boolean | null;
	completed_run_id?: string | null;
	skipped_at?: string | null;
};

export function planWorkoutStatusOf(wo: Row, todayIso: string): PlanWorkoutStatus {
	return planWorkoutStatus(
		{
			scheduled_date: wo.scheduled_date,
			kind: wo.kind,
			completed: isWorkoutCompleted(wo),
			skipped: isWorkoutSkipped(wo)
		},
		todayIso
	);
}

/// "Tue 13 Oct: Tempo, 8.0 km, missed". The parts arrive formatted and `t` is
/// the catalogue lookup (`m` in a component), so this stays free of the i18n
/// and unit stores and unit-tests under tsx; `distance` is null on rest days.
export function planWorkoutAriaLabel(
	wo: Row,
	todayIso: string,
	parts: { day: string; kind: string; distance: string | null },
	t: (key: MessageKey) => string
): string {
	const status = planWorkoutStatusOf(wo, todayIso);
	const suffix =
		status === 'done'
			? t('planDetail.ariaCompletedSuffix')
			: status === 'skipped'
				? t('planDetail.ariaSkippedSuffix')
				: status === 'missed'
					? t('planDetail.ariaMissedSuffix')
					: '';
	const today = wo.scheduled_date === todayIso ? t('planDetail.ariaTodaySuffix') : '';
	const dist = parts.distance ? `, ${parts.distance}` : '';
	return `${parts.day}: ${parts.kind}${dist}${suffix}${today}`;
}
