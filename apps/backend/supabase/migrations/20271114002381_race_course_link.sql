-- A verified club claims a race and links its course (issue #1297; decisions
-- § 2381).
--
-- Until now only the service role could write race_listings.route_id
-- (20270924000002), so every course was linked by an operator in the SQL
-- editor. This opens the client write path the earlier migration reserved,
-- through definer RPCs only, with the verified club as the unit of trust:
--
--   * claim_race_listing(listing, club): an active owner/admin of a public,
--     verified club (private.is_official_publisher, the one derivation of
--     "official", 20271021000030) claims an UNCLAIMED listing. The listing
--     records organiser_club_id and becomes verified. The Threkir club is
--     such a club and takes the same path; nothing names it.
--   * link_race_course(listing, route, source): an owner/admin of the
--     listing's organiser club links a route that is public, not moderated
--     away, and owned by that club (routes.club_id, 20260520_001). A course on
--     a personal account could be deleted or made private by one person and
--     the race page would silently lose it. A null route unlinks. The source
--     says whether the course is the organiser's official one or traced from
--     the published map; the link stamps course_checked_at.
--   * suggest_race_course(listing, route, note): any runner suggests a public
--     route. It never links anything; it queues a suggestion.
--   * review_race_course_suggestion(id, approve, route, source): the organiser
--     club's owner/admin approves (which links the course through the same
--     checks as link_race_course, so a runner's personal route cannot be
--     linked by approval; the reviewer names the club's own copy) or rejects.
--     An unclaimed race is reviewed by claiming it first.
--   * race_course_suggestions_for_review(listing): the pending queue, for the
--     organiser club's admins, or for any verified-club admin while the race
--     is unclaimed. It never returns who suggested a route.
--
-- Every claim, link, unlink and review is written to race_listing_audit.
--
-- Direct writes stay closed. force_unverified_listing now freezes the new
-- columns beside is_verified and route_id: a client insert drops them and a
-- client update keeps the stored values. Its test changes from the JWT role
-- to current_user, the signal 20270704000003 settled on for the same reason:
-- inside a definer RPC called by a runner the JWT and the session role both
-- read `authenticated`, and only current_user (postgres there) tells the RPC
-- apart from a PostgREST write. service_role and migrations are unguarded, as
-- before. pg_trigger_depth() = 1 stays, so the route-delete cascade and the
-- edit trigger below are never reverted.
--
-- Decision 4 (an edit to a linked route): kept, and flagged. Blocking the
-- edit would make an organiser unlink, edit and relink to fix a corner; the
-- note says the course changed. routes_flag_linked_race_course stamps
-- race_listings.course_updated_at when a linked route's waypoints change, and
-- the race page shows "Course updated <date>" until the club re-checks it
-- (link_race_course again, which clears the stamp).
--
-- Reads: public_race_listings appends the organiser club (id, name, slug,
-- only while the club is public and not hidden) and the course source,
-- checked and updated dates (only while the course itself is shown, i.e. the
-- route is public). Existing columns keep their names, types and order.
--
-- Locks: race_listings is a bounded calendar table (migration_locks.md names
-- it as one where the online form is ceremony). The new columns are nullable
-- catalogue changes; the CHECK on a column that is null in every row and the
-- empty partial indexes are cheap. The routes trigger is catalogue-only.

set search_path = public, extensions;

-- ── race_listings: organiser + course provenance ────────────────────────────

alter table race_listings
  add column organiser_club_id uuid references clubs (id) on delete set null,
  add column course_source text,
  add column course_checked_at timestamptz,
  add column course_updated_at timestamptz;

alter table race_listings add constraint race_listings_course_source_check
  check (course_source is null or course_source in ('official', 'traced'));

create index race_listings_organiser_club_idx
  on race_listings (organiser_club_id)
  where organiser_club_id is not null;

create or replace function force_unverified_listing()
  returns trigger language plpgsql security invoker
  set search_path = public
as $$
begin
  if pg_trigger_depth() = 1
     and current_user in ('anon', 'authenticated') then
    new.is_verified := false;
    if tg_op = 'INSERT' then
      new.route_id := null;
      new.organiser_club_id := null;
      new.course_source := null;
      new.course_checked_at := null;
      new.course_updated_at := null;
    else
      new.route_id := old.route_id;
      new.organiser_club_id := old.organiser_club_id;
      new.course_source := old.course_source;
      new.course_checked_at := old.course_checked_at;
      new.course_updated_at := old.course_updated_at;
    end if;
  end if;
  return new;
