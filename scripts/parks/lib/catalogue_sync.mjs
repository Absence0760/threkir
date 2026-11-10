// The park catalogue stage of the production sync (issue #1349, decisions
// § 2429): every committed park, through `private.load_park_catalogue`, as
// one SQL body whose single result set is a row per course. Pure: the CLI in
// ../sync.mjs and the runner in scripts/prod_sync/ do the file reads and the
// connection.

import { loadCall } from './catalogue_payload.mjs';

/** @typedef {import('./catalogue_payload.mjs').CataloguePayload} CataloguePayload */
/** @typedef {{ clubSlug: string, clubId: string, authorId: string }} Publisher */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;

/** The columns the stage's result set carries, in order. */
export const SYNC_COLUMNS = ['park', 'course_slug', 'action', 'backfill_job_id', 'park_course_id'];

/**
 * The committed publisher config (`scripts/parks/publisher.json`).
 *
 * @param {any} json
 * @returns {Publisher}
 */
export function parsePublisher(json) {
	if (!json || typeof json !== 'object' || Array.isArray(json)) throw new Error('publisher.json must be an object');
	const keys = Object.keys(json).sort().join(',');
	if (keys !== 'author_id,club_id,club_slug') {
		throw new Error(`publisher.json must hold exactly club_slug, club_id and author_id, got ${keys}`);
	}
	if (typeof json.club_slug !== 'string' || !SLUG.test(json.club_slug)) {
		throw new Error(`publisher.json club_slug ${json.club_slug} is not a slug`);
	}
	for (const key of ['club_id', 'author_id']) {
		if (typeof json[key] !== 'string' || !UUID.test(json[key])) {
			throw new Error(`publisher.json ${key} ${json[key]} is not a uuid`);
		}
	}
	return { clubSlug: json.club_slug, clubId: json.club_id.toLowerCase(), authorId: json.author_id.toLowerCase() };
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
 * The stage body: loads every park with the backfill flag on, collects each
 * course's row in one temp table, and selects it. The caller wraps it in the
 * transaction that commits or, on a dry run, rolls back.
 *
 * @param {CataloguePayload[]} payloads
 * @param {Publisher} publisher
 */
export function catalogueSyncSql(payloads, publisher) {
	if (payloads.length === 0) throw new Error('the catalogue has no parks to sync');
	const parks = payloads.map((p) => p.park.slug);
	if (new Set(parks).size !== parks.length) throw new Error(`park slugs repeat: ${parks.join(', ')}`);
	const opts = { clubId: publisher.clubId, authorId: publisher.authorId, enqueueBackfill: true };
	const loads = payloads.map(
		(payload) =>
			`insert into pg_temp.park_catalogue_sync (park, course_slug, action, backfill_job_id, park_course_id)\n` +
			`select '${payload.park.slug}', l.course_slug, l.action, l.backfill_job_id, l.park_course_id\n` +
			`  from ${loadCall(payload, opts)} l;\n`,
	);
	return (
		// The function is granted to service_role only (decisions § 2425).
		'set local role service_role;\n' +
		'create temp table park_catalogue_sync (\n' +
		'  seq bigint generated always as identity,\n' +
		'  park text not null, course_slug text not null, action text not null,\n' +
		'  backfill_job_id bigint, park_course_id uuid\n' +
		') on commit drop;\n' +
		loads.join('') +
		`select ${SYNC_COLUMNS.join(', ')} from pg_temp.park_catalogue_sync order by seq;\n`
	);
}
