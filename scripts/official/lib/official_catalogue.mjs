// The official content catalogue (issue #1190, decisions § 2446): what a
// committed item under scripts/official/catalogue/ may say, and the stage SQL
// that loads the whole catalogue through `private.load_official_catalogue` on
// every backend release. Pure: ../sync.mjs reads the files and
// scripts/prod_sync/ holds the connection.
//
// The checks mirror the database's CHECK constraints and enums, so a bad item
// fails the PR rather than the release. The set-shaped lists below are rails
// of apps/web/scripts/check_constraint_unions.mjs, and the three Postgres
// enums are compared with database.types.ts by this module's tests.

/** @typedef {{ clubSlug: string, clubId: string }} Publisher */
/**
 * @typedef {{
 *   plans: any[],
 *   gym_routines: any[],
 *   challenges: any[],
 *   race_courses: any[],
 * }} Catalogue
 */

export const KINDS = /** @type {const} */ (['plans', 'gym_routines', 'challenges', 'race_courses']);

export const GOAL_EVENTS = ['distance_5k', 'distance_10k', 'distance_half', 'distance_full', 'custom'];
export const PLAN_PHASES = ['base', 'build', 'peak', 'taper', 'race', 'graduation'];
export const WORKOUT_KINDS = ['easy', 'long', 'recovery', 'tempo', 'interval', 'marathon_pace', 'race', 'rest', 'walk_run'];
export const PLAN_SOURCES = ['generated', 'imported', 'manual'];
export const PERIODISATIONS = ['none', 'linear', 'block', 'conjugate'];
export const MODALITIES = ['weight_reps', 'time', 'distance', 'bodyweight_reps'];
export const PROGRESSIONS = ['none', 'linear', 'double_progression', 'five_by_five', 'percent_cycle', 'rpe_autoreg'];
export const SET_TYPES = ['warmup', 'working', 'dropset', 'amrap', 'failure', 'backoff'];
export const CHALLENGE_METRICS = ['distance', 'duration', 'vert', 'activity_count', 'streak_days', 'park_courses'];
export const CHALLENGE_ACTIVITY_TYPES = ['run', 'walk', 'hike', 'cycle', 'stroller'];
export const RECURRENCES = ['monthly', 'yearly'];
export const ROUTE_SURFACES = ['road', 'trail', 'mixed'];
export const RACE_PROVIDERS = ['runsignup', 'parkrun', 'manual', 'chronotrack', 'raceresult', 'ultrasignup'];

/** The shortest window a recurrence can have, in days, which caps a streak goal. */
const SHORTEST_WINDOW_DAYS = { monthly: 28, yearly: 365 };

const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The columns the stage's result set carries, in order. */
export const SYNC_COLUMNS = ['kind', 'slug', 'action', 'target_id', 'published_by'];

class CatalogueError extends Error {}

/**
 * @param {string} where
 * @param {string} message
 * @returns {never}
 */
function fail(where, message) {
	throw new CatalogueError(`${where}: ${message}`);
}

/**
 * @param {string} where
 * @param {any} obj
 * @param {string[]} required
 * @param {string[]} optional
 */
function keys(where, obj, required, optional = []) {
	if (!obj || typeof obj !== 'object' || Array.isArray(obj)) fail(where, 'must be an object');
	for (const k of required) if (!(k in obj)) fail(where, `is missing ${k}`);
	const known = new Set([...required, ...optional]);
	for (const k of Object.keys(obj)) if (!known.has(k)) fail(where, `has an unknown key ${k}`);
}

/** @param {string} where @param {any} v @param {number} min @param {number} max */
function text(where, v, min, max) {
	if (typeof v !== 'string' || v.trim().length < min || v.length > max) {
		fail(where, `must be text of ${min} to ${max} characters`);
	}
}

/** @param {string} where @param {any} v @param {number} max */
function optionalText(where, v, max) {
	if (v === null || v === undefined) return;
	text(where, v, 0, max);
}

/** @param {string} where @param {any} v @param {number} min @param {number} [max] */
function int(where, v, min, max = Number.MAX_SAFE_INTEGER) {
	if (!Number.isInteger(v) || v < min || v > max) fail(where, `must be a whole number from ${min} to ${max}`);
}

/** @param {string} where @param {any} v @param {number} min @param {number} [max] */
function optionalInt(where, v, min, max) {
	if (v === null || v === undefined) return;
	int(where, v, min, max);
}

/** @param {string} where @param {any} v @param {number} min @param {number} [max] */
function optionalNumber(where, v, min, max = Number.MAX_VALUE) {
	if (v === null || v === undefined) return;
	if (typeof v !== 'number' || !Number.isFinite(v) || v < min || v > max) {
		fail(where, `must be a number from ${min} to ${max}`);
	}
}

