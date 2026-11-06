-- Moving an event moves its upcoming RSVPs with it (decisions § 2352, issue
-- #1300 BUG-015).
--
-- Every RSVP, waitlist entry and paid order is keyed to one occurrence by
-- (event_id, instance_start). An edit that changed `starts_at` (or a series'
-- rule) left those rows on an instant the event no longer produces, so the
-- roster read empty and every attendee silently lost their place. The web
-- editor also re-sent a minute-truncated start on every save, so an edit
-- that touched only the description could do it.
--
--   1. `private.move_rescheduled_event_rows` (AFTER UPDATE on events, only
--      when the start, zone or rule actually changed) moves the rows of each
--      UPCOMING occurrence (instance_start >= now()) to the matching
--      occurrence of the edited event. A past occurrence is history and is
--      left where it is.
--        * A one-off moves to the new start.
--        * A timezoned series is paired by occurrence index, using the one
--          expansion the server already has (`private.recurrence_occurrences`,
--          20270808000011): the i-th occurrence of the old rule moves to the
--          (i + k)-th of the new one. k is either 0 (counted from the series
--          start: a time-of-day change, a not-yet-started series moved a few
--          days) or the offset that pairs the next upcoming old occurrence
--          with the next upcoming new one (a running series restarted from a
--          later date), whichever moves the keyed rows least; a tie takes the
--          second. The pairing is strictly increasing, so two occurrences
--          never fold onto one key.
--        * A key the old rule does not produce (a legacy series with no zone,
--          whose instants were minted in each viewer's zone, or a UTC-clock
--          instant from before § 1918) moves by the start's delta, but only
--          when the rule itself is unchanged; there is nothing else to pair
--          it by.
--      The move itself is `private.recurrence_move_key`, the per-key mover the
--      § 1918 remap uses: every instance-keyed table, in the order their
--      triggers need (pricing and orders before the `going` rows a paid
--      order backs), a row whose target is already held by the same identity
--      left in place. A refusal from any of those tables aborts the edit
--      rather than strand the rows it could not move.
--   2. `lock_event_order_status` lets that move rewrite an order's
--      `instance_start` and nothing else. The organiser's request carries an
--      `authenticated` role claim, which the ledger lock refuses for every
--      column but the buyer's refund stamp; the mover sets the transaction-
--      local `threkir.event_reschedule` to the event id for the span of the
--      move (the `threkir.plan_matcher` pattern, 20270901000001), and the lock
--      accepts an update that changes only `instance_start` of an order on
--      that event. `event_orders_validate_occurrence` still requires the new
--      instant to be a real occurrence.
--
-- Queuing an "event rescheduled" notice to the moved attendees is a separate
-- item (BUG-016 adds the notification kind); this migration only keeps their
-- places.
--
-- Locks: CREATE OR REPLACE FUNCTION takes no table lock. CREATE TRIGGER takes
-- SHARE ROW EXCLUSIVE on `events` for a catalogue-only change (no scan, no
-- rewrite), blocking concurrent event writes for an O(1) moment. No column is
-- added or changed, so neither type generator has anything to regenerate.

-- ── 1. the ledger lock admits the reschedule move ──────────────────────────

create or replace function lock_event_order_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- Trusted callers, unchanged: the REST service role (the webhook), or
  -- genuine direct SQL (migrations + seed) which reach here with an empty role
  -- claim AND a privileged session_user. PostgREST authenticates every request
  -- as the `authenticator` login role, so an end-user request can never present
  -- session_user = postgres.
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin')) then
    return new;
  end if;

  -- An organiser's event edit moving this order with its occurrence
  -- (private.move_rescheduled_event_rows sets the flag for the move only).
  if tg_op = 'UPDATE'
     and coalesce(current_setting('threkir.event_reschedule', true), '') = old.event_id::text
     and to_jsonb(new) - 'instance_start' = to_jsonb(old) - 'instance_start' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    raise exception 'event_orders is service-role-only (webhook is the sole writer)'
      using errcode = '42501';
  end if;

  if old.status is distinct from new.status then
    raise exception 'event_orders.status is read-only for non-service-role callers'
      using errcode = '42501';
  end if;

  -- The allowlist. Comparing the two row images with the permitted column
  -- removed from each covers every column the table has now and every one it
  -- gains later, including the primary key.
  if to_jsonb(new) - 'refund_initiated_at' is distinct from to_jsonb(old) - 'refund_initiated_at' then
    raise exception 'event_orders is service-role-only except the buyer refund stamp'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ── 2. the mover ────────────────────────────────────────────────────────────

create or replace function private.move_rescheduled_event_rows()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now       timestamptz := now();
  v_delta     interval := new.starts_at - old.starts_at;
  v_same_rule boolean :=
        old.recurrence_freq  is not distinct from new.recurrence_freq
    and old.recurrence_byday is not distinct from new.recurrence_byday
    and old.recurrence_until is not distinct from new.recurrence_until
    and old.recurrence_count is not distinct from new.recurrence_count
    and old.timezone         is not distinct from new.timezone;
  v_keys      timestamptz[];
  v_old       timestamptz[] := '{}';
  v_new       timestamptz[] := '{}';
  v_old_first int;
  v_new_first int;
  v_shift     int := 0;
  v_from      timestamptz[] := '{}';
  v_to        timestamptz[] := '{}';
  v_pair      record;
  v_refused   text[] := '{}';
begin
  select array_agg(distinct k order by k) into v_keys from (
              select instance_start k from public.event_pricing where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.event_orders where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.event_exceptions where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.race_sessions where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.event_attendees where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.event_results where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.checkpoint_crossings where event_id = new.id and instance_start >= v_now
    union all select instance_start from public.race_pings where event_id = new.id and instance_start >= v_now
    union all select event_instance_start from public.run_photos where event_id = new.id and event_instance_start >= v_now
    union all select event_instance_start from public.club_posts where event_id = new.id and event_instance_start >= v_now
    union all select event_instance_start from public.notifications where event_id = new.id and event_instance_start >= v_now
  ) s;
  if v_keys is null then
    return null;
  end if;

  if old.recurrence_freq is null then
    v_old := array[old.starts_at];
    v_new := array[new.starts_at];
  elsif old.timezone is not null and (new.recurrence_freq is null or new.timezone is not null) then
    v_old := array(select private.recurrence_occurrences(
      old.starts_at, old.recurrence_freq, old.recurrence_byday, old.recurrence_until,
      old.recurrence_count, private.recurrence_zone(old.timezone),
      '-infinity', v_keys[cardinality(v_keys)]));
    v_new := array(select private.recurrence_occurrences(
      new.starts_at, new.recurrence_freq, new.recurrence_byday, new.recurrence_until,
      new.recurrence_count, private.recurrence_zone(coalesce(new.timezone, old.timezone)),
      '-infinity',
      greatest(v_keys[cardinality(v_keys)], new.starts_at)
        + greatest(v_delta, -v_delta) + interval '400 days'));

    select min(o.i) into v_old_first
      from unnest(v_old) with ordinality as o(at, i) where o.at >= v_now;
    select min(o.i) into v_new_first
      from unnest(v_new) with ordinality as o(at, i) where o.at >= v_now;

    select c.k into v_shift
      from (values (0, 0), (v_new_first - v_old_first, 1)) as c(k, pref)
     where c.k is not null
     order by (select sum(case when o.i + c.k between 1 and cardinality(v_new)
                               then abs(extract(epoch from v_new[o.i + c.k] - o.at))
                               else 31 * 86400 end)
                 from unnest(v_old) with ordinality as o(at, i)
                where o.at = any (v_keys)),
              c.pref desc
     limit 1;
  end if;

  select coalesce(array_agg(p.from_at), '{}'), coalesce(array_agg(p.to_at), '{}')
    into v_from, v_to
    from (
      select o.at as from_at, v_new[o.i + v_shift] as to_at
        from unnest(v_old) with ordinality as o(at, i)
       where o.at = any (v_keys)
         and o.i + v_shift between 1 and cardinality(v_new)
      union all
      select k, k + v_delta
        from unnest(v_keys) k
       where v_same_rule
         and not (k = any (v_old))
    ) p
   where p.from_at <> p.to_at;

  if cardinality(v_from) = 0 then
    return null;
  end if;

  perform set_config('threkir.event_reschedule', new.id::text, true);
  -- Up-moves from the latest down, down-moves from the earliest up, as the
  -- § 1918 remap orders them: a key's rows only ever move onto a key whose own
  -- rows have already left it.
  for v_pair in
    select f.at as from_at, v_to[f.i] as to_at
      from unnest(v_from) with ordinality as f(at, i)
     order by (v_to[f.i] > f.at) desc,
              case when v_to[f.i] > f.at then f.at end desc,
              f.at asc
  loop
    v_refused := private.recurrence_move_key(new.id, v_pair.from_at, v_pair.to_at, v_refused);
  end loop;
  perform set_config('threkir.event_reschedule', '', true);

  if cardinality(v_refused) > 0 then
    raise exception 'event % cannot move: % of its upcoming rows could not follow it (%)',
      new.id, cardinality(v_refused), array_to_string(v_refused, '; ')
      using errcode = 'check_violation';
  end if;
  return null;
end;
$$;

revoke execute on function private.move_rescheduled_event_rows() from public, anon, authenticated;

create trigger events_move_rescheduled_rows
  after update of starts_at, timezone, recurrence_freq, recurrence_byday,
                  recurrence_until, recurrence_count on public.events
  for each row
  when (old.starts_at        is distinct from new.starts_at
     or old.timezone         is distinct from new.timezone
     or old.recurrence_freq  is distinct from new.recurrence_freq
     or old.recurrence_byday is distinct from new.recurrence_byday
     or old.recurrence_until is distinct from new.recurrence_until
     or old.recurrence_count is distinct from new.recurrence_count)
  execute function private.move_rescheduled_event_rows();
