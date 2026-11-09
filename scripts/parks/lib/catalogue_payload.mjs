// Turns a park's built `manifest.json` and course GeoJSON into the payload
// `private.load_park_catalogue` takes (migration 20271126002425, decisions
// § 2425), and that payload into the one SQL statement the operator runs.
// Pure: the CLI in ../load.mjs does the file reads.
//
// Everything the database would refuse is refused here first, with the course
// named, so a bad manifest fails on the operator's machine rather than half way
// through a production transaction.

import { RACE_DISTANCES_M, haversineM, pathLengthM } from './course_geometry.mjs';

/** @typedef {import('./course_geometry.mjs').LatLng} LatLng */

export const PARK_AGENCIES = ['nps', 'state', 'county', 'other'];
export const COURSE_SHAPES = ['loop', 'out_and_back', 'point_to_point'];
export const GEOMETRY_SOURCES = ['osm', 'nps', 'agency', 'traced'];
export const COURSE_DIFFICULTIES = ['easy', 'moderate', 'hard'];
export const ROUTE_SURFACES = ['road', 'trail', 'mixed'];

export const MAX_CHECKPOINTS = 50;
export const MAX_SOURCE_REF_LENGTH = 8000;

/** A loop's line must close within this; the build closes it exactly. */
export const LOOP_CLOSE_M = 25;

/** The line in the GeoJSON must measure within this of the manifest's distance. */
export const LINE_DISTANCE_TOLERANCE = 0.01;

/** A curated line sits on its end of the course line; the build places it there exactly. */
export const CURATED_GATE_FROM_END_M = 5;

const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

/** @type {Readonly<Record<string, string>>} */
const US_STATES = Object.freeze({
	AL: 'Alabama', AK: 'Alaska', AZ: 'Arizona', AR: 'Arkansas', CA: 'California', CO: 'Colorado',
	CT: 'Connecticut', DE: 'Delaware', DC: 'District of Columbia', FL: 'Florida', GA: 'Georgia',
	HI: 'Hawaii', ID: 'Idaho', IL: 'Illinois', IN: 'Indiana', IA: 'Iowa', KS: 'Kansas',
	KY: 'Kentucky', LA: 'Louisiana', ME: 'Maine', MD: 'Maryland', MA: 'Massachusetts',
	MI: 'Michigan', MN: 'Minnesota', MS: 'Mississippi', MO: 'Missouri', MT: 'Montana',
	NE: 'Nebraska', NV: 'Nevada', NH: 'New Hampshire', NJ: 'New Jersey', NM: 'New Mexico',
	NY: 'New York', NC: 'North Carolina', ND: 'North Dakota', OH: 'Ohio', OK: 'Oklahoma',
	OR: 'Oregon', PA: 'Pennsylvania', RI: 'Rhode Island', SC: 'South Carolina',
	SD: 'South Dakota', TN: 'Tennessee', TX: 'Texas', UT: 'Utah', VT: 'Vermont', VA: 'Virginia',
	WA: 'Washington', WV: 'West Virginia', WI: 'Wisconsin', WY: 'Wyoming',
});

/** @type {Readonly<Record<string, string>>} */
const RACE_DISTANCE_WORDS = Object.freeze({
	'5k': '5 km',
	'10k': '10 km',
	half: 'the half-marathon distance (21.1 km)',
	marathon: 'the marathon distance (42.2 km)',
	'50k': '50 km',
});

/**
 * @typedef {{
 *   slug: string, name: string, course_shape: string, surface: string, difficulty: string | null,
 *   geometry_source: string, source_ref: string | null, source_checked_at: string | null,
 *   distance_m: number, elevation_m: number | null, official_distance_m: number | null,
 *   description: string | null, checkpoints: { lat: number, lng: number }[], waypoints: LatLng[],
 *   start_gate: PayloadGate | null, end_gate: PayloadGate | null,
 * }} PayloadCourse
 * @typedef {{ lat: number, lng: number, bearing_deg: number, half_width_m: number }} PayloadGate
 * @typedef {{
 *   park: Record<string, string | null>, region: string, attribution: string, courses: PayloadCourse[],
 * }} CataloguePayload
 */

