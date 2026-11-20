// The park catalogue stage of the production sync (issue #1349, decisions
// § 2429): every committed park, through `private.load_park_catalogue`, as
// one SQL body whose single result set is a row per course. Pure: the CLI in
// ../sync.mjs and the runner in scripts/prod_sync/ do the file reads and the
// connection.

import { loadCallSql } from './catalogue_payload.mjs';

/** @typedef {import('./catalogue_payload.mjs').CataloguePayload} CataloguePayload */
/** @typedef {{ clubSlug: string, clubId: string }} Publisher */
/**
 * A park or the courses of one held out of the load: every course of a staged
 * park, or the held courses of a live one (decisions § 2602).
 *
 * @typedef {{ park: string, courses: string[], reason: string }} StagedPark
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

/** The columns the stage's result set carries, in order. */
export const SYNC_COLUMNS = ['park', 'course_slug', 'action', 'backfill_job_id', 'park_course_id', 'published_by'];

/**
 * The committed publisher config (`scripts/parks/publisher.json`): the
 * official club by slug, and its id as a cross-check. The author is not
 * committed; the stage resolves it at run time
 * (`private.resolve_club_publisher`), so a change of club ownership never
 * breaks a release.
 *
 * @param {any} json
 * @returns {Publisher}
 */
export function parsePublisher(json) {
	if (!json || typeof json !== 'object' || Array.isArray(json)) throw new Error('publisher.json must be an object');
	const keys = Object.keys(json).sort().join(',');
	if (keys !== 'club_id,club_slug') {
		throw new Error(`publisher.json must hold exactly club_slug and club_id, got ${keys}`);
	}
	if (typeof json.club_slug !== 'string' || !SLUG.test(json.club_slug)) {
		throw new Error(`publisher.json club_slug ${json.club_slug} is not a slug`);
	}
	if (typeof json.club_id !== 'string' || !UUID.test(json.club_id)) {
		throw new Error(`publisher.json club_id ${json.club_id} is not a uuid`);
	}
	return { clubSlug: json.club_slug, clubId: json.club_id.toLowerCase() };
}

/**
 * The park directories under a catalogue root, `<region>/<park>`, that hold a
 * built `manifest.json`, sorted so the load order is stable.
 *
 * @param {string[]} manifestPaths every `<region>/<park>/manifest.json` relative to the root
 */
export function parkDirsFromManifests(manifestPaths) {
	return manifestPaths
		.map((p) => p.split(/[\\/]/))
		.filter((parts) => parts.length === 3 && parts[2] === 'manifest.json')
		.map((parts) => `${parts[0]}/${parts[1]}`)
		.sort();
}

/**
 * The payload the load takes for a live park: its courses minus the held
 * ones, with the held slugs listed in `held` so the load never closes one
 * that is already loaded (decisions § 2602). A held course's geometry goes no
 * further than this.
 *
 * @param {CataloguePayload} payload
 * @param {import('./catalogue_release.mjs').Release} release
 * @returns {CataloguePayload}
 */
export function loadablePayload(payload, release) {
	if (release.status !== 'live') throw new Error(`${payload.park.slug} is staged and does not load`);
	if (!release.held) return payload;
	const held = release.held.map((h) => h.course);
	const named = new Set(payload.courses.map((c) => c.slug));
	const unknown = held.filter((slug) => !named.has(slug));
	if (unknown.length > 0) throw new Error(`${payload.park.slug} holds course(s) its manifest does not name: ${unknown.join(', ')}`);
	const courses = payload.courses.filter((c) => !held.includes(c.slug));
	if (courses.length === 0) throw new Error(`${payload.park.slug} holds every course; its release must be staged`);
	return { ...payload, courses, held };
}

/**
 * Splits validated parks into the payloads the sync loads and the parks and
 * courses it only reports (decisions § 2460, § 2602). A staged park's or a
 * held course's geometry goes no further than this: the stage SQL carries its
 * slugs only.
 *
 * @param {{ payload: CataloguePayload, release: import('./catalogue_release.mjs').Release }[]} parks
 * @returns {{ live: CataloguePayload[], staged: StagedPark[] }}
 */
export function splitByRelease(parks) {
	/** @type {CataloguePayload[]} */
	const live = [];
	/** @type {StagedPark[]} */
	const staged = [];
	for (const { payload, release } of parks) {
		const park = String(payload.park.slug);
		if (release.status === 'staged') {
			staged.push({ park, courses: payload.courses.map((c) => c.slug), reason: release.reason });
			continue;
		}
		live.push(loadablePayload(payload, release));
		for (const h of release.held ?? []) staged.push({ park, courses: [h.course], reason: h.reason });
	}
	return { live, staged };
}

