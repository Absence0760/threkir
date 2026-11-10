/**
 * Park courses (issue #1313, decisions § 2383): the vocabularies the
 * `parks` / `park_courses` CHECK constraints allow, and the pure readers both
 * clients use on those rows.
 *
 * Parity pair with `apps/mobile_android/lib/park_courses.dart`
 * (docs/architecture/parity_pairs.md). The vocabularies are rails in
 * `apps/web/scripts/check_constraint_unions.mjs`.
 */

import { toRouteGpxWithMarkers, type GpxAttribution } from '../routes/route_gpx.ts';
import { routeGuideEnglish, type RouteGuide } from './route_guide.ts';

export const PARK_AGENCIES = ['nps', 'state', 'county', 'other'] as const;
export type ParkAgency = (typeof PARK_AGENCIES)[number];

export const COURSE_SHAPES = ['loop', 'out_and_back', 'point_to_point'] as const;
export type CourseShape = (typeof COURSE_SHAPES)[number];

export const COURSE_STATUSES = ['open', 'closed', 'seasonal'] as const;
export type CourseStatus = (typeof COURSE_STATUSES)[number];

export const GEOMETRY_SOURCES = ['osm', 'nps', 'agency', 'traced'] as const;
export type GeometrySource = (typeof GEOMETRY_SOURCES)[number];

export const COURSE_DIFFICULTIES = ['easy', 'moderate', 'hard'] as const;
export type CourseDifficulty = (typeof COURSE_DIFFICULTIES)[number];

export interface CourseCheckpoint {
	lat: number;
	lng: number;
}

/** The most checkpoints a course may carry; mirrors the CHECK constraint. */
export const MAX_COURSE_CHECKPOINTS = 50;

/**
 * Reads `park_courses.checkpoints`. Returns null — never a shorter list — when
 * the value is not an array or any entry is not a finite in-range lat/lng,
 * because a scorer handed a partial list would time a run that skipped the
 * dropped checkpoint. A caller that gets null must not score the course.
 */
export function parseCourseCheckpoints(raw: unknown): CourseCheckpoint[] | null {
	if (!Array.isArray(raw) || raw.length > MAX_COURSE_CHECKPOINTS) return null;
	const out: CourseCheckpoint[] = [];
	for (const entry of raw) {
		if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) return null;
		const { lat, lng } = entry as { lat?: unknown; lng?: unknown };
		if (typeof lat !== 'number' || typeof lng !== 'number') return null;
		if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
		if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
		out.push({ lat, lng });
	}
	return out;
}

/** `US-VA` → `us-va`, the region segment of `/parks/[region]/…`. */
export function regionSlug(regionCode: string): string {
	return regionCode.toLowerCase();
}

/** `us-va` → `US-VA`; null for anything that is not an ISO 3166-2 shape. */
export function regionCodeFromSlug(slug: string): string | null {
	const code = slug.toUpperCase();
	return /^[A-Z]{2}-[A-Z0-9]{1,3}$/.test(code) ? code : null;
}

/**
 * English names of the US subdivisions park courses launch in. A proper noun,
 * so it is not translated; a region outside the table shows its code.
 */
