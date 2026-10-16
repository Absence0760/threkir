import { isPlanOverlapError } from '../core/supabase_error';
import { shiftIsoDate } from './plan_bulk_ops';

/// An active plan a new plan's window collides with, as the overlap dialog
/// names it.
export interface OverlapPlan {
	id: string;
	name: string;
	start_date: string;
	end_date: string;
}

/// The end date "End it early" gives an overlapped plan: the day before the
/// new plan starts.
export function overlapTrimDate(newStartIso: string): string {
	return shiftIsoDate(newStartIso, -1);
}

/// Whether "End it early" can resolve `overlapping`: only when every
/// overlapped plan starts before the new one, since a plan starting on or
/// after it would be left with no days (the RPC refuses that trim too).
export function canTrimOverlap(overlapping: readonly OverlapPlan[], newStartIso: string): boolean {
	return overlapping.length > 0 && overlapping.every((p) => p.start_date < newStartIso);
}

/// The end date a clone of `template` takes when it starts on `startIso`: the
/// clone RPCs shift every date by the same whole-day offset. Mirrors
/// `clonedPlanEndIso` in the mobile `training_service.dart`.
export function clonedPlanEndIso(
	template: { start_date: string; end_date: string },
	startIso: string
): string {
	const day = (iso: string) => Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / 86_400_000;
	return shiftIsoDate(startIso, day(template.end_date) - day(template.start_date));
}

export type PlanCreateOutcome<T> =
	| { kind: 'created'; value: T }
	| { kind: 'overlap'; overlapping: OverlapPlan[] };

/// Run one create or clone attempt. When the server refuses it because an
/// active plan now overlaps (23P01: the caller chose 'refuse', or a plan was
/// created since the dialog last looked), re-read the overlapping plans so
/// the caller can ask again with fresh names instead of failing or silently
/// replacing. A refusal with nothing left to name rethrows.
export async function attemptPlanCreate<T>(
	create: () => Promise<T>,
	lookupOverlaps: () => Promise<OverlapPlan[]>
): Promise<PlanCreateOutcome<T>> {
	try {
		return { kind: 'created', value: await create() };
	} catch (e) {
		if (!isPlanOverlapError(e)) throw e;
		const overlapping = await lookupOverlaps();
		if (overlapping.length === 0) throw e;
		return {
			kind: 'overlap',
			overlapping: [...overlapping].sort((a, b) => (a.start_date < b.start_date ? -1 : a.start_date > b.start_date ? 1 : 0))
		};
	}
}
