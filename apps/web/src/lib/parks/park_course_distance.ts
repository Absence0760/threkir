/**
 * How a park course's distance reads, and the order a park lists its
 * courses in (issue #1352). A course distance is a name more than a
 * measurement, so it reads "5 km", "21.1 km" or "3.1 mi": whole when the
 * one-decimal value lands on a whole number, else one decimal, never two.
 *
 * Parity pair with `apps/mobile_android/lib/park_course_distance.dart`
 * (docs/architecture/parity_pairs.md). Pure (explicit unit and locale) so it
 * tests without the Svelte compiler; callers pass `getUnit()` and the UI
 * locale.
 */

import { formatDecimal } from '../format/number.ts';

export type CourseDistanceUnit = 'km' | 'mi';

const METRES_PER_MILE = 1609.344;

export interface CourseDistanceParts {
	/** Already rounded to `fractionDigits`. */
	value: number;
	fractionDigits: 0 | 1;
	unit: CourseDistanceUnit;
}

/** Null for a distance that is not a finite, non-negative number. */
export function courseDistanceParts(metres: number, unit: CourseDistanceUnit): CourseDistanceParts | null {
	if (!Number.isFinite(metres) || metres < 0) return null;
	const raw = unit === 'mi' ? metres / METRES_PER_MILE : metres / 1000;
	const tenths = Math.round(raw * 10);
	if (tenths % 10 === 0) return { value: tenths / 10, fractionDigits: 0, unit };
	return { value: tenths / 10, fractionDigits: 1, unit };
}

function formatParts(p: CourseDistanceParts, locale?: string): string {
	return formatDecimal(p.value, p.fractionDigits, locale);
}

/** `5000, 'km'` → `5 km`; `21100, 'km'` → `21.1 km`; null when unreadable. */
export function courseDistanceLabel(metres: number, unit: CourseDistanceUnit, locale?: string): string | null {
	const p = courseDistanceParts(metres, unit);
	return p ? `${formatParts(p, locale)} ${p.unit}` : null;
}

/**
 * A park's shortest to longest course, `5–50 km`, or one label when they
 * read the same. Unreadable distances are skipped; null when none is left.
 */
export function courseDistanceRange(
	metres: readonly number[],
	unit: CourseDistanceUnit,
	locale?: string,
): string | null {
	let min: number | null = null;
	let max: number | null = null;
	for (const m of metres) {
		if (courseDistanceParts(m, unit) === null) continue;
		if (min === null || m < min) min = m;
		if (max === null || m > max) max = m;
	}
	if (min === null || max === null) return null;
	const lo = courseDistanceParts(min, unit)!;
	const hi = courseDistanceParts(max, unit)!;
	const loText = formatParts(lo, locale);
	const hiText = formatParts(hi, locale);
	if (loText === hiText) return `${loText} ${unit}`;
	return `${loText}–${hiText} ${unit}`;
}

export interface ParkCourseSortKey {
	distanceM: number;
	name: string;
	slug: string;
	status: string;
}

function compareText(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

/** Closed courses last, then shortest first, then name, then slug. */
export function compareParkCourses(a: ParkCourseSortKey, b: ParkCourseSortKey): number {
	return (
		Number(a.status === 'closed') - Number(b.status === 'closed') ||
		a.distanceM - b.distanceM ||
		compareText(a.name, b.name) ||
		compareText(a.slug, b.slug)
	);
}

/** A park's courses in list order, as a new array; the input is untouched. */
export function sortParkCourses<T>(courses: readonly T[], key: (course: T) => ParkCourseSortKey): T[] {
	return courses
		.map((course) => ({ course, k: key(course) }))
		.sort((a, b) => compareParkCourses(a.k, b.k))
		.map(({ course }) => course);
}

/**
 * Whether a course's shape is worth a label. Nearly every park course is a
 * loop, so "Loop" says nothing; out-and-back and point-to-point do.
 */
export function courseShapeShown(shape: string | null | undefined): boolean {
	return shape === 'out_and_back' || shape === 'point_to_point';
}

/** The laps a chip names, or null when there is no chip (one lap or unknown). */
export function courseLapsChip(laps: number | null | undefined): number | null {
	return typeof laps === 'number' && Number.isInteger(laps) && laps > 1 ? laps : null;
}