end;
$$;

-- ── audit ───────────────────────────────────────────────────────────────────

create table race_listing_audit (
  id         bigint generated always as identity primary key,
  listing_id uuid not null references race_listings (id) on delete cascade,
  club_id    uuid references clubs (id) on delete set null,
  actor_id   uuid references auth.users (id) on delete set null,
  action     text not null,
  route_id   uuid,
  created_at timestamptz not null default now(),
  constraint race_listing_audit_action_check
    check (action in ('claim', 'link', 'unlink', 'suggestion_approved', 'suggestion_rejected'))
);

create index race_listing_audit_listing_idx on race_listing_audit (listing_id, created_at desc);
create index race_listing_audit_club_id_idx on race_listing_audit (club_id);
create index race_listing_audit_actor_id_idx on race_listing_audit (actor_id);

alter table race_listing_audit enable row level security;

-- Written only by the definer RPCs below. A member reads the entries they
-- made (the data export reads the same rows); nobody else reads any.
create policy "actors read own race listing audit"
  on race_listing_audit for select to authenticated
  using (actor_id = (select auth.uid()));

grant select on public.race_listing_audit to authenticated;
grant select, insert, update, delete on public.race_listing_audit to service_role;

-- ── course suggestions ──────────────────────────────────────────────────────

create table race_course_suggestions (
  id          uuid primary key default gen_random_uuid(),
  listing_id  uuid not null references race_listings (id) on delete cascade,
  route_id    uuid not null references routes (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  note        text,
  status      text not null default 'pending',
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at  timestamptz not null default now(),
  constraint race_course_suggestions_status_check
    check (status in ('pending', 'approved', 'rejected')),
  constraint race_course_suggestions_note_length_check
    check (note is null or char_length(note) <= 500)
);

-- One open suggestion per runner per race; suggesting again replaces it.
create unique index race_course_suggestions_one_pending
  on race_course_suggestions (listing_id, user_id)
  where status = 'pending';
create index race_course_suggestions_listing_idx
  on race_course_suggestions (listing_id, created_at)
  where status = 'pending';
create index race_course_suggestions_route_id_idx on race_course_suggestions (route_id);
create index race_course_suggestions_user_id_idx on race_course_suggestions (user_id);
create index race_course_suggestions_reviewed_by_idx on race_course_suggestions (reviewed_by);

alter table race_course_suggestions enable row level security;

-- The suggester reads and withdraws their own; every other write is an RPC.
create policy "suggesters read own course suggestions"
  on race_course_suggestions for select to authenticated
  using (user_id = (select auth.uid()));

create policy "suggesters withdraw own pending course suggestions"
  on race_course_suggestions for delete to authenticated
  using (user_id = (select auth.uid()) and status = 'pending');

grant select, delete on public.race_course_suggestions to authenticated;
grant select, insert, update, delete on public.race_course_suggestions to service_role;

-- ── helpers ─────────────────────────────────────────────────────────────────

-- Links (or, with a null route, unlinks) a course after every check the
-- caller-facing RPCs share. Never callable by a client: the caller-identity
-- check is the RPC's, made before this runs.
create or replace function private.apply_race_course_link(
  p_listing_id uuid,
  p_club_id uuid,
  p_route_id uuid,
  p_source text,
  p_actor uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_route_id is null then
    update race_listings
       set route_id = null,
           course_source = null,
           course_checked_at = null,
           course_updated_at = null
     where id = p_listing_id;
  else
    if p_source is null or p_source not in ('official', 'traced') then
      raise exception 'course source must be official or traced'
        using errcode = '22023';
    end if;
    if not exists (
      select 1 from routes r
       where r.id = p_route_id
         and r.is_public = true
         and r.shadow_hidden = false
         and r.club_id = p_club_id
    ) then
      raise exception 'the course must be a public route owned by the organiser club'
        using errcode = '42501';
    end if;
    update race_listings
       set route_id = p_route_id,
           course_source = p_source,
           course_checked_at = now(),
           course_updated_at = null
     where id = p_listing_id;
  end if;

  insert into race_listing_audit (listing_id, club_id, actor_id, action, route_id)
  values (p_listing_id, p_club_id, p_actor, p_action, p_route_id);
end;
$$;

revoke execute on function private.apply_race_course_link(uuid, uuid, uuid, text, uuid, text)
  from public, anon, authenticated;

-- ── RPCs ────────────────────────────────────────────────────────────────────

create or replace function claim_race_listing(p_listing_id uuid, p_club_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_current uuid;
begin
  if v_uid is null then
    raise exception 'sign in to claim a race' using errcode = '42501';
  end if;
  if not private.is_official_publisher(p_club_id, v_uid) then
    raise exception 'only an owner or admin of a verified club can claim a race'
      using errcode = '42501';
  end if;

  select organiser_club_id into v_current
    from race_listings where id = p_listing_id
    for update;
  if not found then
    raise exception 'race listing not found' using errcode = 'P0002';
  end if;
  if v_current is not null then
    if v_current = p_club_id then
      return;
    end if;
    raise exception 'this race is already claimed by another club'
      using errcode = '23505';
  end if;

  update race_listings
     set organiser_club_id = p_club_id,
         is_verified = true
   where id = p_listing_id;

  insert into race_listing_audit (listing_id, club_id, actor_id, action)
  values (p_listing_id, p_club_id, v_uid, 'claim');
end;
$$;

revoke execute on function claim_race_listing(uuid, uuid) from public, anon;
grant execute on function claim_race_listing(uuid, uuid) to authenticated;

create or replace function link_race_course(
  p_listing_id uuid,
  p_route_id uuid,
  p_source text default 'official'
)
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
    raise exception 'sign in to link a course' using errcode = '42501';
  end if;

  select organiser_club_id into v_club
    from race_listings where id = p_listing_id
    for update;
  if not found then
    raise exception 'race listing not found' using errcode = 'P0002';
  end if;
  if v_club is null or not private.is_official_publisher(v_club, v_uid) then
    raise exception 'only an owner or admin of the race''s verified organiser club can link its course'
      using errcode = '42501';
  end if;

  perform private.apply_race_course_link(
    p_listing_id, v_club, p_route_id, p_source, v_uid,
    case when p_route_id is null then 'unlink' else 'link' end
  );
end;
$$;

revoke execute on function link_race_course(uuid, uuid, text) from public, anon;
grant execute on function link_race_course(uuid, uuid, text) to authenticated;

create or replace function suggest_race_course(
  p_listing_id uuid,
  p_route_id uuid,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_note text := nullif(btrim(p_note), '');
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'sign in to suggest a course' using errcode = '42501';
  end if;
  if not exists (select 1 from race_listings where id = p_listing_id) then
    raise exception 'race listing not found' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from routes r
     where r.id = p_route_id and r.is_public = true and r.shadow_hidden = false
  ) then
    raise exception 'only a public route can be suggested as a course'
      using errcode = '42501';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'the note is longer than 500 characters' using errcode = '22001';
  end if;

  insert into race_course_suggestions (listing_id, route_id, user_id, note)
  values (p_listing_id, p_route_id, v_uid, v_note)
  on conflict (listing_id, user_id) where status = 'pending'
  do update set route_id = excluded.route_id,
                note = excluded.note,
                created_at = now()
  returning id into v_id;
  return v_id;
end;
$$;

revoke execute on function suggest_race_course(uuid, uuid, text) from public, anon;
grant execute on function suggest_race_course(uuid, uuid, text) to authenticated;

create or replace function review_race_course_suggestion(
  p_suggestion_id uuid,
  p_approve boolean,
  p_route_id uuid default null,
  p_source text default 'official'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_listing uuid;
  v_route uuid;
  v_status text;
  v_club uuid;
begin
  if v_uid is null then
    raise exception 'sign in to review a suggestion' using errcode = '42501';
  end if;
  if p_approve is null then
    raise exception 'approve must be true or false' using errcode = '22023';
  end if;

  select s.listing_id, s.route_id, s.status
    into v_listing, v_route, v_status
    from race_course_suggestions s
   where s.id = p_suggestion_id
   for update;
  if not found then
    raise exception 'suggestion not found' using errcode = 'P0002';
  end if;

  select organiser_club_id into v_club
    from race_listings where id = v_listing
    for update;
  if v_club is null or not private.is_official_publisher(v_club, v_uid) then
    raise exception 'only an owner or admin of the race''s verified organiser club can review its suggestions'
      using errcode = '42501';
  end if;
  if v_status <> 'pending' then
    raise exception 'this suggestion has already been reviewed' using errcode = '23505';
  end if;

  if p_approve then
    perform private.apply_race_course_link(
      v_listing, v_club, coalesce(p_route_id, v_route), p_source, v_uid, 'suggestion_approved'
    );
  else
    insert into race_listing_audit (listing_id, club_id, actor_id, action, route_id)
    values (v_listing, v_club, v_uid, 'suggestion_rejected', v_route);
  end if;

  update race_course_suggestions
     set status = case when p_approve then 'approved' else 'rejected' end,
         reviewed_by = v_uid,
         reviewed_at = now()
   where id = p_suggestion_id;
end;
$$;

revoke execute on function review_race_course_suggestion(uuid, boolean, uuid, text) from public, anon;
grant execute on function review_race_course_suggestion(uuid, boolean, uuid, text) to authenticated;

create or replace function race_course_suggestions_for_review(p_listing_id uuid)
returns table (
  id          uuid,
  route_id    uuid,
  route_name  text,
  route_club_id uuid,
  note        text,
  created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_club uuid;
begin
  if v_uid is null then
    return;
  end if;
  select l.organiser_club_id into v_club from race_listings l where l.id = p_listing_id;
  if not found then
    return;
  end if;
  if v_club is not null then
    if not private.is_official_publisher(v_club, v_uid) then
      return;
    end if;
  elsif not exists (
    select 1 from club_members m
     where m.user_id = v_uid
       and m.status = 'active'
       and m.role in ('owner', 'admin')
       and private.is_official_publisher(m.club_id, v_uid)
  ) then
    return;
  end if;

  return query
    select s.id, s.route_id, r.name, r.club_id, s.note, s.created_at
      from race_course_suggestions s
      join routes r on r.id = s.route_id
     where s.listing_id = p_listing_id
       and s.status = 'pending'
       and r.is_public = true
       and r.shadow_hidden = false
     order by s.created_at;
end;
$$;

revoke execute on function race_course_suggestions_for_review(uuid) from public, anon;
grant execute on function race_course_suggestions_for_review(uuid) to authenticated;

-- ── decision 4: a linked route's edit is flagged ────────────────────────────

create or replace function routes_flag_linked_race_course()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update race_listings
     set course_updated_at = now()
   where route_id = new.id;
  return null;
end;
$$;

revoke execute on function routes_flag_linked_race_course() from public, anon, authenticated;

create trigger routes_flag_linked_race_course
  after update of waypoints on routes
  for each row
  when (old.waypoints is distinct from new.waypoints)
  execute function routes_flag_linked_race_course();

-- ── the public view ─────────────────────────────────────────────────────────

create or replace view public_race_listings as
select
  l.id,
  l.provider,
  l.provider_race_id,
  l.name,
  l.race_date,
  l.distance_m,
  l.location_label,
  l.location_point,
  l.entry_url,
  l.results_url,
  l.is_verified,
  l.created_at,
  l.updated_at,
  coalesce(c.official_distance_m, c.distance_m)::numeric(10, 2) as course_distance_m,
  c.elevation_m as course_elevation_m,
  c.surface as course_surface,
  c.id as course_route_id,
  oc.id as organiser_club_id,
  oc.name as organiser_club_name,
  oc.slug as organiser_club_slug,
  case when c.id is not null then l.course_source end as course_source,
  case when c.id is not null then l.course_checked_at end as course_checked_at,
  case when c.id is not null then l.course_updated_at end as course_updated_at
from race_listings l
left join public_routes c on c.id = l.route_id
left join clubs oc
  on oc.id = l.organiser_club_id
 and oc.is_public = true
 and oc.shadow_hidden = false;

revoke all on public.public_race_listings from public, anon, authenticated;
grant select on public.public_race_listings to anon, authenticated;
