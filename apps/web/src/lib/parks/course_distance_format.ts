import { getUnit } from '../format/units.svelte.ts';
import { currentLocale } from '../i18n/store.svelte.ts';
import { courseDistanceRangeText, courseDistanceText } from './course_distance_text.ts';

// The preference-aware face of course_distance_text.ts for templates; both
// reads are reactive, so a unit or locale change re-renders the label.

export function fmtCourseDistance(metres: number | string | null | undefined): string {
	return courseDistanceText(metres, getUnit(), currentLocale());
}

export function fmtCourseDistanceRange(metres: readonly (number | string | null | undefined)[]): string | null {
	return courseDistanceRangeText(metres, getUnit(), currentLocale());
}