/** @param {string} where @param {any} v @param {readonly string[]} allowed */
function oneOf(where, v, allowed) {
	if (!allowed.includes(v)) fail(where, `must be one of ${allowed.join(', ')}, got ${JSON.stringify(v)}`);
}

/** @param {string} where @param {any} slug */
function slugOf(where, slug) {
	if (typeof slug !== 'string' || !SLUG.test(slug) || slug.length > 100) {
		fail(where, `slug ${JSON.stringify(slug)} is not a lowercase slug of at most 100 characters`);
	}
}

/** @param {string} where @param {any} min @param {any} max */
function ordered(where, min, max) {
	if (min !== null && min !== undefined && max !== null && max !== undefined && min > max) {
		fail(where, 'has a minimum above its maximum');
	}
}

/**
 * A library plan: its design only. The library drops paces, notes, race names
 * and HR targets on every copy (decisions § 2340), so an item that carries
 * one is refused rather than silently thinned.
 *
 * @param {any} plan
 */
export function checkPlan(plan) {
	const where = `plan ${plan?.slug ?? '?'}`;
	keys(where, plan, ['slug', 'name', 'goal_event', 'goal_distance_m', 'days_per_week', 'end_day', 'weeks'], [
		'source',
		'preset',
	]);
	slugOf(where, plan.slug);
	text(`${where} name`, plan.name, 1, 120);
	oneOf(`${where} goal_event`, plan.goal_event, GOAL_EVENTS);
	optionalNumber(`${where} goal_distance_m`, plan.goal_distance_m, 1);
	if (plan.goal_distance_m == null) fail(where, 'needs a goal_distance_m');
	int(`${where} days_per_week`, plan.days_per_week, 2, 7);
	if (plan.source !== undefined) oneOf(`${where} source`, plan.source, PLAN_SOURCES);
	int(`${where} end_day`, plan.end_day, 0);
	if (!Array.isArray(plan.weeks) || plan.weeks.length === 0) fail(where, 'needs at least one week');
	const weekIndexes = new Set();
	const days = new Set();
	for (const week of plan.weeks) {
		const w = `${where} week ${week?.week_index ?? '?'}`;
		keys(w, week, ['week_index', 'phase', 'workouts'], ['target_volume_m']);
		int(`${w} week_index`, week.week_index, 0, 32767);
		if (weekIndexes.has(week.week_index)) fail(w, 'repeats a week_index');
		weekIndexes.add(week.week_index);
		oneOf(`${w} phase`, week.phase, PLAN_PHASES);
		optionalNumber(`${w} target_volume_m`, week.target_volume_m, 0);
		if (!Array.isArray(week.workouts)) fail(w, 'needs a workouts list');
		for (const wo of week.workouts) {
			const o = `${w} day ${wo?.day ?? '?'}`;
			keys(o, wo, ['day', 'kind'], [
				'target_distance_m',
				'target_duration_seconds',
				'pace_zone',
				'structure',
				'target_rpe_min',
				'target_rpe_max',
			]);
			int(`${o} day`, wo.day, 0, plan.end_day);
			if (days.has(wo.day)) fail(o, 'is a second workout on one day');
			days.add(wo.day);
			oneOf(`${o} kind`, wo.kind, WORKOUT_KINDS);
			optionalNumber(`${o} target_distance_m`, wo.target_distance_m, 0);
			optionalInt(`${o} target_duration_seconds`, wo.target_duration_seconds, 0);
			if (wo.target_distance_m != null && wo.target_duration_seconds != null) {
				fail(o, 'sets a duration beside a distance, which the library drops (they make a pace)');
			}
			optionalText(`${o} pace_zone`, wo.pace_zone, 40);
			optionalInt(`${o} target_rpe_min`, wo.target_rpe_min, 1, 10);
			optionalInt(`${o} target_rpe_max`, wo.target_rpe_max, 1, 10);
			ordered(`${o} rpe`, wo.target_rpe_min, wo.target_rpe_max);
			if (wo.kind === 'rest' && (wo.target_rpe_min != null || wo.target_rpe_max != null)) {
				fail(o, 'is a rest day with an effort target');
			}
			if (wo.structure != null && JSON.stringify(wo.structure).includes('"pace_sec_per_km"')) {
				fail(o, 'carries an absolute pace in its structure, which the library drops');
			}
		}
	}
}

