// Pure logic for multi-course races (clubs.md § Live race mode, decisions
// § 1842): ordering an event's courses, diffing the editor's draft list into
// the writes that reach `event_courses`, splitting a results list into one
// leaderboard per course, and the finish-method badge a result carries.

import type { FinishMethod } from '../types';

export interface EventCourse {
	id: string;
	event_id: string;
	route_id: string | null;
	name: string;
	distance_m: number | null;
	sort_order: number;
}

/// One row of the event editor's course list. `id` is set for a course that
/// already exists, absent for one added in this edit.
export interface CourseDraft {
	id?: string;
	name: string;
	routeId: string | null;
	distanceM: number | null;
}

/// Mirrors `event_courses_name_len_chk` (1-120 chars after trimming).
export const COURSE_NAME_MAX = 120;
/// Mirrors `event_courses_distance_m_check` (0 < d <= 1,000 km).
export const COURSE_DISTANCE_MAX_M = 1_000_000;

export function sortCourses<T extends Pick<EventCourse, 'sort_order' | 'name'>>(courses: T[]): T[] {
	return [...courses].sort(
		(a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name)
	);
}

/// A racer must pick a course only when there is a choice to make. The server
/// enforces the same rule on a going / waitlisted RSVP.
export function needsCoursePick(courses: readonly unknown[]): boolean {
	return courses.length > 1;
}

export type CourseDraftError = 'name_required' | 'name_too_long' | 'name_duplicate' | 'distance_invalid';

/// The first problem with a draft list, keyed by the offending row, or null.
export function validateCourseDrafts(
	drafts: readonly CourseDraft[]
): { index: number; error: CourseDraftError } | null {
	const seen = new Set<string>();
	for (let i = 0; i < drafts.length; i++) {
		const name = drafts[i].name.trim();
		if (name.length === 0) return { index: i, error: 'name_required' };
		if (name.length > COURSE_NAME_MAX) return { index: i, error: 'name_too_long' };
		const key = name.toLocaleLowerCase();
		if (seen.has(key)) return { index: i, error: 'name_duplicate' };
		seen.add(key);
		const d = drafts[i].distanceM;
		if (d !== null && !(Number.isFinite(d) && d > 0 && d <= COURSE_DISTANCE_MAX_M)) {
			return { index: i, error: 'distance_invalid' };
		}
	}
	return null;
}

export interface CourseWrite {
	name: string;
	route_id: string | null;
	distance_m: number | null;
	sort_order: number;
}

export interface CourseSavePlan {
	inserts: CourseWrite[];
	updates: { id: string; patch: CourseWrite }[];
	deletes: string[];
}

/// Diff the editor's drafts against what is stored. A draft's position is its
/// sort_order, so a reorder is an update; an existing row the drafts no longer
/// name is a delete; an unchanged row produces no write at all.
export function planCourseSave(
	existing: readonly EventCourse[],
	drafts: readonly CourseDraft[]
): CourseSavePlan {
	const byId = new Map(existing.map((c) => [c.id, c]));
	const kept = new Set<string>();
	const plan: CourseSavePlan = { inserts: [], updates: [], deletes: [] };
	drafts.forEach((d, i) => {
		const write: CourseWrite = {
			name: d.name.trim(),
			route_id: d.routeId,
			distance_m: d.distanceM,
			sort_order: i
		};
		const prior = d.id ? byId.get(d.id) : undefined;
		if (!prior) {
			plan.inserts.push(write);
			return;
		}
		kept.add(prior.id);
		if (
			prior.name !== write.name ||
			prior.route_id !== write.route_id ||
			prior.distance_m !== write.distance_m ||
			prior.sort_order !== write.sort_order
		) {
			plan.updates.push({ id: prior.id, patch: write });
		}
	});
	for (const c of existing) if (!kept.has(c.id)) plan.deletes.push(c.id);
	return plan;
}

export interface CourseBoard<R> {
	course: EventCourse | null;
	results: R[];
}

/// One leaderboard per course, in course order, each keeping the input's
/// order (the fetch already sorts by rank). A result whose course is unknown
/// or null — a pre-course row, or one whose course was deleted — lands in a
/// trailing course-less board, shown only when it has rows. An event with no
/// courses is a single course-less board, so a plain club run renders as it
/// always did. A course with no results still gets an (empty) board so the
/// page can say nobody has finished it yet.
export function groupResultsByCourse<R extends { course_id: string | null }>(
	results: readonly R[],
	courses: readonly EventCourse[]
): CourseBoard<R>[] {
	const ordered = sortCourses([...courses]);
	if (ordered.length === 0) return [{ course: null, results: [...results] }];
	const boards = new Map<string, CourseBoard<R>>(
		ordered.map((c) => [c.id, { course: c, results: [] as R[] }])
	);
	const orphans: R[] = [];
	for (const r of results) {
		const board = r.course_id ? boards.get(r.course_id) : undefined;
		if (board) board.results.push(r);
		else orphans.push(r);
	}
	const out = [...boards.values()];
	if (orphans.length > 0) out.push({ course: null, results: orphans });
	return out;
}

/// The badge a leaderboard row wears. A device-detected finish (`auto`) and a
/// row from before finish methods existed (null) wear none: the badge exists
/// to flag a time that was NOT measured by the finish rule.
export function finishMethodBadge(method: FinishMethod | null): 'manual' | 'host' | null {
	return method === 'manual' || method === 'host' ? method : null;
}

/// The columns an organiser's time edit writes. `duration_s` is the ranked
/// time; on a race that had a GO it IS the gun time, so the gun time moves
/// with it and the chip time (the device's own clock) is left as measured.
export function hostTimeEditPatch(
	durationS: number,
	raceHadGun: boolean
): { duration_s: number; gun_time_s?: number } {
	const d = Math.max(0, Math.round(durationS));
	return raceHadGun ? { duration_s: d, gun_time_s: d } : { duration_s: d };
}
