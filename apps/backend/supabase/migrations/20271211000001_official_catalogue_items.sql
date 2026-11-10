-- The official content catalogue (issue #1190, decisions § 2446): training
-- plans, gym routines and challenges the official club publishes from
-- `scripts/official/catalogue/`, loaded on every backend release the way the
-- park catalogue is (§ 2429).
--
-- private.official_catalogue_items is the crosswalk from a catalogue slug to
-- the row it published. It lives here rather than as a `catalogue_slug`
-- column on each content table because:
--   * no client can read or write it, so a slug cannot be forged onto a
--     user's row and adopted by the next load;
--   * the content tables, their generated row types and their RLS do not
--     change, and nothing is added to `routes`;
--   * one primary key gives every kind the same idempotence key.
-- A slug whose row was deleted (an owner deleting it in the app, an account
-- deletion cascading) points at nothing; the next load recreates the row and
-- moves the pointer.
--
-- official_race_courses gates the race-course part of the catalogue. It is
-- seeded off: tracing a course from an organiser's published map needs the
-- owner's counsel check first (issue #1190), and a course needs real,
-- reviewed geometry. Turning it on is a reviewed `prod_config.json` entry
-- with its sign-off (apps/backend/ops/README.md).
--
-- Locks (docs/backend/migration_locks.md): one new table and one flag row.

create table private.official_catalogue_items (
  kind       text not null check (kind in ('training_plan', 'gym_routine', 'challenge', 'race_course')),
  slug       text not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*(@[0-9]{4}(-[0-9]{2})?)?$' and char_length(slug) <= 120),
  target_id  uuid not null,
  created_at timestamptz not null default now(),
  primary key (kind, slug),
  unique (kind, target_id)
);

comment on table private.official_catalogue_items is
  'Catalogue slug -> the row private.load_official_catalogue published for it. Service role only; '
  'decisions § 2446.';

revoke all on private.official_catalogue_items from public, anon, authenticated;
grant select on private.official_catalogue_items to service_role;

insert into private.feature_flags (name, enabled)
values ('official_race_courses', false)
on conflict (name) do nothing;