export const REGION_NAMES: Readonly<Record<string, string>> = {
	'US-AL': 'Alabama',
	'US-AK': 'Alaska',
	'US-AZ': 'Arizona',
	'US-AR': 'Arkansas',
	'US-CA': 'California',
	'US-CO': 'Colorado',
	'US-CT': 'Connecticut',
	'US-DE': 'Delaware',
	'US-DC': 'District of Columbia',
	'US-FL': 'Florida',
	'US-GA': 'Georgia',
	'US-HI': 'Hawaii',
	'US-ID': 'Idaho',
	'US-IL': 'Illinois',
	'US-IN': 'Indiana',
	'US-IA': 'Iowa',
	'US-KS': 'Kansas',
	'US-KY': 'Kentucky',
	'US-LA': 'Louisiana',
	'US-ME': 'Maine',
	'US-MD': 'Maryland',
	'US-MA': 'Massachusetts',
	'US-MI': 'Michigan',
	'US-MN': 'Minnesota',
	'US-MS': 'Mississippi',
	'US-MO': 'Missouri',
	'US-MT': 'Montana',
	'US-NE': 'Nebraska',
	'US-NV': 'Nevada',
	'US-NH': 'New Hampshire',
	'US-NJ': 'New Jersey',
	'US-NM': 'New Mexico',
	'US-NY': 'New York',
	'US-NC': 'North Carolina',
	'US-ND': 'North Dakota',
	'US-OH': 'Ohio',
	'US-OK': 'Oklahoma',
	'US-OR': 'Oregon',
	'US-PA': 'Pennsylvania',
	'US-RI': 'Rhode Island',
	'US-SC': 'South Carolina',
	'US-SD': 'South Dakota',
	'US-TN': 'Tennessee',
	'US-TX': 'Texas',
	'US-UT': 'Utah',
	'US-VT': 'Vermont',
	'US-VA': 'Virginia',
	'US-WA': 'Washington',
	'US-WV': 'West Virginia',
	'US-WI': 'Wisconsin',
	'US-WY': 'Wyoming',
};

export function regionName(regionCode: string): string {
	return REGION_NAMES[regionCode] ?? regionCode;
}

/**
 * Whether a course counts toward collections (passport, "courses run") right
 * now. A closed course keeps its efforts and boards but drops out of counts
 * while it is closed; a seasonal one still counts.
 */
export function courseIsCountable(status: string): boolean {
	return status === 'open' || status === 'seasonal';
}

/** Courses longer than this carry the long-course notice. */
export const LONG_COURSE_THRESHOLD_M = 15000;

/** Whether a course is long enough to show the long-course notice. */
export function isLongCourse(distanceM: number): boolean {
	return Number.isFinite(distanceM) && distanceM > LONG_COURSE_THRESHOLD_M;
}

/**
 * Groups parks by region code, regions in code order and parks by name within
 * each, for the `/parks` index.
 */
export function groupParksByRegion<T extends { region_code: string; name: string }>(
	parks: readonly T[],
): { regionCode: string; parks: T[] }[] {
	const byRegion = new Map<string, T[]>();
	for (const park of parks) {
		const list = byRegion.get(park.region_code);
		if (list) list.push(park);
		else byRegion.set(park.region_code, [park]);
	}
	return [...byRegion.keys()]
		.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0))
		.map((regionCode) => ({
			regionCode,
			parks: byRegion
				.get(regionCode)!
				.slice()
				.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)),
		}));
}

const OSM_ATTRIBUTION: GpxAttribution = {
	notice:
		'Course line © OpenStreetMap contributors, available under the Open Database License (ODbL).',
	author: 'OpenStreetMap contributors',
	licenseUrl: 'https://opendatacommons.org/licenses/odbl/1-0/',
	linkHref: 'https://www.openstreetmap.org/copyright',
	linkText: '© OpenStreetMap contributors',
};

const NPS_ATTRIBUTION: GpxAttribution = {
	notice: 'Course line from National Park Service trail data.',
	author: 'National Park Service',
	licenseUrl: null,
	linkHref: 'https://www.nps.gov/',
	linkText: 'National Park Service',
};

/**
 * The credit an exported course file carries, from the course's
 * `geometry_source` and its park. Canonical English, like every other GPX
 * `<desc>` the app writes, so the file is the same whoever downloads it.
 * Null for a value outside the vocabulary: the CHECK constraint makes that
 * unreachable for a stored course, and a caller with no course passes null.
 * A park the reader cannot see (pulled) still yields a credit, unnamed.
 *
 * `osm` names the ODbL and links OpenStreetMap's copyright page, which is
 * what its licence asks of a produced work. `nps` credits the National Park
 * Service whatever licence a given dataset states. `agency` credits the park
 * and links its own site; `traced` was drawn by us, so it names no rights
 * holder and only says what it was traced against.
 */
