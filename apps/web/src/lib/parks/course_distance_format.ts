import { getUnit } from '../format/units.svelte.ts';
import { currentLocale } from '../i18n/store.svelte.ts';
import { courseDistanceLabel, courseDistanceRange } from './park_course_distance.ts';

// The preference-aware face of park_course_distance.ts for templates; both
// reads are reactive, so a unit or locale change re-renders the label.

export function fmtCourseDistance(metres: number | string | null | undefined): string {
	return courseDistanceLabel(Number(metres), getUnit(), currentLocale()) ?? '';
}

export function fmtCourseDistanceRange(metres: readonly (number | string)[]): string | null {
	return courseDistanceRange(metres.map(Number), getUnit(), currentLocale());
}
