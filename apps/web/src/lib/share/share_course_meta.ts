/// Per-course `<head>` meta-tag + JSON-LD builders for the public park-course
/// page. Pure string helpers — used by the SvelteKit +page.svelte (dev-server
/// SSR) and the production entity-SSR Lambda.
///
/// The head is canonical English and names only the course and its park:
/// no runner, no time, no board (share_course_lookup reads none).

import { formatKmStable, normaliseSiteUrl } from './share_meta';
import { escapeHtml } from '../util/html_escape';
import { serialiseJsonLd } from '../util/json_ld';
import { collapseAndClip } from '../util/clip_text';
import { regionName } from '../parks/park_courses';
import { GUIDE_EN, routeGuideEnglish } from '../parks/route_guide';
import { courseShareKey, type SharedCourse } from './share_course_lookup';

const SITE_NAME = 'Threkir';

const SHAPE_WORD: Record<string, string> = {
	loop: 'loop',
	out_and_back: 'out-and-back',
	point_to_point: 'point-to-point',
};

export function buildCourseShareTitle(course: SharedCourse | null | undefined): string {
	if (!course) return `Park course — ${SITE_NAME}`;
	const name = collapseAndClip(course.segment.name, 70);
	const park = collapseAndClip(course.park.name, 60);
	return `${name} at ${park} — ${SITE_NAME}`;
}

export function buildCourseShareDescription(course: SharedCourse | null | undefined): string {
	if (!course) return `A standing time-trial course in a park, timed on ${SITE_NAME}.`;
	const km = formatKmStable(course.segment.distance_m);
	const shape = SHAPE_WORD[course.course_shape] ?? '';
	const what = [km, shape, 'course'].filter(Boolean).join(' ');
	const where = `${collapseAndClip(course.park.name, 60)}, ${regionName(course.park.region_code)}`;
	const lead = `${what.charAt(0).toUpperCase()}${what.slice(1)} at ${where}.`;
	if (course.status === 'closed') return `${lead} Currently closed.`;
	const body = `${lead} Run it any time: every run that covers it is timed on a yearly leaderboard.`;
	// A draft guide says so wherever the guide's text goes, search included.
	return course.route_guide && !course.route_guide_checked_at
		? `${body} Route guide: ${GUIDE_EN.pending.charAt(0).toLowerCase()}${GUIDE_EN.pending.slice(1)}`
		: body;
}

/// The course's route guide as one canonical-English paragraph, for the
/// JSON-LD description: the indexable text a written guide gives the page
/// (issue #1344). Empty when the course has none.
export function buildCourseGuideText(course: SharedCourse | null | undefined): string {
	if (!course?.route_guide) return '';
	return routeGuideEnglish(course.route_guide, course.route_guide_checked_at).join(' ');
}

export function buildCourseShareCanonical(
	base: string | null | undefined,
	key: string,
): string {
	return `${normaliseSiteUrl(base)}/share/course/${key}`;
}

/// schema.org JSON-LD for a park course: a `SportsActivityLocation` placed
/// at the course start, contained in its `Park`. Names and descriptions are
/// curated catalogue text, still escaped for the script-element context.
export function buildCourseJsonLd(
	course: SharedCourse | null | undefined,
	opts: { key: string; base: string | null | undefined },
): string {
	const base = normaliseSiteUrl(opts.base);
	const graph: Record<string, unknown> = {
		'@context': 'https://schema.org',
		'@type': 'SportsActivityLocation',
		name: collapseAndClip(course?.segment.name, 120) || 'Park course',
		description: [buildCourseShareDescription(course), buildCourseGuideText(course)].filter(Boolean).join(' '),
		url: buildCourseShareCanonical(base, opts.key),
	};
	const start = course?.segment.waypoints[0];
	if (start) {
		graph.geo = { '@type': 'GeoCoordinates', latitude: start.lat, longitude: start.lng };
	}
	if (course) {
		const park: Record<string, unknown> = {
			'@type': 'Park',
			name: collapseAndClip(course.park.name, 120),
			address: {
				'@type': 'PostalAddress',
				addressRegion: course.park.region_code,
				addressCountry: course.park.country_code,
			},
		};
		if (course.park.website_url?.startsWith('https://')) park.sameAs = course.park.website_url;
		graph.containedInPlace = park;
	}
	return serialiseJsonLd(graph);
}

export interface ShareCourseMetaInput {
	key: string;
	course: SharedCourse | null;
	siteUrl: string;
}

export interface ShareCourseHead {
	title: string;
	description: string;
	canonical: string;
	ogImageUrl: string;
	jsonLd: string;
}

export function buildShareCourseHead(input: ShareCourseMetaInput): ShareCourseHead {
	const { course, siteUrl } = input;
	// The canonical is rebuilt from the row's own slugs when there is one, so
	// a key that reached the row some other way still names one URL.
	const key = course
		? courseShareKey(course.park.region_code, course.park.slug, course.slug)
		: input.key;
	const base = normaliseSiteUrl(siteUrl);
	return {
		title: buildCourseShareTitle(course),
		description: buildCourseShareDescription(course),
		canonical: buildCourseShareCanonical(siteUrl, key),
		ogImageUrl: `${base}/og-default.png`,
		jsonLd: buildCourseJsonLd(course, { key, base: siteUrl }),
	};
}

export function renderShareCourseHeadTags(head: ShareCourseHead): string {
	const e = escapeHtml;
	return [
		`<title>${e(head.title)}</title>`,
		`<meta name="description" content="${e(head.description)}">`,
		`<link rel="canonical" href="${e(head.canonical)}">`,
		`<meta property="og:title" content="${e(head.title)}">`,
		`<meta property="og:description" content="${e(head.description)}">`,
		`<meta property="og:type" content="website">`,
		`<meta property="og:url" content="${e(head.canonical)}">`,
		`<meta property="og:image" content="${e(head.ogImageUrl)}">`,
		`<meta property="og:image:width" content="1200">`,
		`<meta property="og:image:height" content="630">`,
		`<meta property="og:site_name" content="Threkir">`,
		`<meta name="twitter:card" content="summary_large_image">`,
		`<meta name="twitter:title" content="${e(head.title)}">`,
		`<meta name="twitter:description" content="${e(head.description)}">`,
		`<meta name="twitter:image" content="${e(head.ogImageUrl)}">`,
		`<script type="application/ld+json">${head.jsonLd}</script>`,
	].join('\n\t');
}
