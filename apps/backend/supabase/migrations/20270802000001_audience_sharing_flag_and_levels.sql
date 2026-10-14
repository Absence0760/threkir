-- Audience sharing, part 1: the deploy gate and the followers level.
--
-- A run or route is either public (`is_public`) or owner-only today, and every
-- share button flips it public first. The owner asked (2026-10-13) for two
-- narrower audiences that do not make anything public: the owner's followers,
-- and named people (the grant tables in 20270802000002). This file adds the
-- gate both of them sit behind and the followers level itself.
--
-- 1. private.feature_flags + private.audience_sharing_enabled(). Who can read
--    location data changes, so the whole feature waits on a CISO / Security
--    Analyst review before it reaches real users (decisions § 150). The gate
--    is a row in a private table rather than a client env var because the
--    widening is enforced in SQL: a client flag would hide the control and
--    leave the server reading followers / grants for anyone who wrote one
--    directly. NO ROW IS INSERTED HERE, so every environment this migration
--    reaches starts closed; seed.sql opens it for local + CI only. Flipping
--    prod is the pre-deploy checklist item in docs/features/sharing.md.
--    public.audience_sharing_enabled() is the one reader clients get, so web
--    and mobile ask the same question the server answers with.
--
-- 2. runs.followers_only + routes.followers_only. A boolean beside
--    `is_public`, not a visibility enum replacing it: every existing reader
--    (public_runs / public_routes, the feed, run_completed notifications
--    § 96, the sitemap, heatmap, challenges) keys on `is_public` and must not
--    move, and a constant-default boolean is a catalogue-only ADD COLUMN with
--    no backfill on either populated table. The level a client shows is
--    derived: is_public -> public, followers_only -> followers, a live grant
--    -> specific people, else only me (§ 1874).
--
-- 3. private.normalize_audience(), a BEFORE INSERT OR UPDATE trigger on both
--    tables, keeps the pair coherent without a CHECK a client could trip:
--      * is_public wins and clears followers_only, so a client that only
--        knows `is_public` (every mobile build in the field) can still flip
--        a followers run public without a 23514;
--      * while the gate is closed followers_only is stored false, so a writer
--        that maps the `followers` privacy default to followers_only (web
--        now, mobile + importers next) changes nothing before sign-off and a
--        run saved today cannot widen retroactively on the day the flag
--        flips (§ 1875).
--
-- Locks: ADD COLUMN ... NOT NULL DEFAULT false is catalogue-only on PG 11+
-- (no rewrite, no scan); CREATE TRIGGER takes SHARE ROW EXCLUSIVE briefly.
-- No constraint is added, so there is no VALIDATE to split into a later file.

create table private.feature_flags (
  name       text primary key check (name ~ '^[a-z][a-z0-9_]*$'),
  enabled    boolean not null default false,
  updated_at timestamptz not null default now()
);

comment on table private.feature_flags is
  'Server-enforced deploy gates. An absent row is OFF. Flipped by an operator '
  'with SQL after the sign-off the gate stands for; never written by a client.';

alter table private.feature_flags enable row level security;
revoke all on table private.feature_flags from public, anon, authenticated, service_role;

create or replace function private.audience_sharing_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'audience_sharing'),
    false
  );
$$;

revoke execute on function private.audience_sharing_enabled() from public, anon;
grant execute on function private.audience_sharing_enabled() to authenticated, service_role;

create or replace function public.audience_sharing_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.audience_sharing_enabled();
$$;

revoke execute on function public.audience_sharing_enabled() from public, anon;
grant execute on function public.audience_sharing_enabled() to authenticated, service_role;

comment on function public.audience_sharing_enabled() is
  'Whether the followers level and named-person shares are live (decisions '
  '§ 1874). Clients hide the audience control when false.';

alter table public.runs add column followers_only boolean not null default false;
alter table public.routes add column followers_only boolean not null default false;

comment on column public.runs.followers_only is
  'Readable by the owner''s followers (not public, not in feeds). Ignored and '
  'cleared when is_public is true; stored false while audience sharing is off.';
comment on column public.routes.followers_only is
  'Readable by the owner''s followers (not public, not in listings). Ignored '
  'and cleared when is_public is true; stored false while audience sharing is off.';

create or replace function private.normalize_audience()
returns trigger
language plpgsql
set search_path = public, private
as $$
begin
  if new.is_public then
    new.followers_only := false;
  elsif new.followers_only and not private.audience_sharing_enabled() then
    new.followers_only := false;
  end if;
  return new;
end;
$$;

revoke execute on function private.normalize_audience() from public, anon, authenticated;

create trigger runs_normalize_audience
  before insert or update of is_public, followers_only on public.runs
  for each row execute function private.normalize_audience();

create trigger routes_normalize_audience
  before insert or update of is_public, followers_only on public.routes
  for each row execute function private.normalize_audience();
