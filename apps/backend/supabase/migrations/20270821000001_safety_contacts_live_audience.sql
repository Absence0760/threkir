-- Safety alerts without making the run public (issue #1168 item 3,
-- decisions § 1964).
--
-- The overdue net (20270401_001, 20270410_001) and the off-route escalation
-- (20270414_001) only watch a live-broadcast stub, and the only stub a client
-- could create was `is_public = true`: the spectator link had to work for a
-- logged-out partner. So the safety net cost a public run, and auto-live-share
-- stayed default OFF (§ 207 decision 5). This adds a fourth audience for the
-- live window, beside public / followers / named people (§ 1874): the runner's
-- CONFIRMED safety contacts, and nobody else, with no is_public flip.
--
-- How a contact gets in. Safety contacts are email-identified and usually not
-- app users (contact_user_id is null until an app user confirms in-app, §131),
-- so an authenticated-only audience would exclude the common case: a partner
-- with no account. Admission is therefore a per-run, per-contact CAPABILITY
-- LINK, and it is minted only when an escalation fires:
--
--   * runs.safety_audience marks a stub broadcast to the safety audience.
--   * private.run_safety_links holds one unguessable token per (run, confirmed
--     contact). The overdue scan and escalate_run_off_route insert them in
--     the same statement that stamps safety_escalated_at, and put each token
--     in that contact's own email / SMS payload (`view_token`). Before an
--     escalation no token exists, so no one but the runner can see the run.
--   * public.safety_live_run / safety_live_pings are the only read path for a
--     token holder. live_run_pings RLS is NOT widened: it still admits only
--     what private.is_run_visible_to admits, and a safety-audience stub is
--     private, so an anonymous caller, a stranger and a follower all read
--     nothing from the table or its realtime feed. The token is checked in a
--     SECURITY DEFINER function, the way confirm_safety_contact_by_token
--     checks its own.
--
-- What a token admits, all of it at read time:
--   * the gate is open (below),
--   * the token's run is the run asked for, carries safety_audience, and is
--     still an in-progress stub that has not been concluded (a runner who
--     stops the share, or a run that saves, ends access on the next poll),
--   * the token's contact is still a confirmed contact of that run's owner
--     (removing or declining the contact cascades the token away),
--   * the token is under 48 hours old, the live_run_pings retention window.
--
-- The gate. A row in private.feature_flags (20270802000001), separate from
-- `audience_sharing` because it is a separate sign-off: who can see a named
-- person's live location changes, so CISO + counsel review the deploy
-- (decisions § 150). NO ROW IS INSERTED HERE; seed.sql opens it for local and
-- CI only. While it is closed:
--   * private.normalize_safety_audience stores safety_audience false, so a
--     stub written before sign-off cannot widen on the day the flag flips,
--   * the escalation mints no token, so the email carries the bare link,
--   * private.safety_link_admits answers false for every token.
-- Clients ask public.safety_audience_enabled() before offering the audience,
-- so they never write a safety stub the server would store as plain private.
--
-- The escalation functions are re-emitted from their LIVE bodies
-- (enqueue_safety_overdue_emails 20270410_001, escalate_run_off_route
-- 20270414_001, cleanup_stale_live_run_pings 20270119_001) plus the token leg.
--
-- Locks: ADD COLUMN ... NOT NULL DEFAULT false is catalogue-only on PG 11+;
-- CREATE TRIGGER takes SHARE ROW EXCLUSIVE on runs briefly; the new table is
-- empty; function replacement is catalogue-only. No constraint is added to an
-- existing table, so there is no VALIDATE to split out.

-- ─────────────────── 1. the gate ───────────────────

create or replace function private.safety_audience_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'safety_audience'),
    false
  );
$$;

revoke execute on function private.safety_audience_enabled() from public, anon;
grant execute on function private.safety_audience_enabled() to authenticated, service_role;

create or replace function public.safety_audience_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.safety_audience_enabled();
$$;

revoke execute on function public.safety_audience_enabled() from public, anon;
grant execute on function public.safety_audience_enabled() to authenticated, service_role;

comment on function public.safety_audience_enabled() is
  'Whether a live share may run on the safety-contacts-only audience '
  '(decisions § 1964). Clients fall back to the public live share when false.';

-- ─────────────────── 2. runs.safety_audience ───────────────────

alter table public.runs add column safety_audience boolean not null default false;

comment on column public.runs.safety_audience is
  'The live window is shared with the owner''s confirmed safety contacts only, '
  'through per-contact links minted at escalation (decisions § 1964). Never '
  'makes the run public. Stored false while the safety_audience gate is closed.';