export function courseAttribution(
	geometrySource: string | null | undefined,
	park: { name: string; websiteUrl: string | null } | null,
): GpxAttribution | null {
	const name = park?.name ?? null;
	const website = park?.websiteUrl?.startsWith('https://') ? park.websiteUrl : null;
	switch (geometrySource) {
		case 'osm':
			return OSM_ATTRIBUTION;
		case 'nps':
			return NPS_ATTRIBUTION;
		case 'agency':
			return {
				notice: `Course line from trail data published by ${name ?? 'the park'}.`,
				author: name,
				licenseUrl: null,
				linkHref: website,
				linkText: name ?? website ?? '',
			};
		case 'traced':
			return {
				notice: `Course line traced against the published trail map of ${name ?? 'the park'}.`,
				author: null,
				licenseUrl: null,
				linkHref: website,
				linkText: name ?? website ?? '',
			};
		default:
			return null;
	}
}

/**
 * The GPX a course page downloads: the course line, one `<wpt>` per
 * checkpoint in order (so a watch shows the points a run must pass), the
 * geometry credit in `<metadata>`, and the route guide as the track's
 * `<desc>`, in canonical English and led by whether it has been checked on
 * the ground. A checkpoint list that could not be read (null) writes no
 * waypoints rather than a partial set.
 */
export function parkCourseGpx(input: {
	name: string;
	waypoints: readonly { lat: number; lng: number; ele?: number | null }[];
	checkpoints: readonly CourseCheckpoint[] | null;
	attribution: GpxAttribution | null;
	guide?: { guide: RouteGuide; checkedAt: string | null } | null;
}): string {
	return toRouteGpxWithMarkers(
		input.name,
		input.waypoints.map((w) => [w.lng, w.lat]),
		input.waypoints.map((w) => w.ele ?? 0),
		(input.checkpoints ?? []).map((c, i) => ({
			label: `Checkpoint ${i + 1}`,
			lat: c.lat,
			lng: c.lng,
			kind: 'checkpoint',
			meta: {},
		})),
		input.attribution,
		input.guide ? routeGuideEnglish(input.guide.guide, input.guide.checkedAt).join('\n') : null,
	);
}

/** One park course effort in a recap period, joined to its course and park. */
export interface RecapParkRow {
	parkId: string;
	parkName: string;
	regionCode: string;
	courseId: string;
}

export interface RecapParkSummary {
	courseCount: number;
	parkCount: number;
	/** Most courses first, then by name. */
	parks: { parkId: string; name: string; regionCode: string; courseCount: number }[];
}

/**
 * What a recap says about park courses: distinct courses, distinct parks and
 * each park with its distinct course count. A course run twice counts once.
 */
export function recapParkSummary(rows: readonly RecapParkRow[]): RecapParkSummary {
	const courses = new Set<string>();
	const byPark = new Map<string, { parkId: string; name: string; regionCode: string; courses: Set<string> }>();
	for (const r of rows) {
		courses.add(r.courseId);
		let park = byPark.get(r.parkId);
		if (!park) {
			park = { parkId: r.parkId, name: r.parkName, regionCode: r.regionCode, courses: new Set() };
			byPark.set(r.parkId, park);
		}
		park.courses.add(r.courseId);
	}
	const parks = [...byPark.values()]
		.map((p) => ({ parkId: p.parkId, name: p.name, regionCode: p.regionCode, courseCount: p.courses.size }))
		.sort((a, b) => b.courseCount - a.courseCount || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
	return { courseCount: courses.size, parkCount: byPark.size, parks };
}

/** A park course time on one run, as `run_park_course_times` returns it. */
export interface RunParkCourseTime {
	effort_id: string;
	course_name: string;
	course_slug: string;
	park_name: string;
	park_slug: string;
	region_code: string;
	time_seconds: number;
	season: number;
	season_rank: number | null;
}

/**
 * The course a run's share sticker prints: the best-ranked of its park course
 * times this season, or the first when none is ranked; null when the run
 * completed no park course.
 */
export function pickShareCourse<T extends RunParkCourseTime>(rows: readonly T[]): T | null {
	let best: T | null = null;
	for (const r of rows) {
		if (r.season_rank == null) continue;
		if (best === null || r.season_rank < (best.season_rank as number)) best = r;
	}
	return best ?? rows[0] ?? null;
}