/**
 * @param {boolean} cond
 * @param {string} message
 * @returns {asserts cond}
 */
function check(cond, message) {
	if (!cond) throw new Error(message);
}

/** @param {unknown} v */
const isFiniteNumber = (v) => typeof v === 'number' && Number.isFinite(v);

/**
 * @param {unknown} lat
 * @param {unknown} lng
 */
const inRange = (lat, lng) =>
	isFiniteNumber(lat) && isFiniteNumber(lng) && Math.abs(Number(lat)) <= 90 && Math.abs(Number(lng)) <= 180;

/**
 * The course line from a built GeoJSON: its one LineString, as `[lng, lat, ele?]`.
 *
 * @param {any} geojson
 * @param {string} slug
 * @returns {LatLng[]}
 */
export function courseLine(geojson, slug) {
	check(geojson?.type === 'FeatureCollection' && Array.isArray(geojson.features), `${slug}: the GeoJSON is not a FeatureCollection`);
	const lines = geojson.features.filter((/** @type {any} */ f) => f?.geometry?.type === 'LineString');
	check(lines.length === 1, `${slug}: the GeoJSON must hold exactly one LineString, found ${lines.length}`);
	const coords = lines[0].geometry.coordinates;
	check(Array.isArray(coords) && coords.length >= 2, `${slug}: the course line needs at least two points`);
	return coords.map((/** @type {any} */ c, /** @type {number} */ i) => {
		check(Array.isArray(c) && inRange(c[1], c[0]), `${slug}: point ${i} of the course line is not a [lng, lat] in range`);
		check(c[2] == null || isFiniteNumber(c[2]), `${slug}: point ${i} has an elevation that is not a number`);
		return c[2] == null ? { lat: c[1], lng: c[0] } : { lat: c[1], lng: c[0], ele: c[2] };
	});
}

/**
 * A curated start or end line from the manifest, in the shape the segment's
 * `*_gate_*` columns take, or null when the course has none at that end.
 *
 * @param {any} gate
 * @param {LatLng} end the course line's point at that end
 * @param {string} where e.g. `swift-creek-10k: start_gate`
 * @returns {PayloadGate | null}
 */
function curatedGate(gate, end, where) {
	if (gate == null) return null;
	check(typeof gate === 'object' && !Array.isArray(gate), `${where} must be an object`);
	const keys = Object.keys(gate).sort().join(',');
	check(keys === 'bearing_deg,half_width_m,lat,lng', `${where} must hold exactly lat, lng, bearing_deg and half_width_m, got ${keys}`);
	check(inRange(gate.lat, gate.lng), `${where} is not a lat and lng in range`);
	check(isFiniteNumber(gate.bearing_deg) && gate.bearing_deg >= 0 && gate.bearing_deg < 360, `${where} bearing_deg must be in [0, 360)`);
	check(isFiniteNumber(gate.half_width_m) && gate.half_width_m >= 5 && gate.half_width_m <= 100, `${where} half_width_m must be 5-100`);
	const off = haversineM(gate, end);
	check(off <= CURATED_GATE_FROM_END_M, `${where} sits ${off.toFixed(1)} m from its end of the course line, over ${CURATED_GATE_FROM_END_M} m; rebuild it`);
	return { lat: gate.lat, lng: gate.lng, bearing_deg: gate.bearing_deg, half_width_m: gate.half_width_m };
}

/**
 * @param {any} entry
 * @param {LatLng[]} line
 * @param {{ course_shape: string, difficulty: string | null, official_distance_m: number | null, description: string | null }} shape
 * @returns {PayloadCourse}
 */
