/// Single source of truth for the public park-course fetch shape.
/// Used by both:
///   - apps/web/src/routes/share/course/[region]/[park]/[course]/+page.ts
///     (dev-server SSR).
///   - the production entity-SSR Lambda that owns /share/course/*.
///
/// Keyed by `<region>/<park>/<course>` — the same three slugs as the in-app
/// /parks/[region]/[park]/[course] URL — so the indexable URL reads like the
/// place it names. `parks`, `park_courses` and `global_segments` all grant
/// select to anon (migration 20271115002383), and RLS hides an inactive park,
/// its courses and a pulled segment, which the inner joins below turn into a
/// clean not-found.
///
/// Nothing about a runner is read here. The boards are signed-in only, and a
/// list of named runners is the people-directory objection that keeps
/// profiles out of the index (seo.md), so the crawler surface is the course.

import { createClient } from '@supabase/supabase-js';
import { thrownMessage } from '../core/supabase_error';
import { regionCodeFromSlug } from '../parks/park_courses';
import { parseRouteGuide, type RouteGuide } from '../parks/route_guide';
import { TABLES } from '../core/schema';

export interface SharedCoursePoint {
	lat: number;
	lng: number;
	ele: number | null;
}

export interface SharedCourse {
	slug: string;
	course_shape: string;
	status: string;
	status_note: string | null;
	geometry_source: string;
	difficulty: string | null;
	/** Laps of the loop in one timed effort; null when laps do not apply. */
	laps: number | null;
	/** The source credit, verbatim (`park_courses.attribution`, decisions § 2438). */
	attribution: string | null;
	/** The route guide, or null when there is none or it cannot be read (`parseRouteGuide`). */
	route_guide: RouteGuide | null;
	/** The day the guide was checked on the ground (YYYY-MM-DD); null while it is a draft. */
	route_guide_checked_at: string | null;
	segment: {
		name: string;
		description: string | null;
		distance_m: number;
		elevation_m: number | null;
		surface: string | null;
		waypoints: SharedCoursePoint[];
	};
	park: {
		slug: string;
		name: string;
		region_code: string;
		country_code: string;
		agency: string;
		website_url: string | null;
	};
}

export interface SharedCourseLookup {
	course: SharedCourse | null;
}

export interface SharedCourseLookupConfig {
	supabaseUrl: string;
	supabaseAnonKey: string;
}

const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

/// `us-va/fixture-state-park/lake-loop` → its three parts, or null when the
/// key is not three well-formed slugs. A malformed key is a quiet not-found
/// that never reaches PostgREST, like the uuid-keyed lookups' `isEntityId`.
export function parseCourseKey(
	key: string,
): { regionCode: string; region: string; park: string; course: string } | null {
	const parts = key.split('/');
	if (parts.length !== 3) return null;
	const [region, park, course] = parts;
	if (!SLUG.test(park) || !SLUG.test(course) || park.length > 80 || course.length > 80) {
		return null;
	}
	if (region !== region.toLowerCase()) return null;
	const regionCode = regionCodeFromSlug(region);
	if (!regionCode) return null;
	return { regionCode, region, park, course };
}

/// The path segment after `/share/course/` for a course.
export function courseShareKey(regionCode: string, parkSlug: string, courseSlug: string): string {
	return `${regionCode.toLowerCase()}/${parkSlug}/${courseSlug}`;
}

function readPoints(raw: unknown): SharedCoursePoint[] {
	if (!Array.isArray(raw)) return [];
	const out: SharedCoursePoint[] = [];
	for (const p of raw) {
		if (p === null || typeof p !== 'object') continue;
		const { lat, lng, ele } = p as { lat?: unknown; lng?: unknown; ele?: unknown };
		if (typeof lat !== 'number' || typeof lng !== 'number') continue;
		if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue;
		out.push({ lat, lng, ele: typeof ele === 'number' && Number.isFinite(ele) ? ele : null });
	}
	return out;
}

export async function lookupSharedCourse(
	key: string,
	config: SharedCourseLookupConfig | null,
): Promise<SharedCourseLookup> {
	if (!config?.supabaseUrl || !config?.supabaseAnonKey) {
		return { course: null };
	}
	const parsed = parseCourseKey(key);
	if (!parsed) return { course: null };
	try {
		const supabase = createClient(config.supabaseUrl, config.supabaseAnonKey, {
			auth: { persistSession: false },
		});
		const { data, error } = await supabase
			.from(TABLES.park_courses)
			.select(
				'slug, course_shape, status, status_note, geometry_source, difficulty, laps, attribution, ' +
					'route_guide, route_guide_checked_at, ' +
					'global_segments!inner(name, description, distance_m, elevation_m, surface, waypoints), ' +
					'parks!inner(slug, name, region_code, country_code, agency, website_url)',
			)
			.eq('slug', parsed.course)
			.eq('parks.slug', parsed.park)
			.eq('parks.region_code', parsed.regionCode)
			.maybeSingle();
		if (error) {
			console.error('[share-course] upstream_unreachable');
			return { course: null };
		}
		if (!data) return { course: null };
		const r = data as unknown as Record<string, unknown>;
		const seg = r.global_segments as Record<string, unknown> | null;
		const park = r.parks as Record<string, unknown> | null;
		if (!seg || !park) return { course: null };
		return {
			course: {
				slug: r.slug as string,
				course_shape: r.course_shape as string,
				status: r.status as string,
				status_note: (r.status_note as string | null) ?? null,
				geometry_source: r.geometry_source as string,
				difficulty: (r.difficulty as string | null) ?? null,
				laps: typeof r.laps === 'number' && Number.isInteger(r.laps) && r.laps >= 1 ? r.laps : null,
				attribution:
					typeof r.attribution === 'string' && r.attribution.trim() ? r.attribution.trim() : null,
				route_guide: parseRouteGuide(r.route_guide),
				route_guide_checked_at:
					typeof r.route_guide_checked_at === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(r.route_guide_checked_at)
						? r.route_guide_checked_at
						: null,
				segment: {
					name: (seg.name as string) ?? '',
					description: (seg.description as string | null) ?? null,
					distance_m: Number(seg.distance_m) || 0,
					elevation_m: seg.elevation_m == null ? null : Number(seg.elevation_m),
					surface: (seg.surface as string | null) ?? null,
					waypoints: readPoints(seg.waypoints),
				},
				park: {
					slug: park.slug as string,
					name: (park.name as string) ?? '',
					region_code: park.region_code as string,
					country_code: park.country_code as string,
					agency: park.agency as string,
					website_url: (park.website_url as string | null) ?? null,
				},
			},
		};
	} catch (err) {
		console.error('[share-course] upstream_unreachable', thrownMessage(err));
		return { course: null };
	}
}
