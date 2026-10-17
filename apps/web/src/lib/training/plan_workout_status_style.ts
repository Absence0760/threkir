// One look per plan-workout state, shared by every web surface that draws a
// planned workout: PlanCalendar, CurrentWeekStrip, the week rows and the Today
// card on /plans/[id]. Before this, "done" was drawn three ways and a missed
// workout looked exactly like an upcoming one (issue #1186, decisions § 2084).
// Mobile twin: apps/mobile_android/lib/widgets/plan_workout_status_style.dart.
//
// Each surface binds these as `style:--wo-bg` / `--wo-border` /
// `--wo-border-style` / `--wo-glyph` and reads them with its own fallback, so it
// keeps its own box while the state colours live here once; a null fill or
// outline leaves the property unset and the fallback applies. Missed is neutral on purpose: the
// plan lets missed easy volume go (§ 144), so it is information, not a failure,
// and it borrows nothing from the error or warning ramps.

import type { PlanWorkoutStatus } from './plan_current';

type StatusLook = {
	/** Cell fill, or null to keep the surface's own. */
	bg: string | null;
	/** Outline colour (null keeps the surface's own) and style; `dashed` is what reads as "missed" without colour. */
	border: string | null;
	borderStyle: 'solid' | 'dashed';
	/** Material Symbols ligature, or null for no glyph. Every name is in the icon subset. */
	glyph: string | null;
	glyphColor: string;
};

const LOOK: Record<PlanWorkoutStatus, StatusLook> = {
	done: {
		bg: 'var(--color-success-light)',
		border: 'color-mix(in srgb, var(--color-success) 30%, var(--color-border))',
		borderStyle: 'solid',
		glyph: 'check_circle',
		glyphColor: 'var(--color-success-text)'
	},
	missed: {
		bg: 'transparent',
		border: 'var(--color-text-tertiary)',
		borderStyle: 'dashed',
		glyph: 'event_busy',
		glyphColor: 'var(--color-text-tertiary)'
	},
	skipped: {
		bg: 'transparent',
		border: null,
		borderStyle: 'solid',
		glyph: 'skip_next',
		glyphColor: 'var(--color-text-tertiary)'
	},
	upcoming: {
		bg: null,
		border: null,
		borderStyle: 'solid',
		glyph: null,
		glyphColor: 'var(--color-text-tertiary)'
	},
	rest: {
		bg: null,
		border: null,
		borderStyle: 'solid',
		glyph: null,
		glyphColor: 'var(--color-text-tertiary)'
	}
};

export function planWorkoutStatusLook(status: PlanWorkoutStatus): StatusLook {
	return LOOK[status];
}
