/**
 * The order of the "Run any time" park courses on the Races & courses page
 * (issue #1352). Nearest first when the page has a point to measure from,
 * otherwise a stable order that does not depend on where the reader is.
 * Either way a closed course sinks below every course that can be run.
 *
 * Parity pair with `apps/mobile_android/lib/any_time_courses.dart`
 * (docs/architecture/parity_pairs.md).
 */

import { haversineMetres } from '../runs/run_stats.ts';
import { fold } from '../segments/catalogue_browse.ts';
import { regionName } from './park_courses.ts';

export interface AnyTimeCourseKey {
	regionCode: string;
	parkName: string;
	courseName: string;
	slug: string;
	distanceM: number;
	status: string;
	/** Where the course starts; null when its geometry has no first point. */
	start: { lat: number; lng: number } | null;
}

export interface OrderedCourse<T> {
	course: T;
	/** Metres from the origin to the course start; null with no origin or start. */
	awayM: number | null;
}

function compareText(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

function compareStable(a: AnyTimeCourseKey, b: AnyTimeCourseKey): number {
	return (
		compareText(a.regionCode, b.regionCode) ||
		compareText(a.parkName, b.parkName) ||
		a.distanceM - b.distanceM ||
		compareText(a.courseName, b.courseName) ||
		compareText(a.slug, b.slug)
	);
}

/**
 * Courses in "Run any time" order. With an origin, by great-circle distance
 * from it to each course start, a course with no start after every course
 * that has one; without, by region, park, distance, then name. Closed
 * courses come last in both.
 */
export function orderAnyTimeCourses<T>(
	courses: readonly T[],
	key: (course: T) => AnyTimeCourseKey,
	origin: { lat: number; lng: number } | null,
): OrderedCourse<T>[] {
	const rows = courses.map((course) => {
		const k = key(course);
		const awayM =
			origin && k.start ? haversineMetres(origin.lat, origin.lng, k.start.lat, k.start.lng) : null;
		return { course, k, awayM };
	});
	rows.sort((a, b) => {
		const closed = Number(a.k.status === 'closed') - Number(b.k.status === 'closed');
		if (closed !== 0) return closed;
		if (origin) {
			if (a.awayM !== null && b.awayM !== null && a.awayM !== b.awayM) return a.awayM - b.awayM;
			if (a.awayM === null && b.awayM !== null) return 1;
			if (a.awayM !== null && b.awayM === null) return -1;
		}
		return compareStable(a.k, b.k);
	});
	return rows.map(({ course, awayM }) => ({ course, awayM }));
}

/**
 * The words of a park or park course search, folded the way the segment
 * catalogue's search folds (case and accents ignored). A blank query has
 * none, and no words match everything.
 */
export function parkSearchTerms(query: string): string[] {
	return fold(query)
		.split(/\s+/)
		.filter((t) => t.length > 0);
}

/**
 * Whether every one of `terms` is in the course's name, its park's name or
 * the park's place (the region's name or code), so "pocahontas 5k" and
 * "virginia beaver" both find a course. With no `courseName` it asks about
 * the park alone.
 */
export function parkSearchMatches(
	terms: readonly string[],
	target: { courseName?: string; parkName: string; regionCode: string },
): boolean {
	if (terms.length === 0) return true;
	const text = fold(
		[target.courseName ?? '', target.parkName, regionName(target.regionCode), target.regionCode].join(' '),
	);
	return terms.every((t) => text.includes(t));
}
