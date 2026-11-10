// The park catalogue stage of the production sync (issue #1349, decisions
// § 2429): every committed park, through `private.load_park_catalogue`, as
// one SQL body whose single result set is a row per course. Pure: the CLI in
// ../sync.mjs and the runner in scripts/prod_sync/ do the file reads and the
// connection.

import { loadCallSql } from './catalogue_payload.mjs';

/** @typedef {import('./catalogue_payload.mjs').CataloguePayload} CataloguePayload */
/** @typedef {{ clubSlug: string, clubId: string }} Publisher */

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
 * The stage body: resolves the club's publishing account (its active owner,
 * else its earliest-joined active admin; the function refuses a club that is
 * not the committed id, not verified, public and visible, or has neither),
 * loads every park as it with the backfill flag on, collects each course's
 * row in one temp table, and selects it. The caller wraps it in the
 * transaction that commits or, on a dry run, rolls back.
 *
 * @param {CataloguePayload[]} payloads
 * @param {Publisher} publisher
 */
export function catalogueSyncSql(payloads, publisher) {
	if (payloads.length === 0) throw new Error('the catalogue has no parks to sync');
	if (!SLUG.test(publisher.clubSlug) || !UUID.test(publisher.clubId)) throw new Error('the publisher is not a club slug and id');
	const parks = payloads.map((p) => p.park.slug);
	if (new Set(parks).size !== parks.length) throw new Error(`park slugs repeat: ${parks.join(', ')}`);
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
