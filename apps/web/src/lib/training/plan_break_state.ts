/**
 * The break offer's state for a host (decisions § 2128), pure so it can be
 * tested without the data layer. `loadBreakContext` in core reads the
 * context; this decides from it.
 */

import {
	breakOfferShowing,
	breakWindow,
	detectPlanBreak,
	type BreakInput,
	type PlanBreak
} from './plan_break.ts';

/// What a host needs beyond the plan to know whether the break offer shows
/// (decisions § 2128): the latest run before today and the answered offer.
export type BreakContext = { runDatesIso: string[]; dismissedPref: unknown };

/// The host's break state. `pending` while the reads are in flight, when the
/// other plan cards wait rather than flash and then give way to the offer.
export type BreakState = {
	pending: boolean;
	found: PlanBreak | null;
	showing: boolean;
	window: { fromIso: string; untilIso: string } | null;
};

/// The break state for a plan, from a context that is still loading
/// (`undefined`), failed (`null`) or loaded. A malformed row hides the offer
/// and lets the other cards show, rather than throwing out of a page render.
export function breakState(
	plan: BreakInput['plan'] & { id: string },
	weeks: BreakInput['weeks'],
	workouts: BreakInput['workouts'],
	todayIso: string,
	context: BreakContext | null | undefined
): BreakState {
	if (context === undefined) return { pending: true, found: null, showing: false, window: null };
	if (context === null) return { pending: false, found: null, showing: false, window: null };
	try {
		const found = detectPlanBreak({ plan, weeks, workouts, runDatesIso: context.runDatesIso, todayIso });
		return {
			pending: false,
			found,
			showing: breakOfferShowing(found, context.dismissedPref, plan.id),
			window: breakWindow(found, context.dismissedPref, plan.id, todayIso)
		};
	} catch (e) {
		console.error('plan break: working out the break failed', e);
		return { pending: false, found: null, showing: false, window: null };
	}
}
