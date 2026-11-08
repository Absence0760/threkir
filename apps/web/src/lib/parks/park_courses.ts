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
 * checkpoint in order (so a watch shows the points a run must pass), and the
 * geometry credit in `<metadata>`. A checkpoint list that could not be read
 * (null) writes no waypoints rather than a partial set.
 */
export function parkCourseGpx(input: {
	name: string;
	waypoints: readonly { lat: number; lng: number; ele?: number | null }[];
	checkpoints: readonly CourseCheckpoint[] | null;
	attribution: GpxAttribution | null;
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
	);
}