function payloadCourse(entry, line, shape) {
	const slug = String(entry.slug);
	check(typeof entry.name === 'string' && entry.name.length >= 1 && entry.name.length <= 120, `${slug}: name must be 1-120 characters`);
	check(COURSE_SHAPES.includes(shape.course_shape), `${slug}: course_shape ${shape.course_shape} is not one of ${COURSE_SHAPES.join(', ')}`);
	check(ROUTE_SURFACES.includes(entry.surface), `${slug}: surface ${entry.surface} is not one of ${ROUTE_SURFACES.join(', ')}`);
	check(
		shape.difficulty === null || COURSE_DIFFICULTIES.includes(shape.difficulty),
		`${slug}: difficulty ${shape.difficulty} is not one of ${COURSE_DIFFICULTIES.join(', ')}`,
	);
	check(GEOMETRY_SOURCES.includes(entry.geometry_source), `${slug}: geometry_source ${entry.geometry_source} is not one of ${GEOMETRY_SOURCES.join(', ')}`);
	check(
		entry.source_ref == null || (typeof entry.source_ref === 'string' && entry.source_ref.length <= MAX_SOURCE_REF_LENGTH),
		`${slug}: source_ref is longer than ${MAX_SOURCE_REF_LENGTH} characters`,
	);
	check(entry.source_checked_at == null || DATE.test(entry.source_checked_at), `${slug}: source_checked_at must be YYYY-MM-DD`);
	check(isFiniteNumber(entry.distance_m) && entry.distance_m >= 100, `${slug}: distance_m must be at least 100`);
	check(entry.elevation_m == null || (isFiniteNumber(entry.elevation_m) && entry.elevation_m >= 0), `${slug}: elevation_m must be a non-negative number`);

	const checkpoints = entry.checkpoints ?? [];
	check(Array.isArray(checkpoints) && checkpoints.length <= MAX_CHECKPOINTS, `${slug}: at most ${MAX_CHECKPOINTS} checkpoints`);
	checkpoints.forEach((/** @type {any} */ c, /** @type {number} */ i) =>
		check(inRange(c?.lat, c?.lng), `${slug}: checkpoint ${i + 1} is not a lat and lng in range`),
	);

	if (entry.waypoint_count !== undefined) {
		check(line.length === entry.waypoint_count, `${slug}: the GeoJSON has ${line.length} points, the manifest says ${entry.waypoint_count}; rebuild it`);
	}
	const lineM = pathLengthM(line);
	check(
		Math.abs(lineM / entry.distance_m - 1) <= LINE_DISTANCE_TOLERANCE,
		`${slug}: the GeoJSON line measures ${lineM.toFixed(0)} m against the manifest's ${entry.distance_m} m; rebuild it`,
	);
	if (shape.course_shape === 'loop') {
		const gap = haversineM(line[0], line[line.length - 1]);
		check(gap <= LOOP_CLOSE_M, `${slug}: a loop must start and finish together, its ends are ${gap.toFixed(0)} m apart`);
	}

	return {
		slug,
		name: entry.name,
		course_shape: shape.course_shape,
		surface: entry.surface,
		difficulty: shape.difficulty,
		geometry_source: entry.geometry_source,
		source_ref: entry.source_ref ?? null,
		source_checked_at: entry.source_checked_at ?? null,
		distance_m: entry.distance_m,
		elevation_m: entry.elevation_m ?? null,
		official_distance_m: shape.official_distance_m,
		description: shape.description,
		checkpoints: checkpoints.map((/** @type {{ lat: number, lng: number }} */ c) => ({ lat: c.lat, lng: c.lng })),
		waypoints: line,
		start_gate: curatedGate(entry.start_gate, line[0], `${slug}: start_gate`),
		end_gate: curatedGate(entry.end_gate, line[line.length - 1], `${slug}: end_gate`),
	};
}

/**
 * @param {any} manifest the park's built `manifest.json`
 * @param {(file: string) => any} readGeojson reads a course's GeoJSON by its manifest file name
 * @returns {CataloguePayload}
 */
