// The course line editor's numeric form (#1305, #1358): what it seeds from,
// and when a refresh of the server's lines may replace what is typed. Pure, so
// the rules are testable without a DOM; CourseGateEditor.svelte holds the state.
// Web-only: mobile shows course lines but has no editor.

import { COURSE_GATE_DEFAULT_HALF_WIDTH_M, type CourseGate, type GateWhich } from './course_gates';

export interface GateFormValues {
	lat: number | null;
	lng: number | null;
	bearingDeg: number | null;
	halfWidthM: number;
}

/** What the form was last seeded from, and whether it has been typed in since. */
export interface GateFormSync {
	which: GateWhich | null;
	seededFrom: CourseGate | null;
	dirty: boolean;
}

function round(v: number, places: number): number {
	const f = 10 ** places;
	return Math.round(v * f) / f;
}

export function gateFormSeed(g: CourseGate | null): GateFormValues {
	return {
		lat: g ? round(g.lat, 6) : null,
		lng: g ? round(g.lng, 6) : null,
		bearingDeg: g ? round(g.bearingDeg, 1) : null,
		halfWidthM: g ? g.halfWidthM : COURSE_GATE_DEFAULT_HALF_WIDTH_M
	};
}

/** Same line by value. A refetch builds a new object for an unchanged row. */
export function sameGate(a: CourseGate | null, b: CourseGate | null): boolean {
	if (a === null || b === null) return a === b;
	return (
		a.lat === b.lat &&
		a.lng === b.lng &&
		a.bearingDeg === b.bearingDeg &&
		a.halfWidthM === b.halfWidthM &&
		a.source === b.source
	);
}

/**
 * Whether the form should take the server's copy of the edited line. A
 * switch to the other line always does; otherwise only a line that actually
 * moved does, and never over edits not yet applied.
 */
export function shouldReseed(sync: GateFormSync, which: GateWhich, server: CourseGate | null): boolean {
	if (sync.which !== which) return true;
	if (sync.dirty) return false;
	return !sameGate(sync.seededFrom, server);
}

/**
 * The width a number field's entry leaves the form holding: a cleared or
 * half-typed field keeps the last valid width rather than becoming empty,
 * which Apply would otherwise save as the default.
 */
export function widthFromEntry(entry: number | null | undefined, previous: number): number {
	return typeof entry === 'number' && Number.isFinite(entry) ? entry : previous;
}
