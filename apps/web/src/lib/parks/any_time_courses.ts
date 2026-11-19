/**
 * The order of the "Run any time" parks and park courses on the Races &
 * courses page (issue #1352). Nearest first when the page has a point to
 * measure from, otherwise a stable order that does not depend on where the
 * reader is. Either way what cannot be run sinks below what can. The section
 * lists parks; a course is listed on its own only when a search finds it by
 * its own name (decisions § 2550).
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

type LatLng = { lat: number; lng: number };

export interface AnyTimeParkKey {
	regionCode: string;
	parkName: string;
	slug: string;
	/** True when every course the park lists is closed. */
	allClosed: boolean;
	/** Its courses' starts, the points the park is measured by. */
	starts: readonly LatLng[];
	/** The park's own location, measured only when no course has a start. */
	location: LatLng | null;
}

export interface OrderedPark<T> {
	park: T;
	/** Metres from the origin to the park's nearest course start; null with no origin or point. */
	awayM: number | null;
}

function parkAwayM(origin: LatLng, k: AnyTimeParkKey): number | null {
	const points = k.starts.length > 0 ? k.starts : k.location ? [k.location] : [];
	let best: number | null = null;
	for (const p of points) {
		const d = haversineMetres(origin.lat, origin.lng, p.lat, p.lng);
		if (best === null || d < best) best = d;
	}
	return best;
}

/**
 * Parks in "Run any time" order: the course rule applied per park. With an
 * origin, by the distance to the park's nearest course start (its own
 * location when no course has one), a park with neither after every measured
 * one; without, by region then name. A park whose courses are all closed
 * comes last in both.
 */
export function orderAnyTimeParks<T>(
	parks: readonly T[],
	key: (park: T) => AnyTimeParkKey,
	origin: LatLng | null,
): OrderedPark<T>[] {
	const rows = parks.map((park) => {
		const k = key(park);
		return { park, k, awayM: origin ? parkAwayM(origin, k) : null };
	});
	rows.sort((a, b) => {
		const closed = Number(a.k.allClosed) - Number(b.k.allClosed);
		if (closed !== 0) return closed;
		if (origin) {
			if (a.awayM !== null && b.awayM !== null && a.awayM !== b.awayM) return a.awayM - b.awayM;
			if (a.awayM === null && b.awayM !== null) return 1;
			if (a.awayM !== null && b.awayM === null) return -1;
		}
		return (
			compareText(a.k.regionCode, b.k.regionCode) ||
			compareText(a.k.parkName, b.k.parkName) ||
			compareText(a.k.slug, b.k.slug)
		);
	});
	return rows.map(({ park, awayM }) => ({ park, awayM }));
}

export interface AnyTimeSearchView {
	parkId: string;
	courseName: string;
	parkName: string;
	regionCode: string;
}

export interface AnyTimeHits<C> {
	/** The parks to list, each once, in the order their first course came. */
	parkIds: string[];
	/** The courses to list on their own. */
	courses: C[];
}

/**
 * What "Run any time" lists for a search. With no words, every park and no
 * course on its own. With words, the parks whose own name or place matches,
 * plus each course that matches by its own name where its park does not, so
 * "beaver" finds Beaver Lake Trail and "pocahontas" finds the park, not its
 * six courses again.
 */
export function anyTimeSearchHits<C>(
	courses: readonly C[],
	view: (course: C) => AnyTimeSearchView,
	terms: readonly string[],
): AnyTimeHits<C> {
	const parkIds: string[] = [];
	const seen = new Set<string>();
	const hits: C[] = [];
	for (const c of courses) {
		const v = view(c);
		if (parkSearchMatches(terms, { parkName: v.parkName, regionCode: v.regionCode })) {
			if (!seen.has(v.parkId)) {
				seen.add(v.parkId);
				parkIds.push(v.parkId);
			}
		} else if (parkSearchMatches(terms, v)) {
			hits.push(c);
		}
	}
	return { parkIds, courses: hits };
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

const WORD_CHAR = /[\p{L}\p{N}]/u;

/**
 * Whether `term` starts a word somewhere in `text`: at its start, or after a
 * character that is neither a letter nor a digit. "belle" starts a word of
 * "belle isle state park" and "va" one of "us-va"; "ark" starts none, so it
 * does not find every park.
 */
function startsAWord(text: string, term: string): boolean {
	for (let i = text.indexOf(term); i !== -1; i = text.indexOf(term, i + 1)) {
		if (i === 0 || !WORD_CHAR.test(text[i - 1])) return true;
	}
	return false;
}

/**
 * Whether every one of `terms` starts a word of the course's name, its park's
 * name or the park's place (the region's name or code), so "pocahontas 5k",
 * "virginia beaver" and "swift cr" all find a course while "ark" does not
 * find every park. With no `courseName` it asks about the park alone. The
 * cases are `fixtures/park_search_cases.json`, read on both sides.
 */
export function parkSearchMatches(
	terms: readonly string[],
	target: { courseName?: string; parkName: string; regionCode: string },
): boolean {
	if (terms.length === 0) return true;
	const text = fold(
		[target.courseName ?? '', target.parkName, regionName(target.regionCode), target.regionCode].join(' '),
	);
	return terms.every((t) => startsAWord(text, t));
}
