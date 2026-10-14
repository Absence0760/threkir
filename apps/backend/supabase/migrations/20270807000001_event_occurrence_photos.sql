-- Event photos: organiser/host photos per occurrence, organiser moderation,
-- and integrity checks on attendee photos (issue #1150, decisions § 1905).
--
-- Model: a host photo is a `run_photos` row with `run_id` NULL. Keeping it in
-- the one table means the bucket, the path-shape CHECKs, the EXIF-strip +
-- thumbnail job (the AFTER INSERT trigger enqueues `photo_process` for every
-- row, and the worker keys on the photo id, never the run), the Art 20 export
-- (`run_photos.json` is selected by `owner_id`) and the Art 17 drain (the row
-- cascades with `owner_id`; the bytes sit under `{owner_id}/`) all cover host
-- photos with no new code. A sibling table would have needed each of those
-- re-done and a union on every gallery read.
--
--   1. `run_id` drops NOT NULL. A run-less row must carry an occurrence
--      (`run_photos_runless_has_occurrence`, NOT VALID here, VALIDATE in
--      20270807000002). The CHECK names `event_instance_start` rather than
--      `event_id` on purpose: `event_id` is `on delete set null`, so deleting
--      an event detaches its host photos instead of failing the delete. A
--      detached row stays its owner's (owner SELECT policy, export, erasure).
--   2. `hidden_at` / `hidden_by`: the organiser's soft hide. A hidden photo
--      leaves the event gallery for everyone but its owner and the event's
--      stewards. An attendee's photo stays on their own run — the run-path
--      SELECT policy is untouched — because the organiser's authority is over
--      the event page, not over a runner's run. Written only through
--      `set_event_photo_hidden`; a direct UPDATE is refused by the trigger.
--   3. `private.is_event_occurrence(event, instant)`: the server-side
--      occurrence check. No SQL expansion existed (`expandInstances` lives in
--      web recurrence.ts + mobile recurrence.dart), so this ports its
--      membership test: a one-off is its `starts_at`; a recurring series with
--      a `timezone` is walked on the UTC clock exactly as the clients do. A
--      legacy series with no timezone was expanded in each viewer's local
--      zone, so no single instant is canonical; it is held to the bounds and
--      to a whole-day offset from `starts_at` (±1 h for a DST shift).
--   4. The photo window (`private.event_photo_window_*`): an attendee's run
--      must START within [occurrence − 2 h, occurrence + 24 h). −2 h covers
--      arriving early and recording the warm-up; +24 h covers a late wave, a
--      run recorded after the group run, and a day-long ultra. A run that
--      starts a day later is a different outing. A host photo may be added
--      from occurrence − 2 h onwards (set-up shots), never for an occurrence
--      that is still further away. Mirrored by `event_photo_window.ts` /
--      `event_photo_window.dart` so the run picker only offers runs the
--      database will accept.
--   5. RLS: a steward (club owner / admin / event_organiser, or the event's
--      `host_user_id`) inserts run-less photos for their event; owners keep
--      their delete; nobody but the owner and the run owner deletes a row.
--
-- Locks: DROP NOT NULL and ADD COLUMN (no default) are catalogue-only;
-- the CHECK is NOT VALID (no scan); CREATE TRIGGER takes SHARE ROW EXCLUSIVE
-- for an O(1) change; policy and function DDL take no table scan.

-- ── 1. run_id becomes optional ──────────────────────────────────────────────

alter table public.run_photos alter column run_id drop not null;

alter table public.run_photos
  add constraint run_photos_runless_has_occurrence
  check (run_id is not null or event_instance_start is not null) not valid;

-- ── 2. moderation columns ───────────────────────────────────────────────────

alter table public.run_photos
  add column hidden_at timestamptz,
  add column hidden_by uuid references auth.users(id) on delete set null;

-- ── 3. occurrence + steward + window helpers ────────────────────────────────

create or replace function private.is_event_occurrence(p_event_id uuid, p_instance timestamptz)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  e            record;
  v_start_sec  timestamptz;
  v_start_utc  timestamp;
  v_inst_utc   timestamp;
  v_codes      text[] := array['MO','TU','WE','TH','FR','SA','SU'];
  v_byday      text[];
  v_step_weeks int;
  v_anchor     date;
  v_day        date;
  v_months     int;
  v_cand       timestamptz;
  v_rem        numeric;
  v_n          bigint;
  v_i          int;
  v_first      date;
begin
  if p_event_id is null or p_instance is null then
    return false;
  end if;

  select starts_at, recurrence_freq, recurrence_byday, recurrence_until,
         recurrence_count, timezone
    into e
    from events
   where id = p_event_id;
  if not found then
    return false;
  end if;

  if e.recurrence_freq is null then
    return p_instance = e.starts_at;
  end if;

  v_start_sec := date_trunc('second', e.starts_at);
  if p_instance < v_start_sec then
    return false;
  end if;
  if e.recurrence_until is not null and p_instance > e.recurrence_until then
    return false;
  end if;

  if e.timezone is null then
    if e.recurrence_freq = 'monthly' then
      return true;
    end if;
    v_rem := mod(extract(epoch from (p_instance - v_start_sec)), 86400);
    return v_rem <= 3600 or v_rem >= 82800;
  end if;

  v_start_utc := v_start_sec at time zone 'UTC';
  v_inst_utc := p_instance at time zone 'UTC';

  if e.recurrence_freq = 'monthly' then
    v_months := (extract(year from v_inst_utc)::int - extract(year from v_start_utc)::int) * 12
              + (extract(month from v_inst_utc)::int - extract(month from v_start_utc)::int);
    if v_months < 0 then
      return false;
    end if;
    if e.recurrence_count is not null and v_months + 1 > e.recurrence_count then
      return false;
    end if;
    v_cand := make_timestamptz(
      extract(year from v_inst_utc)::int,
      extract(month from v_inst_utc)::int,
      least(
        extract(day from v_start_utc)::int,
        extract(day from (date_trunc('month', v_inst_utc) + interval '1 month - 1 day'))::int
      ),
      extract(hour from v_start_utc)::int,
      extract(minute from v_start_utc)::int,
      floor(extract(second from v_start_utc))::double precision,
      'UTC'
    );
    return p_instance = v_cand;
  end if;

  -- weekly / biweekly
  if p_instance <> date_trunc('second', p_instance)
     or v_inst_utc::time <> v_start_utc::time then
    return false;
  end if;
  v_byday := coalesce(
    nullif(e.recurrence_byday, '{}'::text[]),
    array[v_codes[extract(isodow from v_start_utc)::int]]
  );
  v_step_weeks := case when e.recurrence_freq = 'biweekly' then 2 else 1 end;
  v_anchor := v_start_utc::date - (extract(isodow from v_start_utc)::int - 1);
  v_day := v_inst_utc::date;
  if not (v_codes[extract(isodow from v_day)::int] = any (v_byday)) then
    return false;
  end if;
  if ((v_day - v_anchor) / 7) % v_step_weeks <> 0 then
    return false;
  end if;

  -- Counted per weekday in O(1), never walked day by day: p_instance is
  -- client-supplied, and a series with a count and no until would otherwise
  -- let one insert expand a range out to year 9999. The start day itself
  -- always qualifies on time (every occurrence shares its time of day).
  if e.recurrence_count is not null then
    v_n := 0;
    for v_i in 1..7 loop
      continue when not (v_codes[v_i] = any (v_byday));
      v_first := v_start_utc::date + ((v_i - extract(isodow from v_start_utc)::int + 7) % 7);
      v_first := v_first + 7 * (((v_first - v_anchor) / 7) % v_step_weeks);
      if v_first <= v_day then
        v_n := v_n + (v_day - v_first) / (7 * v_step_weeks) + 1;
      end if;
    end loop;
    if v_n > e.recurrence_count then
      return false;
    end if;
  end if;

  return true;
end;
$$;

revoke execute on function private.is_event_occurrence(uuid, timestamptz) from public, anon;
grant execute on function private.is_event_occurrence(uuid, timestamptz) to authenticated, service_role;

-- Who may post and moderate an occurrence's photos: the club's event
-- organisers (the `is_event_organiser` role set, keyed on a given user rather
-- than auth.uid()) and the event's named host.
create or replace function private.is_event_photo_steward(p_event_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null and exists (
    select 1
      from events e
     where e.id = p_event_id
       and (
         e.host_user_id = p_user_id
         or exists (
           select 1 from club_members cm
            where cm.club_id = e.club_id
              and cm.user_id = p_user_id
              and cm.status = 'active'
              and cm.role in ('owner', 'admin', 'event_organiser')
         )
       )
  );
$$;

revoke execute on function private.is_event_photo_steward(uuid, uuid) from public, anon;
grant execute on function private.is_event_photo_steward(uuid, uuid) to anon, authenticated, service_role;

-- The window constants, named once. Mirrored in
-- apps/web/src/lib/social/event_photo_window.ts and
-- apps/mobile_android/lib/event_photo_window.dart.
create or replace function private.event_photo_window_before()
returns interval language sql immutable set search_path = public as $$ select interval '2 hours' $$;

create or replace function private.event_photo_window_after()
returns interval language sql immutable set search_path = public as $$ select interval '24 hours' $$;

revoke execute on function private.event_photo_window_before() from public, anon;
revoke execute on function private.event_photo_window_after() from public, anon;
grant execute on function private.event_photo_window_before() to authenticated, service_role;
grant execute on function private.event_photo_window_after() to authenticated, service_role;

create or replace function private.run_starts_in_event_photo_window(p_run_id uuid, p_instance timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
     where r.id = p_run_id
       and r.started_at >= p_instance - private.event_photo_window_before()
       and r.started_at <  p_instance + private.event_photo_window_after()
  );
$$;

revoke execute on function private.run_starts_in_event_photo_window(uuid, timestamptz) from public, anon;
grant execute on function private.run_starts_in_event_photo_window(uuid, timestamptz) to authenticated, service_role;

-- ── 4. integrity + moderation-column trigger ────────────────────────────────
--
-- Invoker rights on purpose: `current_user` is what tells a direct client
-- UPDATE (authenticated) from `set_event_photo_hidden` (a SECURITY DEFINER
-- body runs as its owner) and from the service role. The helpers it calls are
-- SECURITY DEFINER, so the checks never depend on what the caller can read.
create or replace function public.run_photos_event_integrity()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_privileged boolean := current_user in ('postgres', 'supabase_admin', 'service_role');
begin
  if tg_op = 'UPDATE' then
    if not v_privileged and (
         new.hidden_at is distinct from old.hidden_at
         or new.hidden_by is distinct from old.hidden_by
       ) then
      raise exception 'run_photos.hidden_at is set through set_event_photo_hidden only'
        using errcode = '42501';
    end if;
    -- An event's deletion detaches its photos (event_id set null); that and
    -- an owner untagging their own photo are the only tag changes allowed.
    if new.run_id is distinct from old.run_id
       or new.event_instance_start is distinct from old.event_instance_start
       or (new.event_id is distinct from old.event_id and new.event_id is not null) then
      if not v_privileged then
        raise exception 'a photo''s run and event occurrence are fixed at upload'
          using errcode = '42501';
      end if;
    end if;
    return new;
  end if;

  if not v_privileged and (new.hidden_at is not null or new.hidden_by is not null) then
    raise exception 'a photo cannot be uploaded hidden' using errcode = '42501';
  end if;

  if (new.event_id is null) <> (new.event_instance_start is null) then
    raise exception 'event_id and event_instance_start are set together'
      using errcode = '23514';
  end if;

  if new.event_id is null then
    if new.run_id is null then
      raise exception 'a photo needs a run or an event occurrence'
        using errcode = '23514';
    end if;
    return new;
  end if;

  if not private.is_event_occurrence(new.event_id, new.event_instance_start) then
    raise exception 'event_instance_start is not an occurrence of this event'
      using errcode = '23514';
  end if;

  if new.run_id is null then
    if not private.is_event_photo_steward(new.event_id, new.owner_id) then
      raise exception 'only the event''s organisers or host can post photos without a run'
        using errcode = '42501';
    end if;
    if now() < new.event_instance_start - private.event_photo_window_before() then
      raise exception 'this occurrence has not happened yet'
        using errcode = '23514';
    end if;
  elsif not private.run_starts_in_event_photo_window(new.run_id, new.event_instance_start) then
    raise exception 'that run did not start during this occurrence'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke execute on function public.run_photos_event_integrity() from public, anon, authenticated;

create trigger run_photos_event_integrity_trigger
  before insert or update of run_id, event_id, event_instance_start, hidden_at, hidden_by
  on public.run_photos
  for each row execute function public.run_photos_event_integrity();

-- ── 5. RLS ─────────────────────────────────────────────────────────────────

create policy "event steward attaches occurrence photos"
  on public.run_photos for insert
  to authenticated
  with check (
    owner_id = (select auth.uid())
    and run_id is null
    and event_id is not null
    and private.is_event_photo_steward(event_id, (select auth.uid()))
  );

-- A hidden photo leaves the gallery for everyone but its owner and the
-- event's stewards (who need to see it to restore it).
alter policy "event photos readable when event is readable" on public.run_photos
  using (
    event_id is not null
    and exists (select 1 from public.events e where e.id = run_photos.event_id)
    and (
      hidden_at is null
      or owner_id = (select auth.uid())
      or private.is_event_photo_steward(event_id, (select auth.uid()))
    )
  );

-- A host photo has no run, so the run path never admits its owner; a
-- detached one has no event either.
create policy "photo owner reads own photos"
  on public.run_photos for select
  to authenticated
  using (owner_id = (select auth.uid()));

-- The bytes follow the same three paths as the row (live body 20270416_001).
alter policy "run-photo bytes visible when run or event is visible" on storage.objects
  using (
    bucket_id = 'run-photos'
    and exists (
      select 1
        from public.run_photos rp
       where (rp.storage_path = storage.objects.name or rp.thumb_512_path = storage.objects.name)
         and (
           private.is_run_photo_visible_to(rp.run_id, (select auth.uid()))
           or rp.owner_id = (select auth.uid())
           or (
             rp.event_id is not null
             and exists (select 1 from public.events e where e.id = rp.event_id)
             and (
               rp.hidden_at is null
               or private.is_event_photo_steward(rp.event_id, (select auth.uid()))
             )
           )
         )
    )
  );

-- ── 6. client RPCs ─────────────────────────────────────────────────────────

-- Whether the caller may post run-less photos to and moderate this event's
-- galleries. The host column is not client-readable, so the page asks.
create or replace function public.can_steward_event_photos(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select private.is_event_photo_steward(p_event_id, auth.uid());
$$;

revoke execute on function public.can_steward_event_photos(uuid) from public, anon;
grant execute on function public.can_steward_event_photos(uuid) to authenticated, service_role;

-- Hide (p_hidden = true) or restore a photo in an event gallery. Steward-only.
create or replace function public.set_event_photo_hidden(p_photo_id uuid, p_hidden boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_event_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_hidden is null then
    raise exception 'p_hidden is required' using errcode = '22004';
  end if;

  select event_id into v_event_id from run_photos where id = p_photo_id;
  if v_event_id is null or not private.is_event_photo_steward(v_event_id, v_uid) then
    raise exception 'only the event''s organisers or host can moderate its photos'
      using errcode = '42501';
  end if;

  update run_photos
     set hidden_at = case when p_hidden then now() else null end,
         hidden_by = case when p_hidden then v_uid else null end
   where id = p_photo_id;
end;
$$;

revoke execute on function public.set_event_photo_hidden(uuid, boolean) from public, anon;
grant execute on function public.set_event_photo_hidden(uuid, boolean) to authenticated, service_role;
