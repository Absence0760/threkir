-- Organiser course alerts (issue #1190: "verified organisers can post course
-- alerts on their listings and routes (reroutes, closures, the up/down
-- year)"; decisions § 2407).
--
-- A course alert is a short notice a verified organiser posts on a race
-- listing it claimed, or on a route its club owns. It is written only through
-- post_course_alert and removed only through delete_course_alert, both
-- definer RPCs that run the one derivation of "official"
-- (private.is_official_publisher, 20271021000030): the caller must be an
-- active owner/admin of a public, verified, unhidden club, and the club must
-- be the listing's organiser (race_listings.organiser_club_id, frozen against
-- client writes by force_unverified_listing) or the route's owning club
-- (routes.club_id). Nobody else can post one, there is no client INSERT,
-- UPDATE or DELETE grant, and the table carries no flag a client could set to
-- make an alert read as official.
--
-- Reads follow the target and the club's standing: an alert is visible only
-- while its club is still verified, public and unhidden (revoking the club
-- withdraws its alerts with its badge), and a route alert only to someone who
-- can see the route (private.is_route_visible_to). Listing alerts follow the
-- calendar, which anyone can read. The author column is not granted to
-- clients: the alert speaks for the club, not the admin who typed it.
--
-- Who is told: post_course_alert raises a `course_alert` notification
-- (kind added in 20271124002408) for
--   * a listing alert: every runner with an active or paused training plan
--     aimed at that race (training_plans.race_listing_id), and everyone who
--     saved the race's linked course route and can still see it;
--   * a route alert: everyone who saved that route and can still see it, and
--     every runner with an active or paused plan aimed at an upcoming race
--     whose linked course is that route.
-- Never the author, never for a race whose date has passed, one notice per
-- recipient per alert. A club may post at most five alerts per target per
-- 24 hours, so a mistaken loop cannot flood every runner training for a race.
--
-- Locks: a new table and new functions. The new table's foreign keys take a
-- brief SHARE ROW EXCLUSIVE on clubs, race_listings, routes and auth.users,
-- catalogue-only. notifications is untouched here; its column and kind are
-- 20271124002408, in their own transaction.

-- ── table ───────────────────────────────────────────────────────────────────

create table course_alerts (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references clubs (id) on delete cascade,
  author_id  uuid references auth.users (id) on delete set null,
  listing_id uuid references race_listings (id) on delete cascade,
  route_id   uuid references routes (id) on delete cascade,
  kind       text not null,
  message    text not null,
  created_at timestamptz not null default now(),
  constraint course_alerts_kind_check
    check (kind in ('reroute', 'closure', 'direction', 'notice')),
  constraint course_alerts_message_length_check
    check (char_length(btrim(message)) between 1 and 500),
  constraint course_alerts_one_target_check
    check (num_nonnulls(listing_id, route_id) = 1)
);

create index course_alerts_listing_idx
  on course_alerts (listing_id, created_at desc)
  where listing_id is not null;
create index course_alerts_route_idx
  on course_alerts (route_id, created_at desc)
  where route_id is not null;
create index course_alerts_club_id_idx on course_alerts (club_id);
create index course_alerts_author_id_idx on course_alerts (author_id);
create index course_alerts_listing_id_idx on course_alerts (listing_id);
create index course_alerts_route_id_idx on course_alerts (route_id);

alter table course_alerts enable row level security;

-- ── the club's standing, once ───────────────────────────────────────────────

