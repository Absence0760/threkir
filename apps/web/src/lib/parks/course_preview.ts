/**
 * The park page's course preview: which course `?course=` selects, the
 * address that selects another, where the map frames, and the one sentence
 * that says where to start. Pure, so the page's selection logic tests
 * without a browser. Web-only: the phone previews in a bottom sheet and
 * keeps nothing in an address.
 */

import { formatGuideLine, routeGuideLines, type GuideFormat, type RouteGuide } from './route_guide.ts';

export const COURSE_PARAM = 'course';

/** The slug `?course=` names, when the park has a course by that slug. */
export function selectedCourseSlug(search: string, slugs: readonly string[]): string | null {
	const raw = new URLSearchParams(search).get(COURSE_PARAM);
	return raw !== null && slugs.includes(raw) ? raw : null;
}

/** `search` with `course` set to `slug`, or removed for null; every other parameter kept. */
export function courseSearch(search: string, slug: string | null): string {
	const params = new URLSearchParams(search);
	if (slug === null) params.delete(COURSE_PARAM);
	else params.set(COURSE_PARAM, slug);
	const rest = params.toString();
	return rest ? `?${rest}` : '';
}

export interface LatLngPoint {
	lat: number;
	lng: number;
}

/** `[[west, south], [east, north]]` around every real point, or null when there is none. */
export function boundsOf(lines: readonly (readonly LatLngPoint[])[]): [[number, number], [number, number]] | null {
	let w = Infinity;
	let s = Infinity;
	let e = -Infinity;
	let n = -Infinity;
	for (const line of lines) {
		for (const p of line) {
			if (!Number.isFinite(p.lat) || !Number.isFinite(p.lng)) continue;
			if (Math.abs(p.lat) > 90 || Math.abs(p.lng) > 180) continue;
			// A null coordinate read through `Number()` lands on 0, 0.
			if (p.lat === 0 && p.lng === 0) continue;
			w = Math.min(w, p.lng);
			e = Math.max(e, p.lng);
			s = Math.min(s, p.lat);
			n = Math.max(n, p.lat);
		}
	}
	return Number.isFinite(w) ? [[w, s], [e, n]] : null;
}

export interface StartSentence {
	text: string;
	/** The guide's own language for its free-text note; null when the line is in the reader's. */
	lang: string | null;
}

/**
 * Where to start, in one plain sentence: the guide's own "getting there"
 * note when it has one ("Start at the boat-ramp lot."), else its first line
 * ("Start on the Lake Trail."). Null without a guide.
 */
export function startSentence(guide: RouteGuide | null, fmt: GuideFormat): StartSentence | null {
	if (!guide) return null;
	if (guide.gettingThere) return { text: guide.gettingThere, lang: guide.lang };
	const first = routeGuideLines(guide)[0];
	return first ? { text: formatGuideLine(first, fmt), lang: null } : null;
}