/** @param {any} routine */
export function checkRoutine(routine) {
	const where = `gym routine ${routine?.slug ?? '?'}`;
	keys(where, routine, ['slug', 'title', 'exercises'], ['notes', 'periodisation']);
	slugOf(where, routine.slug);
	text(`${where} title`, routine.title, 1, 120);
	optionalText(`${where} notes`, routine.notes, 1000);
	if (routine.periodisation !== undefined) oneOf(`${where} periodisation`, routine.periodisation, PERIODISATIONS);
	if (!Array.isArray(routine.exercises) || routine.exercises.length === 0) fail(where, 'needs at least one exercise');
	for (const [i, ex] of routine.exercises.entries()) {
		const e = `${where} exercise ${i + 1}`;
		keys(e, ex, ['name', 'modality', 'sets'], [
			'notes',
			'progression',
			'progression_params',
			'superset_group',
			'superset_order',
		]);
		text(`${e} name`, ex.name, 1, 120);
		oneOf(`${e} modality`, ex.modality, MODALITIES);
		if (ex.progression !== undefined) oneOf(`${e} progression`, ex.progression, PROGRESSIONS);
		optionalText(`${e} notes`, ex.notes, 500);
		if ((ex.superset_group == null) !== (ex.superset_order == null)) {
			fail(e, 'sets one of superset_group and superset_order without the other');
		}
		optionalInt(`${e} superset_order`, ex.superset_order, 0);
		if (!Array.isArray(ex.sets) || ex.sets.length === 0) fail(e, 'needs at least one set');
		for (const [j, set] of ex.sets.entries()) {
			const s = `${e} set ${j + 1}`;
			keys(s, set, [], [
				'set_type',
				'target_reps_min',
				'target_reps_max',
				'target_weight_kg',
				'target_percent_1rm',
				'target_rpe',
				'rest_s',
				'tempo',
				'target_duration_s',
				'target_distance_m',
			]);
			if (set.set_type !== undefined) oneOf(`${s} set_type`, set.set_type, SET_TYPES);
			optionalInt(`${s} target_reps_min`, set.target_reps_min, 0);
			optionalInt(`${s} target_reps_max`, set.target_reps_max, 0);
			ordered(`${s} reps`, set.target_reps_min, set.target_reps_max);
			optionalNumber(`${s} target_weight_kg`, set.target_weight_kg, 0, 99999.99);
			optionalNumber(`${s} target_percent_1rm`, set.target_percent_1rm, 0.01, 200);
			if (set.target_weight_kg != null && set.target_percent_1rm != null) fail(s, 'sets both a weight and a %1RM');
			optionalNumber(`${s} target_rpe`, set.target_rpe, 0, 10);
			optionalInt(`${s} rest_s`, set.rest_s, 0, 3600);
			if (set.tempo != null && !/^[0-9X]{3,4}$/.test(set.tempo)) fail(s, 'has a tempo that is not 3 or 4 of 0-9 / X');
			optionalInt(`${s} target_duration_s`, set.target_duration_s, 0);
			optionalNumber(`${s} target_distance_m`, set.target_distance_m, 0);
		}
	}
}

/** @param {any} challenge */
export function checkChallenge(challenge) {
	const where = `challenge ${challenge?.slug ?? '?'}`;
	keys(where, challenge, ['slug', 'recurrence', 'title', 'metric', 'goal_value'], ['description', 'activity_type']);
	slugOf(where, challenge.slug);
	oneOf(`${where} recurrence`, challenge.recurrence, RECURRENCES);
	if (typeof challenge.title !== 'string' || !challenge.title.includes('{period}')) {
		fail(where, 'title must name its {period}, so each board says which month or year it is');
	}
	const longest = challenge.title.replace('{period}', 'September 2027');
	text(`${where} title`, longest, 1, 120);
	optionalText(`${where} description`, challenge.description, 2000);
	oneOf(`${where} metric`, challenge.metric, CHALLENGE_METRICS);
	if (challenge.metric === 'park_courses') fail(where, 'park_courses boards need a park region, which the catalogue does not carry');
	optionalNumber(`${where} goal_value`, challenge.goal_value, Number.MIN_VALUE);
	if (challenge.goal_value == null) fail(where, 'needs a goal_value, so a runner can finish it');
	if (challenge.metric === 'streak_days') {
		const cap = SHORTEST_WINDOW_DAYS[/** @type {'monthly' | 'yearly'} */ (challenge.recurrence)];
		if (challenge.goal_value > cap) fail(where, `streak goal ${challenge.goal_value} is longer than its shortest window (${cap} days)`);
	}
	if (challenge.activity_type != null) oneOf(`${where} activity_type`, challenge.activity_type, CHALLENGE_ACTIVITY_TYPES);
}

/**
 * A race course traced from the race's published map. Loaded only while the
 * `official_race_courses` flag is on; the geometry must be the reviewed
 * trace, never a placeholder.
 *
 * @param {any} course
 */
