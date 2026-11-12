-- A class event attaches a gym routine (decisions § 1869).
--
-- A class already carries `gym_template` (a `{discipline, duration_min}` hint)
-- and `session_plan_id` (a timed yoga / pilates sequence). A strength or HIIT
-- class needs the load-bearing content instead: exercises x sets x reps x load,
-- which is a `gym_routines` row. Attaching one is a READ of that routine, never
-- a clone into each attendee's library: Log-as-workout pre-fills the
-- attendee's own gym workout from it, and "Save as routine" gives anyone a
-- personal copy on request.
--
-- 1. events.gym_routine_id, nullable, `on delete set null` (deleting the
--    template leaves the class standing, just un-attached), with a partial
--    covering index and the column grant every client-read events column needs
--    under the 20260818_001 column-level SELECT lockdown. An FK id carries no
--    PII; row visibility still flows through the events SELECT policy.
--
-- 2. private.enforce_event_gym_routine_organiser(), a BEFORE trigger in the
--    shape of enforce_event_session_plan_organiser, with one rule that one
--    lacks. Only an event organiser may change the attachment (trusted callers
--    bypass that half), and EVERY writer must attach a routine every attendee
--    can read: a template of the event's own club (`club_id = events.club_id`,
--    readable by its members) or a public template (readable by any signed-in
--    user). A host's personal routine would otherwise attach and then read as
--    nothing to everyone else, and another club's template would read as
--    nothing to this club's members. It also fires on a change of
--    `events.club_id`, so moving an event cannot strand a club template in a
--    club whose members cannot read it.
--
-- 3. events_one_class_content, a CHECK that a row carries at most one of
--    session_plan_id / gym_routine_id: the attendee's Log-as-workout seeds
--    from one source. Added NOT VALID here and VALIDATEd in 20270803000002, a
--    separate transaction, per docs/backend/migration_locks.md.
--
-- Locks: ADD COLUMN of a nullable column with no default is catalogue-only; its
-- FK takes SHARE ROW EXCLUSIVE on gym_routines briefly and has no rows to
-- check. CREATE INDEX on `events` (a bounded config table, not on the guarded
-- list) and CREATE TRIGGER are brief. The CHECK is NOT VALID, so no scan here.

alter table public.events
  add column gym_routine_id uuid references public.gym_routines (id) on delete set null;

create index events_gym_routine_idx on public.events (gym_routine_id)
  where gym_routine_id is not null;

grant select (gym_routine_id) on public.events to authenticated, anon;

create or replace function private.enforce_event_gym_routine_organiser()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_routine_club uuid;
  v_routine_public boolean;
begin
  if new.gym_routine_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.gym_routine_id is not distinct from old.gym_routine_id
     and new.club_id is not distinct from old.club_id then
    return new;
  end if;

  -- The organiser half has the lock_event_order_status trusted-caller bypass
  -- (service role, or direct SQL from migrations + seed). The readability half
  -- below does not: it is a data rule, not an authorisation one.
  if not (v_role = 'service_role'
          or (v_role = '' and session_user in ('postgres', 'supabase_admin')))
     and (tg_op = 'INSERT' or new.gym_routine_id is distinct from old.gym_routine_id)
     and not is_event_organiser(new.club_id) then
    raise exception 'only an event organiser may change the gym routine for event %', new.id
      using errcode = '42501';
  end if;

  select r.club_id, r.is_public_template
    into v_routine_club, v_routine_public
    from gym_routines r
   where r.id = new.gym_routine_id;

  if not found then
    raise exception 'gym routine % does not exist', new.gym_routine_id
      using errcode = '23503';
  end if;

  if v_routine_club is distinct from new.club_id and not v_routine_public then
    raise exception 'a class can attach only a template of its own club or a public template'
      using errcode = '42501',
            hint = 'Publish the routine to this club, or to the public library, first.';
  end if;
  return new;
end;
$$;

revoke execute on function private.enforce_event_gym_routine_organiser() from public, anon;

create trigger events_gym_routine_organiser
  before insert or update of gym_routine_id, club_id on public.events
  for each row execute function private.enforce_event_gym_routine_organiser();

alter table public.events
  add constraint events_one_class_content
  check (num_nonnulls(session_plan_id, gym_routine_id) <= 1)
  not valid;