export function cataloguePayload(manifest, readGeojson) {
	const park = manifest?.park;
	check(park && typeof park === 'object', 'the manifest has no park');
	check(typeof park.slug === 'string' && SLUG.test(park.slug) && park.slug.length <= 80, `park slug ${park.slug} is not a lower-case hyphenated slug`);
	check(typeof park.name === 'string' && park.name.length >= 1 && park.name.length <= 120, 'park name must be 1-120 characters');
	check(PARK_AGENCIES.includes(park.agency), `park agency ${park.agency} is not one of ${PARK_AGENCIES.join(', ')}`);
	check(typeof park.region_code === 'string' && /^[A-Z]{2}-[A-Z0-9]{1,3}$/.test(park.region_code), `park region_code ${park.region_code} is not ISO 3166-2`);
	check(typeof park.country_code === 'string' && /^[A-Z]{2}$/.test(park.country_code), `park country_code ${park.country_code} is not ISO 3166-1 alpha-2`);
	check(typeof park.timezone === 'string' && park.timezone.length >= 1, 'park timezone is missing');
	check(park.website_url == null || /^https:\/\//.test(park.website_url), 'park website_url must be https');
	check(typeof manifest.attribution === 'string' && manifest.attribution.trim().length > 0, 'the manifest carries no attribution');

	/** @type {PayloadCourse[]} */
	const courses = [];
	for (const entry of manifest.courses ?? []) {
		check(typeof entry?.slug === 'string', 'a course has no slug');
		courses.push(
			payloadCourse(entry, courseLine(readGeojson(entry.geojson), entry.slug), {
				course_shape: entry.course_shape,
				difficulty: entry.difficulty ?? null,
				official_distance_m: null,
				description: entry.direction ? `Run it ${entry.direction}.` : null,
			}),
		);
	}
	for (const entry of manifest.race_courses ?? []) {
		check(typeof entry?.slug === 'string', 'a race course has no slug');
		const raceM = RACE_DISTANCES_M[/** @type {keyof typeof RACE_DISTANCES_M} */ (entry.race_distance)];
		check(raceM !== undefined, `${entry.slug}: unknown race distance ${entry.race_distance}`);
		check(entry.distance_m === raceM, `${entry.slug}: measures ${entry.distance_m} m, not the ${entry.race_distance} distance ${raceM} m`);
		check(Number.isInteger(entry.laps) && entry.laps >= 1, `${entry.slug}: laps must be a whole number of at least 1`);
		const laps = entry.laps === 1 ? 'one lap' : `${entry.laps} laps`;
		courses.push(
			payloadCourse(entry, courseLine(readGeojson(entry.geojson), entry.slug), {
				course_shape: 'loop',
				difficulty: null,
				official_distance_m: raceM,
				description: `Measures exactly ${RACE_DISTANCE_WORDS[entry.race_distance]}: ${laps} of the loop, starting and finishing on one line on the lead-in.`,
			}),
		);
	}
	check(courses.length > 0, 'the manifest has no courses');
	const slugs = courses.map((c) => c.slug);
	for (const slug of slugs) {
		check(SLUG.test(slug) && slug.length <= 80, `course slug ${slug} is not a lower-case hyphenated slug`);
	}
	check(new Set(slugs).size === slugs.length, `course slugs repeat: ${slugs.join(', ')}`);

	const subdivision = park.country_code === 'US' ? US_STATES[park.region_code.slice(3)] : undefined;
	return {
		park: {
			slug: park.slug,
			name: park.name,
			agency: park.agency,
			region_code: park.region_code,
			country_code: park.country_code,
			timezone: park.timezone,
			website_url: park.website_url ?? null,
		},
		region: subdivision ? `${park.name}, ${subdivision}` : park.name,
		attribution: manifest.attribution.trim(),
		courses,
	};
}

/**
 * The one statement the operator runs as the service role.
 *
 * @param {CataloguePayload} payload
 * @param {{ clubId: string, authorId: string, enqueueBackfill?: boolean }} opts
 */
export function loadSql(payload, { clubId, authorId, enqueueBackfill = false }) {
	check(UUID.test(clubId), `--club-id ${clubId} is not a uuid`);
	check(UUID.test(authorId), `--author-id ${authorId} is not a uuid`);
	const json = JSON.stringify(payload);
	let tag = '$park_catalogue$';
	for (let n = 1; json.includes(tag); n++) tag = `$park_catalogue_${n}$`;
	return (
		`select * from private.load_park_catalogue(\n  ${tag}${json}${tag}::jsonb,\n` +
		`  '${clubId.toLowerCase()}'::uuid,\n  '${authorId.toLowerCase()}'::uuid,\n  ${enqueueBackfill}\n);\n`
	);
}
