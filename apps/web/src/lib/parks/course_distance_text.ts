import { courseDistanceLabel, courseDistanceRange, type CourseDistanceUnit } from './park_course_distance.ts';

// course_distance_format.ts reads the unit and locale from runes modules the
// `tsx --test` runner cannot compile; the part worth testing — reading a
// stored distance that may arrive as a numeric string, or not at all — is
// here, with the preference passed in.

function metresOf(value: number | string | null | undefined): number {
	if (value == null || (typeof value === 'string' && value.trim() === '')) return Number.NaN;
	return Number(value);
}

export function courseDistanceText(
	metres: number | string | null | undefined,
	unit: CourseDistanceUnit,
	locale: string,
): string {
	return courseDistanceLabel(metresOf(metres), unit, locale) ?? '';
}

export function courseDistanceRangeText(
	metres: readonly (number | string | null | undefined)[],
	unit: CourseDistanceUnit,
	locale: string,
): string | null {
	return courseDistanceRange(metres.map(metresOf), unit, locale);
}
