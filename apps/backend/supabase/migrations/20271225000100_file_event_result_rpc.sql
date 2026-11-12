-- A runner files their own race result through public.file_event_result
-- instead of a PostgREST upsert on event_results (decisions § 2474, step two).
--
-- 20271224000700 left authenticated able to SELECT eight columns the redacted
-- view withholds (age_grade_pct, note, run_id, start_at, finish_at,
-- start_detection, finish_detection, clock_offset_ms) because every client
-- files with PostgREST's merge upsert, which writes
-- ON CONFLICT DO UPDATE SET col = EXCLUDED.col for every body column, and
-- PostgreSQL requires SELECT on each column read from EXCLUDED. This function
-- runs that same statement as its owner, so once every supported build calls
-- it the eight can be revoked from authenticated (docs/ops/releasing.md).
-- This migration revokes nothing: released builds still upsert.
--
-- The body is the upsert the clients sent, unchanged in shape, so the result
-- reaches the database exactly as before:
--   * The same columns. Only the keys the caller sent are inserted and, on a
--     conflict, set from EXCLUDED; an omitted column keeps its stored value,
--     which the clients rely on (a Wear result never writes a null course over
--     a host's correction).
--   * The same triggers. Nothing here bypasses them: the BEFORE INSERT
--     triggers see the proposed row (the race guard's normalisation, window
--     lock of § 1849 / § 2471 and course check; the athletic-event check; the
--     approval default), the BEFORE UPDATE race guard sees the conflict update
--     (the approval reset of § 2474), and the rerank trigger fires after. They
--     read the caller from auth.uid() and the JWT claims, which a definer
--     function leaves as they were.
--
-- What RLS decided for the upsert is decided here, because the owner bypasses
-- it. Under the caller's RLS the upsert passed when the row was the caller's
-- own (event_results_insert_self / _update_self_or_director: user_id =
-- auth.uid()) and the event was one the caller can see (insert_self's club
-- test evaluated over events and clubs under their own RLS, and the SELECT
-- policy the conflict path applies to the stored row). Both reduce to
-- private.is_event_visible_to(event, caller), the helper that mirrors the
-- events SELECT policy, so the function calls it rather than copying the
-- predicates (the drift 20260818_001 records). The function narrows the rest:
--   * user_id is the caller, always; a body naming anyone else is refused.
--   * Only the columns a runner's result carries may be sent. A key outside
--     that list (organiser_approved, needs_review, rank, bib, id, ...) is
--     refused rather than ignored, so a client bug is loud.
--   * No caller, no call: auth.uid() null raises 'not authenticated', and
--     EXECUTE is granted to authenticated alone.
--
-- Locks: a function only; no table lock.

create or replace function public.file_event_result(p_result jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_allowed constant text[] := array[
    'event_id', 'instance_start', 'user_id', 'run_id', 'duration_s', 'distance_m',
    'finisher_status', 'age_grade_pct', 'note', 'course_id', 'gun_time_s', 'chip_time_s',
    'finish_method', 'start_at', 'finish_at', 'start_detection', 'finish_detection',
    'clock_offset_ms', 'updated_at'
  ];
  v_body jsonb;
  v_bad text;
  v_event uuid;
  v_cols text;
  v_set text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_result is null or jsonb_typeof(p_result) <> 'object' then
    raise exception 'file_event_result: the result must be a JSON object'
      using errcode = '22023';
  end if;

  select min(k) into v_bad
    from jsonb_object_keys(p_result) k
   where k <> all (v_allowed);
  if v_bad is not null then
    raise exception 'file_event_result: % is not a column a runner files', v_bad
      using errcode = '42501';
  end if;

  if p_result ? 'user_id' and (p_result ->> 'user_id') is distinct from v_uid::text then
    raise exception 'file_event_result: a runner files only their own result'
      using errcode = '42501';
  end if;

  v_body := p_result || jsonb_build_object('user_id', v_uid);
  v_event := (v_body ->> 'event_id')::uuid;

  if v_event is null or not private.is_event_visible_to(v_event, v_uid) then
    raise exception 'new row violates row-level security policy for table "event_results"'
      using errcode = '42501';
  end if;

  select string_agg(format('%I', k), ', ' order by k),
         string_agg(format('%I = excluded.%I', k, k), ', ' order by k)
           filter (where k not in ('event_id', 'instance_start', 'user_id'))
    into v_cols, v_set
    from jsonb_object_keys(v_body) k;

  execute format(
    'insert into public.event_results as r (%1$s) '
    'select %1$s from jsonb_populate_record(null::public.event_results, $1) '
    'on conflict on constraint event_results_account_uniq do %2$s',
    v_cols,
    case when v_set is null then 'nothing' else 'update set ' || v_set end
  ) using v_body;
end;
$$;

revoke all on function public.file_event_result(jsonb) from public, anon, service_role;
grant execute on function public.file_event_result(jsonb) to authenticated;

comment on function public.file_event_result(jsonb) is
  'File or re-file the caller''s own event result: the PostgREST merge upsert '
  'on (event_id, instance_start, user_id) the clients sent, run as the owner '
  'so the caller needs no SELECT on the columns it writes back from EXCLUDED. '
  'Keys outside the runner''s columns are refused; user_id is the caller; the '
  'event must be visible to the caller (private.is_event_visible_to); every '
  'event_results trigger fires as for the upsert (20271225000100, decisions '
  '§ 2474).';
