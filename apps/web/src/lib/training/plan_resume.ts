/**
 * What resuming a paused plan should offer (issue #1186): push the weeks that
 * had not started when the runner paused back by the whole weeks the plan sat
 * paused, so it picks up again next week instead of coming back as missed.
 *
 * The week the runner paused in stays (it may hold work they did), and week 0
 * never moves because it is anchored on the start date. `resume_training_plan`
 * applies the result in one transaction.
 */

import { daysBetweenIso } from './cycle_plan.ts';

export const RESUME_MAX_SHIFT_WEEKS = 52;

export interface ResumeShift {
	/// The first week index to move.
	fromWeekIndex: number;
	/// How many whole weeks it and every later week move.
	weeks: number;
}

/// The shift a resume on `todayIso` should offer for a plan that started on
/// `startIso`, has `weekCount` weeks and was paused on `pausedOnIso` (all the
/// runner's local dates), or null when there is nothing to push back: paused
/// and resumed in the same plan week, paused before the plan started, paused
/// in its last week, or a pause date we do not know or cannot read.
export function resumeShift(input: {
	startIso: string;
	pausedOnIso: string | null;
	todayIso: string;
	weekCount: number;
}): ResumeShift | null {
	if (!input.pausedOnIso) return null;
	const toPause = daysBetweenIso(input.startIso, input.pausedOnIso);
	const toToday = daysBetweenIso(input.startIso, input.todayIso);
	if (toPause == null || toToday == null) return null;
	const pausedWeek = Math.floor(toPause / 7);
	const todayWeek = Math.floor(toToday / 7);
	if (pausedWeek < 0) return null;
	const fromWeekIndex = pausedWeek + 1;
	const weeks = Math.min(todayWeek - pausedWeek, RESUME_MAX_SHIFT_WEEKS);
	if (weeks < 1 || fromWeekIndex >= input.weekCount) return null;
	return { fromWeekIndex, weeks };
}