create or replace function private.is_official_club(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_club_id is not null
    and exists (
      select 1 from clubs c
       where c.id = p_club_id
         and c.is_verified = true
         and c.is_public = true
         and c.shadow_hidden = false
    );
$$;

comment on function private.is_official_club(uuid) is
  'True while the club is verified, public and not shadow-hidden: the club '
  'half of private.is_official_publisher, for rows that speak for a club '
  'rather than an author (course alerts, decisions § 2407).';

grant execute on function private.is_official_club(uuid) to anon, authenticated, service_role;

create policy "course alerts readable with their course"
  on course_alerts for select to anon, authenticated
  using (
    private.is_official_club(club_id)
    and (
      listing_id is not null
      or private.is_route_visible_to(route_id, (select auth.uid()))
    )
  );

-- Supabase's default privileges grant every new table to the client roles;
-- take that back so only the columns below are readable and nothing is
-- writable except through the RPCs.
revoke all on public.course_alerts from public, anon, authenticated;
grant select (id, club_id, listing_id, route_id, kind, message, created_at)
  on public.course_alerts to anon, authenticated;
grant select, insert, update, delete on public.course_alerts to service_role;

-- ── post ────────────────────────────────────────────────────────────────────

create or replace function post_course_alert(
  p_listing_id uuid,
  p_route_id uuid,
  p_kind text,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_message text := btrim(coalesce(p_message, ''));
  v_club uuid;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'sign in to post a course alert' using errcode = '42501';
  end if;
  if num_nonnulls(p_listing_id, p_route_id) <> 1 then
    raise exception 'a course alert names one race or one route' using errcode = '22023';
  end if;
  if p_kind is null or p_kind not in ('reroute', 'closure', 'direction', 'notice') then
    raise exception 'unknown course alert kind' using errcode = '22023';
  end if;
  if char_length(v_message) < 1 or char_length(v_message) > 500 then
    raise exception 'a course alert is 1 to 500 characters' using errcode = '22001';
  end if;

  if p_listing_id is not null then
    select l.organiser_club_id into v_club from race_listings l where l.id = p_listing_id;
    if not found then
      raise exception 'race listing not found' using errcode = 'P0002';
    end if;
  else
    select r.club_id into v_club from routes r where r.id = p_route_id;
    if not found then
      raise exception 'route not found' using errcode = 'P0002';
    end if;
  end if;

  if v_club is null or not private.is_official_publisher(v_club, v_uid) then
    raise exception 'only an owner or admin of the verified organiser club can post a course alert'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'course_alert|' || coalesce(p_listing_id, p_route_id)::text, 0));
  if (
    select count(*) from course_alerts a
     where a.club_id = v_club
       and a.listing_id is not distinct from p_listing_id
       and a.route_id is not distinct from p_route_id
       and a.created_at > now() - interval '24 hours'
  ) >= 5 then
    raise exception 'this course already has five alerts today' using errcode = '54000';
  end if;

  insert into course_alerts (club_id, author_id, listing_id, route_id, kind, message)
  values (v_club, v_uid, p_listing_id, p_route_id, p_kind, v_message)
  returning id into v_id;

  insert into notifications (user_id, actor_id, kind, club_id, course_alert_id)
  select distinct r.user_id, v_uid, 'course_alert', v_club, v_id
  from (
    -- runners training for the race (listing alert)
    select p.user_id
      from training_plans p
      join race_listings l on l.id = p.race_listing_id
     where p_listing_id is not null
       and l.id = p_listing_id
       and l.race_date >= current_date
       and p.status in ('active', 'paused')
       and p.is_template = false
       and p.is_public_template = false
    union
    -- runners who saved the race's course (listing alert)
    select s.user_id
      from saved_routes s
      join race_listings l on l.route_id = s.route_id
     where p_listing_id is not null
       and l.id = p_listing_id
       and l.race_date >= current_date
       and private.is_route_visible_to(s.route_id, s.user_id)
    union
    -- runners who saved the route (route alert)
    select s.user_id
      from saved_routes s
     where p_route_id is not null
       and s.route_id = p_route_id
       and private.is_route_visible_to(s.route_id, s.user_id)
    union
    -- runners training for an upcoming race run on the route (route alert)
    select p.user_id
      from training_plans p
      join race_listings l on l.id = p.race_listing_id
     where p_route_id is not null
       and l.route_id = p_route_id
       and l.race_date >= current_date
       and p.status in ('active', 'paused')
       and p.is_template = false
       and p.is_public_template = false
  ) r
  where r.user_id is not null
    and r.user_id <> v_uid;

  return v_id;
end;
$$;

revoke execute on function post_course_alert(uuid, uuid, text, text) from public, anon;
grant execute on function post_course_alert(uuid, uuid, text, text) to authenticated;

-- ── delete ──────────────────────────────────────────────────────────────────

-- Removing an alert removes its notices too (notifications.course_alert_id
-- cascades), so a retracted mistake leaves no inbox line pointing at nothing.
create or replace function delete_course_alert(p_alert_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_club uuid;
begin
  if v_uid is null then
    raise exception 'sign in to remove a course alert' using errcode = '42501';
  end if;
  select a.club_id into v_club from course_alerts a where a.id = p_alert_id;
  if not found then
    raise exception 'course alert not found' using errcode = 'P0002';
  end if;
  if not private.is_official_publisher(v_club, v_uid) then
    raise exception 'only an owner or admin of the verified organiser club can remove a course alert'
      using errcode = '42501';
  end if;
  delete from course_alerts where id = p_alert_id;
end;
$$;

revoke execute on function delete_course_alert(uuid) from public, anon;
grant execute on function delete_course_alert(uuid) to authenticated;