export function checkRaceCourse(course) {
	const where = `race course ${course?.slug ?? '?'}`;
	keys(where, course, ['slug', 'name', 'description', 'source_ref', 'distance_m', 'waypoints'], [
		'listing',
		'listing_id',
		'surface',
		'elevation_m',
	]);
	slugOf(where, course.slug);
	text(`${where} name`, course.name, 1, 120);
	text(`${where} description`, course.description, 1, 2000);
	if (typeof course.source_ref !== 'string' || !/^https:\/\/\S+$/.test(course.source_ref)) {
		fail(where, 'source_ref must be the https URL of the published course map it was traced from');
	}
	if (('listing' in course) === ('listing_id' in course)) fail(where, 'needs exactly one of listing and listing_id');
	if ('listing_id' in course && (typeof course.listing_id !== 'string' || !UUID.test(course.listing_id))) {
		fail(where, 'listing_id must be a uuid');
	}
	if ('listing' in course) {
		keys(`${where} listing`, course.listing, ['provider', 'provider_race_id']);
		oneOf(`${where} listing provider`, course.listing.provider, RACE_PROVIDERS);
		text(`${where} listing provider_race_id`, course.listing.provider_race_id, 1, 200);
	}
	if (course.surface !== undefined) oneOf(`${where} surface`, course.surface, ROUTE_SURFACES);
	optionalNumber(`${where} distance_m`, course.distance_m, 1);
	optionalNumber(`${where} elevation_m`, course.elevation_m, 0);
	if (!Array.isArray(course.waypoints) || course.waypoints.length < 2) fail(where, 'needs at least two waypoints');
	for (const [i, p] of course.waypoints.entries()) {
		keys(`${where} waypoint ${i + 1}`, p, ['lat', 'lng'], ['ele']);
		optionalNumber(`${where} waypoint ${i + 1} lat`, p.lat, -90, 90);
		optionalNumber(`${where} waypoint ${i + 1} lng`, p.lng, -180, 180);
	}
}

const CHECKS = { plans: checkPlan, gym_routines: checkRoutine, challenges: checkChallenge, race_courses: checkRaceCourse };

/**
 * Checks every item and that slugs are unique within a kind.
 *
 * @param {Catalogue} catalogue
 * @returns {Catalogue}
 */
export function checkCatalogue(catalogue) {
	for (const kind of KINDS) {
		const items = catalogue[kind];
		if (!Array.isArray(items)) fail(kind, 'must be a list');
		const slugs = new Set();
		for (const item of items) {
			CHECKS[kind](item);
			if (slugs.has(item.slug)) fail(kind, `repeats the slug ${item.slug}`);
			slugs.add(item.slug);
		}
	}
	return catalogue;
}

/**
 * The item as the loader reads it: a plan's `preset` (the generator inputs
 * its weeks were built from, read by the web test that pins them) stays out
 * of the payload.
 *
 * @param {Catalogue} catalogue
 */
export function payloadOf(catalogue) {
	return {
		plans: catalogue.plans.map(({ preset: _preset, ...plan }) => plan),
		gym_routines: catalogue.gym_routines,
		challenges: catalogue.challenges,
		race_courses: catalogue.race_courses,
	};
}

/**
 * The stage body: resolves the club's publishing account the way the park
 * stage does (`private.resolve_club_publisher`), loads the whole catalogue as
 * it in one call, and selects a row per item. The caller wraps it in the
 * transaction that commits or, on a dry run, rolls back.
 *
 * @param {Catalogue} catalogue
 * @param {Publisher} publisher
 */
export function officialCatalogueSql(catalogue, publisher) {
	if (!SLUG.test(publisher.clubSlug) || !UUID.test(publisher.clubId)) throw new Error('the publisher is not a club slug and id');
	const json = JSON.stringify(payloadOf(checkCatalogue(catalogue)));
	let tag = '$official_catalogue$';
	for (let n = 1; json.includes(tag); n++) tag = `$official_catalogue_${n}$`;
	const club = `'${publisher.clubId}'::uuid`;
	return (
		// Both functions are granted to service_role only (decisions § 2429, § 2446).
		'set local role service_role;\n' +
		'create temp table official_catalogue_publisher on commit drop as\n' +
		`  select private.resolve_club_publisher('${publisher.clubSlug}', ${club}) as author_id;\n` +
		`select l.kind, l.slug, l.action, l.target_id, p.author_id as published_by\n` +
		`  from official_catalogue_publisher p\n` +
		`  cross join lateral private.load_official_catalogue(\n` +
		`    ${tag}${json}${tag}::jsonb,\n` +
		`    ${club},\n` +
		'    p.author_id\n' +
		'  ) with ordinality l(kind, slug, target_id, action, n)\n' +
		' order by l.n;\n'
	);
}

/**
 * One line for the step summary.
 *
 * @param {Catalogue} catalogue
 */
export function catalogueNote(catalogue) {
	return KINDS.map((k) => `${catalogue[k].length} ${k.replace('_', ' ')}`).join(', ') +
		(catalogue.race_courses.length > 0 ? ' (race courses load only while official_race_courses is on)' : '');
}