create or replace function private.normalize_safety_audience()
returns trigger
language plpgsql
set search_path = public, private
as $$
begin
  if new.safety_audience and not private.safety_audience_enabled() then
    new.safety_audience := false;
  end if;
  return new;
end;
$$;

revoke execute on function private.normalize_safety_audience() from public, anon, authenticated;

create trigger runs_normalize_safety_audience
  before insert or update of safety_audience on public.runs
  for each row execute function private.normalize_safety_audience();

-- ─────────────────── 3. the per-contact links ───────────────────

-- In `private`, so PostgREST never exposes it and no client role holds a
-- grant: a token is read back only by the definer functions below. Not in the
-- Art 20 export for the same reason a session token is not: it is a
-- short-lived credential addressed to someone else, and the 48 h sweep in
-- cleanup_stale_live_run_pings deletes it. All FKs cascade, so deleting the
-- run, removing the contact or deleting either account revokes the link.
create table private.run_safety_links (
  token      uuid primary key default gen_random_uuid(),
  run_id     uuid not null references public.runs(id) on delete cascade,
  contact_id uuid not null references public.safety_contacts(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint run_safety_links_run_contact_key unique (run_id, contact_id)
);

create index run_safety_links_contact_id_idx on private.run_safety_links (contact_id);
create index run_safety_links_created_at_idx on private.run_safety_links (created_at);

comment on table private.run_safety_links is
  'One capability link per (escalated safety-audience run, confirmed contact). '
  'Minted by the escalation, read only by safety_live_run / safety_live_pings, '
  'swept after 48 h (decisions § 1964).';

alter table private.run_safety_links enable row level security;
revoke all on table private.run_safety_links from public, anon, authenticated, service_role;

create or replace function private.safety_link_admits(p_run_id uuid, p_token uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select p_run_id is not null
     and p_token is not null
     and private.safety_audience_enabled()
     and exists (
       select 1
         from private.run_safety_links l
         join runs r on r.id = l.run_id
         join safety_contacts sc on sc.id = l.contact_id
        where l.token = p_token
          and l.run_id = p_run_id
          and l.created_at > now() - interval '48 hours'
          and r.safety_audience
          and coalesce(r.metadata->>'in_progress', '') = 'true'
          and r.concluded_at is null
          and sc.owner_id = r.user_id
          and sc.confirmed_at is not null
     );
$$;

revoke execute on function private.safety_link_admits(uuid, uuid) from public, anon, authenticated;
grant execute on function private.safety_link_admits(uuid, uuid) to service_role;

-- ─────────────────── 4. the token holder's read path ───────────────────

-- The run facts the spectator page renders, for a token holder. No user_id:
-- the page needs a name, and the contact already knows who they are watching
-- (the email named them), so the owner's display name is returned instead of
-- an id that would let the caller probe anything else. route_id only when the
-- route is public, as public_runs does. Zero rows means "not admitted": the
-- caller cannot tell a wrong token from an ended run, by design.
create or replace function public.safety_live_run(p_run_id uuid, p_token uuid)
returns table (
  started_at timestamptz,
  duration_s integer,
  distance_m double precision,
  route_id uuid,
  owner_name text
)
language sql
stable
security definer
set search_path = public, private
as $$
  select r.started_at,
         r.duration_s,
         r.distance_m::double precision,
         case when is_public_route_by_id(r.route_id) then r.route_id else null end,
         coalesce(p.display_name, '')
    from runs r
    left join user_profiles p on p.id = r.user_id
   where r.id = p_run_id
     and private.safety_link_admits(p_run_id, p_token);
$$;

revoke execute on function public.safety_live_run(uuid, uuid) from public;
grant execute on function public.safety_live_run(uuid, uuid) to anon, authenticated, service_role;

comment on function public.safety_live_run(uuid, uuid) is
  'The live run a safety contact''s escalation link admits (decisions § 1964). '
  'Empty when the token does not admit the run.';

-- The pings a token holder may read. Pings are clipped to the owner's privacy
-- zones when they are WRITTEN (live_run_pings_drop_in_zone, 20260618_001 +
-- 20270121_001), so the stored rows are already what any non-owner may see.
-- With no `p_since` it returns the newest 1000, newest first, exactly as the
-- page's backlog hydrate reads the table; with one it returns what arrived
-- after it, oldest first, which is the poll a contact runs instead of a
-- realtime channel (a realtime subscription carries no token).
create or replace function public.safety_live_pings(
  p_run_id uuid,
  p_token uuid,
  p_since timestamptz default null
)
returns table (
  lat double precision,
  lng double precision,
  distance_m double precision,
  elapsed_s integer,
  at timestamptz,
  coarse boolean
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.safety_link_admits(p_run_id, p_token) then
    return;
  end if;
  if p_since is null then
    return query
      select p.lat, p.lng, p.distance_m::double precision, p.elapsed_s, p.at, p.coarse
        from live_run_pings p
       where p.run_id = p_run_id
       order by p.at desc
       limit 1000;
  else
    return query
      select p.lat, p.lng, p.distance_m::double precision, p.elapsed_s, p.at, p.coarse
        from live_run_pings p
       where p.run_id = p_run_id
         and p.at > p_since
       order by p.at asc
       limit 1000;
  end if;
end;
$$;

revoke execute on function public.safety_live_pings(uuid, uuid, timestamptz) from public;
grant execute on function public.safety_live_pings(uuid, uuid, timestamptz)
  to anon, authenticated, service_role;

comment on function public.safety_live_pings(uuid, uuid, timestamptz) is
  'Privacy-clipped live pings for a safety contact''s escalation link '
  '(decisions § 1964). Empty when the token does not admit the run.';

-- ─────────────────── 5. the overdue scan mints the links ───────────────────

-- Live body 20270410_001. New: `stamped` returns safety_audience, a `links`
-- CTE mints one token per confirmed contact when the run is a safety-audience
-- stub and the gate is open, and each email / SMS carries its own contact's
-- token. A contact never sees another contact's token.
create or replace function public.enqueue_safety_overdue_emails()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with overdue as (
    select
      r.id,
      r.user_id,
      r.started_at,
      greatest(r.started_at, coalesce(max(p.at), r.started_at)) as last_seen_at,
      max(p.at) is not null as has_ping
    from runs r
    left join user_settings us on us.user_id = r.user_id
    left join live_run_pings p on p.run_id = r.id
    where coalesce(r.metadata->>'in_progress', '') = 'true'
      and r.metadata->>'safety_escalated_at' is null
      and r.started_at > now() - interval '24 hours'
      and exists (
        select 1 from safety_contacts sc
        where sc.owner_id = r.user_id and sc.confirmed_at is not null
      )
    group by r.id, (us.prefs->>'safety_overdue_minutes')
    having
      (
        r.metadata->>'expected_return_at' is not null
        and (r.metadata->>'expected_return_at')::timestamptz < now()
      )
      or
      (
        us.prefs->>'safety_overdue_minutes' ~ '^[0-9]+$'
        and (us.prefs->>'safety_overdue_minutes')::int >= 10
        and greatest(r.started_at, coalesce(max(p.at), r.started_at))
            < now() - make_interval(mins => (us.prefs->>'safety_overdue_minutes')::int)
      )
  ),
  stamped as (
    update runs r
    set metadata = coalesce(r.metadata, '{}'::jsonb)
                   || jsonb_build_object('safety_escalated_at', now())
    from overdue o
    where r.id = o.id
    returning r.id, o.user_id, o.started_at, o.last_seen_at, o.has_ping, r.safety_audience
  ),
  links as (
    insert into private.run_safety_links (run_id, contact_id)
    select s.id, sc.id
    from stamped s
    join safety_contacts sc
      on sc.owner_id = s.user_id and sc.confirmed_at is not null
    where s.safety_audience
      and private.safety_audience_enabled()
    on conflict (run_id, contact_id) do nothing
    returning run_id, contact_id, token
  ),
  email_jobs as (
    insert into public.jobs (kind, payload)
    select
      'safety_email',
      jsonb_strip_nulls(jsonb_build_object(
        'template', 'overdue',
        'contact_user_id', sc.contact_user_id,
        'contact_email', sc.contact_email,
        'owner_name', coalesce(pr.display_name, ''),
        'run_id', s.id::text,
        'started_at', s.started_at,
        'last_seen_at', case when s.has_ping then s.last_seen_at end,
        'view_token', l.token::text
      ))
    from stamped s
    join safety_contacts sc
      on sc.owner_id = s.user_id and sc.confirmed_at is not null
    left join links l on l.run_id = s.id and l.contact_id = sc.id
    left join user_profiles pr on pr.id = s.user_id
    returning 1
  )
  insert into public.jobs (kind, payload)
  select
    'safety_sms',
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'overdue',
      'contact_user_id', sc.contact_user_id,
      'contact_phone', sc.contact_phone,
      'owner_name', coalesce(pr.display_name, ''),
      'run_id', s.id::text,
      'started_at', s.started_at,
      'last_seen_at', case when s.has_ping then s.last_seen_at end,
      'view_token', l.token::text
    ))
  from stamped s
  join safety_contacts sc
    on sc.owner_id = s.user_id
   and sc.confirmed_at is not null
   and sc.contact_phone is not null
   and sc.sms_opt_in_at is not null
  left join links l on l.run_id = s.id and l.contact_id = sc.id
  left join user_profiles pr on pr.id = s.user_id;
end;
$$;

revoke execute on function public.enqueue_safety_overdue_emails() from public, anon, authenticated;

-- ─────────────────── 6. the off-route escalation mints them too ───────────────────

-- Live body 20270414_001. New: the stamp returns safety_audience, the links
-- are minted under the same conditions as the scan's, and each job carries
-- its own contact's token.
create or replace function public.escalate_run_off_route(p_run_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_started timestamptz;
  v_safety_audience boolean;
  v_last_seen timestamptz;
  v_has_ping boolean;
  v_owner_name text;
begin
  update runs r
    set metadata = coalesce(r.metadata, '{}'::jsonb)
                   || jsonb_build_object('safety_escalated_at', now())
  where r.id = p_run_id
    and r.user_id = auth.uid()
    and coalesce(r.metadata->>'in_progress', '') = 'true'
    and r.metadata->>'safety_escalated_at' is null
    and r.started_at > now() - interval '24 hours'
    and exists (
      select 1 from user_settings us
      where us.user_id = r.user_id
        and us.prefs->>'safety_off_route_alerts' = 'true'
    )
    and exists (
      select 1 from safety_contacts sc
      where sc.owner_id = r.user_id and sc.confirmed_at is not null
    )
  returning r.user_id, r.started_at, r.safety_audience
    into v_owner, v_started, v_safety_audience;

  if v_owner is null then
    return false;
  end if;

  select greatest(v_started, coalesce(max(p.at), v_started)),
         max(p.at) is not null
    into v_last_seen, v_has_ping
    from live_run_pings p
    where p.run_id = p_run_id;

  select coalesce(display_name, '') into v_owner_name
    from user_profiles where id = v_owner;

  if v_safety_audience and private.safety_audience_enabled() then
    insert into private.run_safety_links (run_id, contact_id)
    select p_run_id, sc.id
      from safety_contacts sc
     where sc.owner_id = v_owner and sc.confirmed_at is not null
    on conflict (run_id, contact_id) do nothing;
  end if;

  insert into public.jobs (kind, payload)
  select
    'safety_email',
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'off_route',
      'contact_user_id', sc.contact_user_id,
      'contact_email', sc.contact_email,
      'owner_name', v_owner_name,
      'run_id', p_run_id::text,
      'started_at', v_started,
      'last_seen_at', case when v_has_ping then v_last_seen end,
      'view_token', l.token::text
    ))
  from safety_contacts sc
  left join private.run_safety_links l on l.run_id = p_run_id and l.contact_id = sc.id
  where sc.owner_id = v_owner and sc.confirmed_at is not null;

  insert into public.jobs (kind, payload)
  select
    'safety_sms',
    jsonb_strip_nulls(jsonb_build_object(
      'template', 'off_route',
      'contact_user_id', sc.contact_user_id,
      'contact_phone', sc.contact_phone,
      'owner_name', v_owner_name,
      'run_id', p_run_id::text,
      'started_at', v_started,
      'last_seen_at', case when v_has_ping then v_last_seen end,
      'view_token', l.token::text
    ))
  from safety_contacts sc
  left join private.run_safety_links l on l.run_id = p_run_id and l.contact_id = sc.id
  where sc.owner_id = v_owner
    and sc.confirmed_at is not null
    and sc.contact_phone is not null
    and sc.sms_opt_in_at is not null;

  return true;
end;
$$;

revoke execute on function public.escalate_run_off_route(uuid) from public, anon;
grant execute on function public.escalate_run_off_route(uuid) to authenticated;

-- ─────────────────── 7. the links die with the pings ───────────────────

-- Live body 20270119_001 plus the link sweep. A link is useless once the
-- pings it reads are gone, and admission already refuses it past 48 h, so the
-- same cron (cleanup-stale-live-run-pings, every 15 min) deletes both on one
-- window. The return value stays the ping count the schedule has always read.
create or replace function cleanup_stale_live_run_pings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from live_run_pings
   where at < now() - interval '48 hours';
  get diagnostics v_count = row_count;
  delete from private.run_safety_links
   where created_at < now() - interval '48 hours';
  return v_count;
end;
$$;

revoke all on function cleanup_stale_live_run_pings() from public, anon, authenticated;
grant execute on function cleanup_stale_live_run_pings() to service_role;