/**
 * The stage body: resolves the club's publishing account (its active owner,
 * else its earliest-joined active admin; the function refuses a club that is
 * not the committed id, not verified, public and visible, or has neither),
 * loads every live park as it with the backfill flag on, collects each
 * course's row in one temp table, adds a `staged` row per course of each
 * staged park without loading it, and selects the table. The caller wraps it
 * in the transaction that commits or, on a dry run, rolls back.
 *
 * @param {CataloguePayload[]} payloads the live parks
 * @param {Publisher} publisher
 * @param {StagedPark[]} [staged]
 */
export function catalogueSyncSql(payloads, publisher, staged = []) {
	if (payloads.length === 0 && staged.length === 0) throw new Error('the catalogue has no parks to sync');
	if (!SLUG.test(publisher.clubSlug) || !UUID.test(publisher.clubId)) throw new Error('the publisher is not a club slug and id');
	for (const s of staged) {
		if (!SLUG.test(s.park) || s.courses.length === 0 || !s.courses.every((c) => SLUG.test(c))) {
			throw new Error(`staged park ${s.park} is not a park slug with course slugs`);
		}
	}
	const loadedParks = payloads.map((p) => p.park.slug);
	if (new Set(loadedParks).size !== loadedParks.length) throw new Error(`park slugs repeat: ${loadedParks.join(', ')}`);
	const courseKeys = staged.flatMap((s) => s.courses.map((c) => `${s.park}/${c}`));
	if (new Set(courseKeys).size !== courseKeys.length) throw new Error(`staged courses repeat: ${courseKeys.join(', ')}`);
	for (const p of payloads) {
		const held = new Set(p.held ?? []);
		const fromStaged = new Set(staged.filter((s) => s.park === p.park.slug).flatMap((s) => s.courses));
		if (held.size !== fromStaged.size || [...held].some((c) => !fromStaged.has(c))) {
			throw new Error(`${p.park.slug}: its held courses and its staged rows disagree`);
		}
	}
	const club = `'${publisher.clubId}'::uuid`;
	const opts = {
		clubSql: club,
		authorSql: '(select author_id from pg_temp.park_catalogue_publisher)',
		enqueueBackfill: true,
	};
	const loads = payloads.map(
		(payload) =>
			`insert into pg_temp.park_catalogue_sync (park, course_slug, action, backfill_job_id, park_course_id)\n` +
			`select '${payload.park.slug}', l.course_slug, l.action, l.backfill_job_id, l.park_course_id\n` +
			`  from ${loadCallSql(payload, opts)} l;\n`,
	);
	// A course held out is `held_live` when it is already loaded and open (the
	// load leaves it exactly as it is), and `staged` when it is not.
	const stagedRows = staged.flatMap((s) => s.courses.map((c) => `('${s.park}', '${c}')`));
	if (stagedRows.length > 0) {
		loads.push(
			'insert into pg_temp.park_catalogue_sync (park, course_slug, action)\n' +
				'select v.park, v.course_slug,\n' +
				'       case when exists (select 1 from public.park_courses pc join public.parks p on p.id = pc.park_id\n' +
				"                          where p.slug = v.park and pc.slug = v.course_slug and pc.status <> 'closed')\n" +
				"            then 'held_live' else 'staged' end\n" +
				`  from (values\n  ${stagedRows.join(',\n  ')}\n) v(park, course_slug);\n`,
		);
	}
	return (
		// Both functions are granted to service_role only (decisions § 2425, § 2429).
		'set local role service_role;\n' +
		'create temp table park_catalogue_publisher on commit drop as\n' +
		`  select private.resolve_club_publisher('${publisher.clubSlug}', ${club}) as author_id;\n` +
		'create temp table park_catalogue_sync (\n' +
		'  seq bigint generated always as identity,\n' +
		'  park text not null, course_slug text not null, action text not null,\n' +
		'  backfill_job_id bigint, park_course_id uuid\n' +
		') on commit drop;\n' +
		loads.join('') +
		`select s.${SYNC_COLUMNS.slice(0, -1).join(', s.')}, p.author_id as published_by\n` +
		'  from pg_temp.park_catalogue_sync s cross join pg_temp.park_catalogue_publisher p order by s.seq;\n'
	);
}
