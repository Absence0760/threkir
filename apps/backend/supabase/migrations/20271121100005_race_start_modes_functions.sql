-- Race start modes (#1306, decisions § 2400-§ 2401): the functions, triggers,
-- per-minute job and redacted views, moved out of 20271121002400 unchanged.
-- They read the columns 20271121100001-100003 add, so they follow them.
--
-- Locks: CREATE OR REPLACE FUNCTION and VIEW take no lock on a table. Each
-- trigger is drop-then-create (ACCESS EXCLUSIVE, then SHARE ROW EXCLUSIVE, on
-- events and race_sessions, both bounded) so a database that ran the earlier
-- form of 20271121002400 ends in the same state; nothing here scans.

set search_path = public;

-- ─── helpers ───────────────────────────────────────────────────────────────

-- The status a session is in, judged on the server clock rather than on the
-- stored status, which the per-minute job moves up to a minute late. Ping and
-- result writes, the spectator read and the clients all go by this.
create or replace function private.race_session_effective_status(
  p_status text,
  p_mode text,
  p_scheduled_start_at timestamptz,
  p_window_opens_at timestamptz,
  p_window_closes_at timestamptz
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_status in ('finished', 'cancelled') then p_status
    when p_mode = 'host_go' then p_status
    when p_window_closes_at is not null and p_window_closes_at <= now()
         and (p_status = 'running'
              or coalesce(p_scheduled_start_at, p_window_opens_at) <= now())
      then 'finished'
    when p_status = 'armed' and coalesce(p_scheduled_start_at, p_window_opens_at) <= now()
      then 'running'
    else p_status
  end;
$$;

-- anon too: the logged-out spectator page reads race_sessions_redacted, a
-- security-invoker view that calls it.
revoke execute on function private.race_session_effective_status(text, text, timestamptz, timestamptz, timestamptz)
  from public;
grant execute on function private.race_session_effective_status(text, text, timestamptz, timestamptz, timestamptz)
  to anon, authenticated, service_role;

-- The session's settings, as the event says them, for one occurrence.
create or replace function private.race_session_settings(p_event_id uuid, p_instance_start timestamptz)
returns table (
  start_mode text,
  scheduled_start_at timestamptz,
  window_opens_at timestamptz,
  window_closes_at timestamptz,
  auto_approve boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    e.race_start_mode,
    case when e.race_start_mode = 'scheduled'
      then p_instance_start + make_interval(secs => e.race_scheduled_offset_s) end,
    case when e.race_start_mode = 'self_timed'
      then p_instance_start + make_interval(secs => e.race_window_open_offset_s) end,
    case
      when e.race_start_mode = 'scheduled' then
        p_instance_start + make_interval(secs => e.race_scheduled_offset_s + e.race_window_length_s)
      when e.race_start_mode = 'self_timed' then
        p_instance_start + make_interval(secs => e.race_window_open_offset_s + e.race_window_length_s)
    end,
    case e.race_start_mode
      when 'self_timed' then coalesce(e.race_auto_approve, false)
      when 'scheduled' then coalesce(e.race_auto_approve, true)
    end
  from public.events e
  where e.id = p_event_id;
$$;

-- The insert trigger runs as the caller, so the roles that arm a race or
-- create one through an operator path need it. It reads only the event's own
-- race settings.
revoke execute on function private.race_session_settings(uuid, timestamptz) from public, anon;
grant execute on function private.race_session_settings(uuid, timestamptz) to authenticated, service_role;

-- ─── race_sessions triggers ────────────────────────────────────────────────

-- On insert: the mode and its instants come from the event, whatever a client
-- sent, and a scheduled or self-timed race can only be inserted armed (the
-- server fires it). Host GO keeps the organiser's own auto-approve choice.
--
-- On update: a not-yet-started session moved to another instance_start (the
-- BUG-015 mover, the § 1918 remap) carries its instants by the same delta, so
-- an organiser's override survives too. Then, for a client caller only:
--   * the mode and, for Host GO, the instants are the server's;
--   * a scheduled start moves (Delay) only while it is still ahead, to a time
--     still ahead, and the auto-end moves with it;
--   * a self-timed window's opening moves only while it is still ahead, and
--     its close moves with it;
--   * a window's close moves (Extend, or an earlier close) only while it is
--     still ahead, to a time still ahead, at most 7 days after it opened;
--   * ending a scheduled or self-timed race closes its window now.
create or replace function public.race_sessions_apply_start_mode()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_client boolean := current_user in ('anon', 'authenticated');
  v_settings record;
  v_delta interval;
  v_start timestamptz;
begin
  if tg_op = 'INSERT' then
    select * into v_settings
    from private.race_session_settings(new.event_id, new.instance_start);
    if not found then
      return new;
    end if;
    new.start_mode := v_settings.start_mode;
    new.scheduled_start_at := v_settings.scheduled_start_at;
    new.window_opens_at := v_settings.window_opens_at;
    new.window_closes_at := v_settings.window_closes_at;
    if new.start_mode <> 'host_go' then
      new.is_auto_approve := v_settings.auto_approve;
      if v_client and new.status <> 'armed' then
        raise exception 'race_start_mode_server_fires: a % race is started by the server', new.start_mode
          using errcode = 'check_violation';
      end if;
    end if;
    return new;
  end if;

  if new.instance_start is distinct from old.instance_start then
    if old.status = 'armed' then
      v_delta := new.instance_start - old.instance_start;
      new.scheduled_start_at := old.scheduled_start_at + v_delta;
      new.window_opens_at := old.window_opens_at + v_delta;
      new.window_closes_at := old.window_closes_at + v_delta;
    end if;
    return new;
  end if;

  if not v_client then
    return new;
  end if;

  new.start_mode := old.start_mode;

  if old.start_mode = 'host_go' then
    new.scheduled_start_at := null;
    new.window_opens_at := null;
    new.window_closes_at := null;
    return new;
  end if;

  if old.status in ('finished', 'cancelled') then
    if new.scheduled_start_at is distinct from old.scheduled_start_at
       or new.window_opens_at is distinct from old.window_opens_at
       or new.window_closes_at is distinct from old.window_closes_at then
      raise exception 'race_window_closed: the race is %', old.status
        using errcode = 'check_violation';
    end if;
    return new;
  end if;

  if old.start_mode = 'scheduled' then
    new.window_opens_at := null;
    if new.scheduled_start_at is distinct from old.scheduled_start_at then
      if old.status <> 'armed' or old.scheduled_start_at <= now()
         or new.scheduled_start_at is null or new.scheduled_start_at <= now() then
        raise exception 'race_start_passed: a scheduled start can only move while it is still ahead'
          using errcode = 'check_violation';
      end if;
      new.window_closes_at := old.window_closes_at
        + (new.scheduled_start_at - old.scheduled_start_at);
    end if;
  else
    new.scheduled_start_at := null;
    if new.window_opens_at is distinct from old.window_opens_at then
      if old.status <> 'armed' or old.window_opens_at <= now()
         or new.window_opens_at is null or new.window_opens_at <= now() then
        raise exception 'race_start_passed: a window can only move while it has not opened'
          using errcode = 'check_violation';
      end if;
      new.window_closes_at := old.window_closes_at
        + (new.window_opens_at - old.window_opens_at);
    end if;
  end if;

  v_start := coalesce(new.scheduled_start_at, new.window_opens_at);

  if new.window_closes_at is distinct from old.window_closes_at
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.window_opens_at is not distinct from old.window_opens_at then
    if old.window_closes_at <= now()
       or new.window_closes_at is null
       or new.window_closes_at <= now()
       or new.window_closes_at <= v_start
       or new.window_closes_at > v_start + interval '7 days' then
      raise exception 'race_window_invalid: a window closes ahead of now, after it opens and within 7 days'
        using errcode = 'check_violation';
    end if;
  end if;

  if new.status = 'finished' and old.status <> 'finished' then
    new.window_closes_at := greatest(least(old.window_closes_at, now()), v_start + interval '1 second');
  end if;

  return new;
end;
$$;

revoke execute on function public.race_sessions_apply_start_mode() from public, anon, authenticated;

drop trigger if exists race_sessions_apply_start_mode_trg on public.race_sessions;
create trigger race_sessions_apply_start_mode_trg
  before insert or update on public.race_sessions
  for each row execute function public.race_sessions_apply_start_mode();

-- The transitions, now per mode (extends 20260529000003, § 1863):
--   * Host GO is unchanged: armed -> running | cancelled, running -> finished.
--   * Scheduled and Self-timed: only the server moves armed -> running. A
--     client may cancel only while the start (or the window's opening) is
--     still ahead, judged on the clock and not on the stored status (m2), and
--     may end a race that is live by the clock even if the stored status
--     still says armed.
create or replace function public.race_sessions_enforce_transition()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_client boolean := current_user in ('anon', 'authenticated');
  v_start timestamptz;
begin
  if tg_op = 'INSERT' then
    return new;
  end if;

  if old.status = new.status then
    return new;
  end if;

  if old.status in ('finished', 'cancelled') then
    raise exception
      'race_sessions: cannot transition from terminal status %', old.status
      using errcode = 'check_violation';
  end if;

  v_start := coalesce(old.scheduled_start_at, old.window_opens_at);

  if old.start_mode in ('scheduled', 'self_timed') and old.status = 'armed' then
    if new.status = 'running' then
      if v_client then
        raise exception 'race_start_mode_server_fires: a % race is started by the server', old.start_mode
          using errcode = 'check_violation';
      end if;
      return new;
    elsif new.status = 'cancelled' then
      if v_start <= now() then
        raise exception 'race_start_passed: a race whose start has passed is ended, not cancelled'
          using errcode = 'check_violation';
      end if;
      return new;
    elsif new.status = 'finished' then
      if v_start > now() then
        raise exception 'race_sessions: invalid transition armed → finished before the start'
          using errcode = 'check_violation';
      end if;
      return new;
    end if;
  end if;

  case
    when old.status = 'armed' and new.status in ('running', 'cancelled') then
      return new;
    when old.status = 'running' and new.status = 'finished' then
      return new;
    else
      raise exception
        'race_sessions: invalid transition % → %', old.status, new.status
        using errcode = 'check_violation';
  end case;
end;
$$;

-- GO is the server's clock (§ 1851), and for a scheduled or self-timed race
-- it is the scheduled instant or the window's opening, never a client time.
create or replace function public.race_sessions_server_clock()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin'))
  then
    if tg_op = 'UPDATE' and old.status = 'armed' and new.status in ('running', 'finished')
       and new.started_at is null and old.start_mode <> 'host_go' then
      new.started_at := coalesce(old.scheduled_start_at, old.window_opens_at);
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status in ('running', 'finished') then
      new.started_at := now();
    end if;
    if new.status = 'finished' then
      new.finished_at := now();
    end if;
    return new;
  end if;

  if old.status in ('running', 'finished') then
    new.started_at := old.started_at;
  elsif new.status in ('running', 'finished') then
    new.started_at := case old.start_mode
      when 'scheduled' then old.scheduled_start_at
      when 'self_timed' then old.window_opens_at
      else now()
    end;
  end if;

  if old.status = 'finished' then
    new.finished_at := old.finished_at;
  elsif new.status = 'finished' then
    new.finished_at := now();
  end if;

  return new;
end;
$$;

-- A self-timed race freezes its lines when its window opens (M14; § 2391
-- left this call to #1306), whoever moves it: the job, or an operator.
create or replace function public.race_sessions_freeze_at_window_open()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.snapshot_race_session_courses(new.event_id, new.instance_start);
  return null;
end;
$$;

revoke execute on function public.race_sessions_freeze_at_window_open() from public, anon, authenticated;

drop trigger if exists race_sessions_freeze_at_window_open_trg on public.race_sessions;
create trigger race_sessions_freeze_at_window_open_trg
  after update of status on public.race_sessions
  for each row
  when (new.start_mode = 'self_timed' and old.status = 'armed'
        and new.status in ('running', 'finished'))
  execute function public.race_sessions_freeze_at_window_open();

-- A Delay tells everyone going (m4). A move that rides on a reschedule is
-- told by event_updated instead.
create or replace function public.race_sessions_notify_start_moved()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into notifications (user_id, kind, event_id, event_instance_start)
  select a.user_id, 'race_start_moved', new.event_id, new.instance_start
  from event_attendees a
  where a.event_id = new.event_id
    and a.instance_start = new.instance_start
    and a.status = 'going';
  return null;
end;
$$;

revoke execute on function public.race_sessions_notify_start_moved() from public, anon, authenticated;

drop trigger if exists race_sessions_notify_start_moved_trg on public.race_sessions;
create trigger race_sessions_notify_start_moved_trg
  after update of scheduled_start_at on public.race_sessions
  for each row
  when (new.start_mode = 'scheduled' and new.status = 'armed'
        and old.instance_start = new.instance_start
        and old.scheduled_start_at is distinct from new.scheduled_start_at)
  execute function public.race_sessions_notify_start_moved();

-- ─── creating sessions lazily ──────────────────────────────────────────────

-- Create the session for one occurrence of a scheduled or self-timed race
-- when its opening instant is within p_ahead and its window has not closed.
-- Refuses (raises) a key that is not a real occurrence; returns false for a
-- Host GO event, a cancelled occurrence, a non-athletic event or one not yet
-- due. Returns true when the session exists afterwards.
create or replace function private.ensure_race_session_due(
  p_event_id uuid,
  p_instance_start timestamptz,
  p_ahead interval
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings record;
begin
  if exists (select 1 from public.race_sessions s
              where s.event_id = p_event_id and s.instance_start = p_instance_start) then
    return true;
  end if;

  select * into v_settings from private.race_session_settings(p_event_id, p_instance_start);
  if not found or v_settings.start_mode = 'host_go' then
    return false;
  end if;

  if not private.is_event_occurrence(p_event_id, p_instance_start) then
    raise exception 'race_not_an_occurrence: % is not an occurrence of event %', p_instance_start, p_event_id
      using errcode = 'check_violation';
  end if;

  if exists (select 1 from public.event_exceptions x
              where x.event_id = p_event_id and x.instance_start = p_instance_start)
     or not public.event_is_athletic(p_event_id)
     or coalesce(v_settings.scheduled_start_at, v_settings.window_opens_at) > now() + p_ahead
     or v_settings.window_closes_at <= now() then
    return false;
  end if;

  insert into public.race_sessions (event_id, instance_start, status)
  values (p_event_id, p_instance_start, 'armed')
  on conflict (event_id, instance_start) do nothing;
  return true;
end;
$$;

revoke execute on function private.ensure_race_session_due(uuid, timestamptz, interval) from public, anon, authenticated;

-- The event page's first read of an occurrence. A caller who cannot see the
-- event gets false, the same answer as "no race".
create or replace function public.ensure_race_session(p_event_id uuid, p_instance_start timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.is_event_visible_to(p_event_id, auth.uid()) then
    return false;
  end if;
  return private.ensure_race_session_due(p_event_id, p_instance_start, interval '24 hours');
end;
$$;

revoke execute on function public.ensure_race_session(uuid, timestamptz) from public, anon;
grant execute on function public.ensure_race_session(uuid, timestamptz) to authenticated;

-- The server's clock, for a countdown sampled when a race panel opens (m3).
create or replace function public.server_now()
returns timestamptz
language sql
stable
set search_path = ''
as $$
  select now();
$$;

revoke execute on function public.server_now() from public;
grant execute on function public.server_now() to anon, authenticated;

-- The participant read: every race the caller is going to that is armed or
-- live by the clock, in any mode, with the server's clock beside it. It first
-- creates the sessions of the caller's scheduled and self-timed occurrences
-- that are due within a day, so discovery goes by the window (B4) rather than
-- by how far the occurrence's start is from now.
create or replace function public.my_race_sessions()
returns table (
  event_id uuid,
  instance_start timestamptz,
  status text,
  effective_status text,
  start_mode text,
  started_at timestamptz,
  scheduled_start_at timestamptz,
  window_opens_at timestamptz,
  window_closes_at timestamptz,
  course_id uuid,
  event_title text,
  event_timezone text,
  server_now timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  r record;
begin
  if v_uid is null then
    return;
  end if;

  for r in
    select a.event_id, a.instance_start
      from public.event_attendees a
      join public.events e on e.id = a.event_id
     where a.user_id = v_uid
       and a.status = 'going'
       and e.race_start_mode <> 'host_go'
       and a.instance_start >= now() - interval '15 days'
       and a.instance_start <= now() + interval '2 days'
  loop
    begin
      perform private.ensure_race_session_due(r.event_id, r.instance_start, interval '24 hours');
    exception when check_violation then
      null;
    end;
  end loop;

  return query
    select s.event_id, s.instance_start, s.status,
           private.race_session_effective_status(
             s.status, s.start_mode, s.scheduled_start_at, s.window_opens_at, s.window_closes_at),
           s.start_mode, s.started_at, s.scheduled_start_at, s.window_opens_at, s.window_closes_at,
           a.course_id, e.title, e.timezone, now()
      from public.event_attendees a
      join public.race_sessions s
        on s.event_id = a.event_id and s.instance_start = a.instance_start
      join public.events e on e.id = a.event_id
     where a.user_id = v_uid
       and a.status = 'going'
       and a.instance_start >= now() - interval '15 days'
       and private.race_session_effective_status(
             s.status, s.start_mode, s.scheduled_start_at, s.window_opens_at, s.window_closes_at)
           in ('armed', 'running')
     order by s.instance_start;
end;
$$;

revoke execute on function public.my_race_sessions() from public, anon;
grant execute on function public.my_race_sessions() to authenticated;

-- An organiser who changes an event's race settings re-derives every session
-- of it that has not started, so a session the job created before the edit
-- does not fire at the old time. A started session keeps what it raced under.
create or replace function private.rederive_race_sessions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s record;
  v_settings record;
begin
  for s in
    select rs.event_id, rs.instance_start
      from public.race_sessions rs
     where rs.event_id = new.id
       and rs.status = 'armed'
       and private.race_session_effective_status(
             rs.status, rs.start_mode, rs.scheduled_start_at, rs.window_opens_at, rs.window_closes_at)
           = 'armed'
  loop
    select * into v_settings from private.race_session_settings(s.event_id, s.instance_start);
    if v_settings.start_mode <> 'host_go'
       and coalesce(v_settings.scheduled_start_at, v_settings.window_opens_at) <= now() then
      -- The new settings would put the start in the past: the race would fire
      -- at once. Leave the session alone; the organiser can delay or cancel it.
      continue;
    end if;
    update public.race_sessions rs
       set start_mode = v_settings.start_mode,
           scheduled_start_at = v_settings.scheduled_start_at,
           window_opens_at = v_settings.window_opens_at,
           window_closes_at = v_settings.window_closes_at,
           is_auto_approve = coalesce(v_settings.auto_approve, rs.is_auto_approve)
     where rs.event_id = s.event_id and rs.instance_start = s.instance_start;
  end loop;
  return null;
end;
$$;

revoke execute on function private.rederive_race_sessions() from public, anon, authenticated;

drop trigger if exists events_rederive_race_sessions on public.events;
create trigger events_rederive_race_sessions
  after update of race_start_mode, race_scheduled_offset_s, race_window_open_offset_s,
                  race_window_length_s, race_auto_approve
  on public.events
  for each row
  when (old.race_start_mode is distinct from new.race_start_mode
        or old.race_scheduled_offset_s is distinct from new.race_scheduled_offset_s
        or old.race_window_open_offset_s is distinct from new.race_window_open_offset_s
        or old.race_window_length_s is distinct from new.race_window_length_s
        or old.race_auto_approve is distinct from new.race_auto_approve)
  execute function private.rederive_race_sessions();

-- ─── the per-minute job ────────────────────────────────────────────────────

-- In order: create the sessions due within 30 minutes; warn everyone going
-- about 10 minutes before a scheduled GO; fire scheduled GOs whose instant has
-- passed (started_at = the instant); open self-timed windows (started_at = the
-- opening; the lines freeze); close windows that have closed (finished_at =
-- the close, which files host DNFs exactly as End does). Each step reads the
-- clock, so a missed minute is caught up on the next run.
create or replace function public.race_sessions_tick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  e record;
  v_inst timestamptz;
  v_open_offset interval;
begin
  for e in
    select ev.id, ev.race_start_mode,
           case ev.race_start_mode
             when 'scheduled' then ev.race_scheduled_offset_s
             else ev.race_window_open_offset_s
           end as open_offset_s,
           ev.race_window_length_s
      from public.events ev
     where ev.race_start_mode <> 'host_go'
  loop
    v_open_offset := make_interval(secs => e.open_offset_s);
    for v_inst in
      select o
        from private.event_occurrences(
               e.id,
               now() - v_open_offset - make_interval(secs => e.race_window_length_s),
               now() - v_open_offset + interval '30 minutes') o
    loop
      begin
        perform private.ensure_race_session_due(e.id, v_inst, interval '30 minutes');
      exception when others then
        raise warning 'race_sessions_tick: % % %', e.id, v_inst, sqlerrm;
      end;
    end loop;
  end loop;

  insert into public.notifications (user_id, kind, event_id, event_instance_start)
  select a.user_id, 'race_starting_soon', s.event_id, s.instance_start
    from public.race_sessions s
    join public.event_attendees a
      on a.event_id = s.event_id and a.instance_start = s.instance_start
    left join public.user_settings us on us.user_id = a.user_id
   where s.start_mode = 'scheduled'
     and s.status = 'armed'
     and s.scheduled_start_at > now()
     and s.scheduled_start_at <= now() + interval '10 minutes'
     and a.status = 'going'
     and (us.prefs ->> 'notify_race_starting_soon') is distinct from 'off'
     and not exists (
       select 1 from public.notifications n
        where n.kind = 'event_reminder'
          and n.user_id = a.user_id
          and n.event_id = s.event_id
          and n.event_instance_start = s.instance_start
          and n.created_at > now() - interval '1 hour')
  on conflict do nothing;

  update public.race_sessions s
     set status = 'running',
         started_at = coalesce(s.scheduled_start_at, s.window_opens_at),
         updated_at = now()
   where s.status = 'armed'
     and s.start_mode in ('scheduled', 'self_timed')
     and coalesce(s.scheduled_start_at, s.window_opens_at) <= now();

  update public.race_sessions s
     set status = 'finished',
         finished_at = s.window_closes_at,
         updated_at = now()
   where s.status = 'running'
     and s.start_mode in ('scheduled', 'self_timed')
     and s.window_closes_at <= now();
end;
$$;

revoke execute on function public.race_sessions_tick() from public, anon, authenticated;
grant execute on function public.race_sessions_tick() to service_role;

select cron.schedule('race-sessions-tick', '* * * * *', 'select public.race_sessions_tick()');

-- ─── pings: live by the clock ──────────────────────────────────────────────

-- A runner's ping is accepted while the race is live by the clock (no cron
-- lag), not only once the stored status says running.
create or replace function private.race_session_is_live(p_event_id uuid, p_instance_start timestamptz)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.race_sessions s
     where s.event_id = p_event_id
       and s.instance_start = p_instance_start
       and private.race_session_effective_status(
             s.status, s.start_mode, s.scheduled_start_at, s.window_opens_at, s.window_closes_at)
           = 'running'
  );
$$;

revoke execute on function private.race_session_is_live(uuid, timestamptz) from public;
grant execute on function private.race_session_is_live(uuid, timestamptz) to anon, authenticated, service_role;

-- The race_pings insert policy that calls it is 20271121100006.

-- Self-timed pings are kept until the window closes plus 24 h, so the close
-- DNF fill and the plausibility check have the data (replaces the flat 48 h
-- of 20261213_001 for those sessions only).
create or replace function public.cleanup_stale_race_pings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from race_pings p
   where p.at < now() - interval '48 hours'
     and not exists (
       select 1 from race_sessions s
        where s.event_id = p.event_id
          and s.instance_start = p.instance_start
          and s.start_mode = 'self_timed'
          and s.window_closes_at + interval '24 hours' > now());
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ─── results ───────────────────────────────────────────────────────────────

-- Whether a self-timed result's crossings agree with the runner's own pings
-- (M7): a ping within 60 s and 150 m of the start line around start_at, one
-- near the finish line (or finish point) around finish_at, the first before
-- the second, and their gap within two minutes of the chip time. Reads the
-- race's frozen lines. No pings at all is not plausible: an offline runner's
-- result is reviewed, not refused.
create or replace function private.race_result_plausible(
  p_event_id uuid,
  p_instance_start timestamptz,
  p_user_id uuid,
  p_course_id uuid,
  p_start_at timestamptz,
  p_finish_at timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  c record;
  v_start_ping timestamptz;
  v_finish_ping timestamptz;
  v_chip double precision;
begin
  if p_start_at is null or p_finish_at is null or p_user_id is null then
    return false;
  end if;
  v_chip := extract(epoch from p_finish_at - p_start_at);

  select rc.start_gate_lat, rc.start_gate_lng,
         coalesce(rc.finish_gate_lat, rc.finish_lat) as finish_lat,
         coalesce(rc.finish_gate_lng, rc.finish_lng) as finish_lng
    into c
    from public.race_session_courses rc
   where rc.event_id = p_event_id
     and rc.instance_start = p_instance_start
     and (rc.course_id = p_course_id
          or (p_course_id is null
              and (select count(*) from public.race_session_courses q
                    where q.event_id = p_event_id and q.instance_start = p_instance_start) = 1))
   limit 1;
  if not found or c.start_gate_lat is null or c.finish_lat is null then
    return false;
  end if;

  select min(p.at) into v_start_ping
    from public.race_pings p
   where p.event_id = p_event_id and p.instance_start = p_instance_start
     and p.user_id = p_user_id
     and p.at between p_start_at - interval '60 seconds' and p_start_at + interval '60 seconds'
     and 6371008.8 * 2 * asin(sqrt(
           power(sin(radians(p.lat - c.start_gate_lat) / 2), 2)
           + cos(radians(c.start_gate_lat)) * cos(radians(p.lat))
             * power(sin(radians(p.lng - c.start_gate_lng) / 2), 2))) <= 150;

  select max(p.at) into v_finish_ping
    from public.race_pings p
   where p.event_id = p_event_id and p.instance_start = p_instance_start
     and p.user_id = p_user_id
     and p.at between p_finish_at - interval '60 seconds' and p_finish_at + interval '60 seconds'
     and 6371008.8 * 2 * asin(sqrt(
           power(sin(radians(p.lat - c.finish_lat) / 2), 2)
           + cos(radians(c.finish_lat)) * cos(radians(p.lat))
             * power(sin(radians(p.lng - c.finish_lng) / 2), 2))) <= 150;

  return v_start_ping is not null
     and v_finish_ping is not null
     and v_start_ping < v_finish_ping
     and abs(extract(epoch from v_finish_ping - v_start_ping) - v_chip) <= 120;
end;
$$;

revoke execute on function private.race_result_plausible(uuid, timestamptz, uuid, uuid, timestamptz, timestamptz)
  from public, anon, authenticated;

-- The race guard (§ 1850) gains the crossing columns and the Self-timed rules:
--   * any status but finished keeps no crossing instants or detections (M8),
--     and a host edit clears them and the review flag;
--   * Self-timed (M4): no gun time; with both crossings the chip time is the
--     span between them and is the ranked time; a result without a gate start,
--     with a start outside the window (M6) or failing the plausibility check
--     (M7) is kept and flagged needs_review, never refused;
--   * the lock rule (M5, decision 4b): a finished gate-to-gate row that needs
--     no review is replaced only by a faster gate-to-gate row that needs none.
--     Anything else leaves it in place without an error, so a queued slower
--     attempt is accepted rather than retried forever. Every other row (DNF,
--     host DNF, pending manual, needs_review) is always replaceable;
--   * an edit of a runner's own timing on a session that is not auto-approved,
--     or is self-timed, goes back to pending; a needs_review row is pending.
create or replace function public.event_results_race_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_club uuid;
  v_timing_changed boolean;
  v_session record;
  v_chip integer;
  v_clean boolean;
begin
  if tg_op = 'INSERT' and new.course_id is null then
    if new.user_id is not null then
      select a.course_id into new.course_id
      from event_attendees a
      where a.event_id = new.event_id
        and a.instance_start = new.instance_start
        and a.user_id = new.user_id;
    end if;
    if new.course_id is null then
      select min(c.id::text)::uuid into new.course_id
      from event_courses c
      where c.event_id = new.event_id
      having count(*) = 1;
    end if;
  end if;

  if new.course_id is not null and not exists (
    select 1 from event_courses c
    where c.id = new.course_id and c.event_id = new.event_id
  ) then
    raise exception 'event_course_mismatch: course % does not belong to event %',
      new.course_id, new.event_id
      using errcode = 'check_violation';
  end if;

  v_timing_changed := tg_op = 'INSERT'
    or new.duration_s is distinct from old.duration_s
    or new.gun_time_s is distinct from old.gun_time_s
    or new.chip_time_s is distinct from old.chip_time_s
    or new.finisher_status is distinct from old.finisher_status
    or new.start_at is distinct from old.start_at
    or new.finish_at is distinct from old.finish_at
    or new.start_detection is distinct from old.start_detection
    or new.finish_detection is distinct from old.finish_detection;

  if v_role = 'service_role' or v_uid is null or not v_timing_changed then
    return new;
  end if;

  select rs.status, rs.finished_at, rs.start_mode, rs.window_opens_at,
         rs.window_closes_at, rs.is_auto_approve
    into v_session
    from race_sessions rs
   where rs.event_id = new.event_id and rs.instance_start = new.instance_start;

  if new.user_id is distinct from v_uid then
    if tg_op = 'UPDATE' then
      new.finish_method := 'host';
      new.start_at := null;
      new.finish_at := null;
      new.start_detection := null;
      new.finish_detection := null;
      new.needs_review := false;
    end if;
  else
    if new.finisher_status is distinct from 'finished' then
      new.gun_time_s := null;
      new.chip_time_s := null;
      new.finish_method := null;
      new.start_at := null;
      new.finish_at := null;
      new.start_detection := null;
      new.finish_detection := null;
      new.needs_review := false;
    else
      if new.finish_method = 'host' then
        new.finish_method := null;
      end if;
      if new.finish_method is distinct from 'auto' then
        new.finish_detection := null;
      end if;
      if v_session.start_mode is distinct from 'self_timed' and tg_op = 'UPDATE' then
        if new.gun_time_s is distinct from new.duration_s then
          new.gun_time_s := null;
        end if;
        if new.gun_time_s is null and new.chip_time_s is distinct from new.duration_s then
          new.chip_time_s := null;
        end if;
      end if;
    end if;

    if v_session.start_mode = 'self_timed' and new.finisher_status = 'finished' then
      new.gun_time_s := null;
      if new.start_at is not null and new.finish_at is not null then
        v_chip := round(extract(epoch from new.finish_at - new.start_at))::integer;
        if v_chip > 0 then
          new.chip_time_s := v_chip;
          new.duration_s := v_chip;
        end if;
      elsif new.chip_time_s is not null and new.chip_time_s > 0 then
        new.duration_s := new.chip_time_s;
      end if;

      v_clean := new.start_detection = 'gate'
        and v_chip is not null and v_chip > 0
        and new.start_at >= v_session.window_opens_at
        and new.start_at < v_session.window_closes_at
        and private.race_result_plausible(new.event_id, new.instance_start, new.user_id,
              new.course_id, new.start_at, new.finish_at);
      v_clean := coalesce(v_clean, false);
      new.needs_review := not v_clean;
    end if;

    if v_session.start_mode = 'self_timed'
       and tg_op = 'UPDATE'
       and old.finisher_status = 'finished'
       and old.start_detection = 'gate'
       and old.finish_detection = 'gate'
       and not old.needs_review
       and not (new.finisher_status = 'finished'
                and new.start_detection = 'gate'
                and new.finish_detection = 'gate'
                and not new.needs_review
                and new.duration_s < old.duration_s)
    then
      return old;
    end if;

    if tg_op = 'UPDATE' and v_session.status is not null then
      if v_session.start_mode = 'self_timed' then
        if new.needs_review or not v_session.is_auto_approve then
          new.organiser_approved := false;
          new.organiser_approved_by := null;
          new.organiser_approved_at := null;
        else
          new.organiser_approved := true;
          new.organiser_approved_by := new.user_id;
          new.organiser_approved_at := now();
        end if;
      elsif not v_session.is_auto_approve then
        new.organiser_approved := false;
        new.organiser_approved_by := null;
        new.organiser_approved_at := null;
        new.needs_review := new.finisher_status = 'finished';
      end if;
    end if;
  end if;

  select e.club_id into v_club from events e where e.id = new.event_id;
  if private.is_race_director(v_club) or private.is_event_organiser(v_club) then
    return new;
  end if;

  if v_session.status is null
     or v_session.status is distinct from 'finished'
     or v_session.finished_at >= now() - interval '24 hours'
  then
    return new;
  end if;

  raise exception 'race_result_window_closed: race finished at %', v_session.finished_at
    using errcode = 'check_violation';
end;
$$;

-- A needs_review row is pending even on an auto-approved race.
create or replace function public.event_results_set_approval_default()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_auto boolean;
begin
  if (tg_op <> 'INSERT') then
    return new;
  end if;
  select is_auto_approve into v_auto
  from race_sessions
  where event_id = new.event_id and instance_start = new.instance_start;
  if new.needs_review or (v_auto is not null and v_auto = false) then
    new.organiser_approved := false;
    new.organiser_approved_by := null;
    new.organiser_approved_at := null;
  else
    new.organiser_approved := true;
    new.organiser_approved_by := new.user_id;
    new.organiser_approved_at := now();
  end if;
  return new;
end;
$$;

-- ─── read surfaces ─────────────────────────────────────────────────────────

create or replace view public.race_sessions_redacted as
select
  event_id,
  instance_start,
  status,
  started_at,
  finished_at,
  created_at,
  updated_at,
  case
    when private.is_club_admin(
      (select club_id from events where id = race_sessions.event_id)
    ) then started_by
    else null
  end as started_by,
  case
    when private.is_club_admin(
      (select club_id from events where id = race_sessions.event_id)
    ) then is_auto_approve
    else null
  end as is_auto_approve,
  courses_frozen_at,
  start_mode,
  scheduled_start_at,
  window_opens_at,
  window_closes_at,
  private.race_session_effective_status(
    status, start_mode, scheduled_start_at, window_opens_at, window_closes_at
  ) as effective_status
from race_sessions;

-- The organiser sees how each result was timed and whether it needs review
-- (m9); the runner sees their own. The public sees nothing new.
create or replace view public.event_results_redacted as
select
  id,
  event_id,
  instance_start,
  user_id,
  bib,
  finisher_name,
  duration_s,
  distance_m,
  rank,
  finisher_status,
  case
    when user_id = auth.uid() then age_grade_pct
    else null
  end as age_grade_pct,
  case
    when user_id = auth.uid() then note
    else null
  end as note,
  created_at,
  updated_at,
  organiser_approved,
  case
    when user_id = auth.uid() then run_id
    else null
  end as run_id,
  course_id,
  gun_time_s,
  chip_time_s,
  finish_method,
  case
    when user_id = auth.uid()
      or private.is_race_director((select club_id from events where id = event_results.event_id))
    then start_detection
  end as start_detection,
  case
    when user_id = auth.uid()
      or private.is_race_director((select club_id from events where id = event_results.event_id))
    then finish_detection
  end as finish_detection,
  case
    when user_id = auth.uid()
      or private.is_race_director((select club_id from events where id = event_results.event_id))
    then needs_review
  end as needs_review
from public.event_results;

alter view public.race_sessions_redacted set (security_invoker = on);
revoke all on public.race_sessions_redacted from public, anon, authenticated;
grant select on public.race_sessions_redacted to anon, authenticated;

alter view public.event_results_redacted set (security_invoker = on);
revoke all on public.event_results_redacted from public, anon, authenticated;
grant select on public.event_results_redacted to anon, authenticated;
