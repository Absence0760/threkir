// The park catalogue on a LOCAL stack, for the opt-in demo dataset
// (bin/seed-demo.sh, decisions § 2521 as amended by § 2590). The same load the
// release sync runs (`catalogueSyncSql`: `private.resolve_club_publisher`, then
// `private.load_park_catalogue` per park as the official club), with two local
// differences: the official club is created first, owned by seed.sql's runner,
// because no local stack has one; and staged parks load too, because staging
// holds a park back from production, not from a developer's own database.
// Pure: ../local_load.mjs does the file reads.

import { catalogueSyncSql } from './catalogue_sync.mjs';

/** @typedef {import('./catalogue_payload.mjs').CataloguePayload} CataloguePayload */
/** @typedef {import('./catalogue_sync.mjs').Publisher} Publisher */

/** seed.sql's `runner@test.com`, who owns every seeded club. */
export const LOCAL_PUBLISHER_OWNER = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';

/**
 * The load body: refuses a database seed.sql did not build, creates the
 * official club (verified, public, owned by the seed runner) when it is
 * missing, then runs the release sync's SQL over every park.
 *
 * @param {CataloguePayload[]} payloads every park, staged or live
 * @param {Publisher} publisher the committed publisher.json
 */
export function localCatalogueSql(payloads, publisher) {
	const sync = catalogueSyncSql(payloads, publisher);
	return (
		'do $$\n' +
		'begin\n' +
		// The same rail as seed_demo.sql: only seed.sql creates this function.
		"  if to_regprocedure('tests.confirm_consent()') is null then\n" +
		"    raise exception 'catalogue_local: tests.confirm_consent() is missing, so this database was not seeded by seed.sql; refusing to load the catalogue';\n" +
		'  end if;\n' +
		`  if not exists (select 1 from auth.users where id = '${LOCAL_PUBLISHER_OWNER}') then\n` +
		"    raise exception 'catalogue_local: runner@test.com is missing; run supabase db reset first';\n" +
		'  end if;\n' +
		'end $$;\n' +
		'insert into clubs (id, owner_id, name, slug, description, location_label, is_public, join_policy, is_verified)\n' +
		`values ('${publisher.clubId}', '${LOCAL_PUBLISHER_OWNER}', 'Threkir', '${publisher.clubSlug}',\n` +
		"        'The official club. On a local stack it publishes the park catalogue (bin/seed-demo.sh).',\n" +
		"        'Virginia', true, 'open', true)\n" +
		'on conflict (id) do nothing;\n' +
		sync
	);
}
