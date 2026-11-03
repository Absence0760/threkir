-- Share-link attribution and a creator view (issue #1273 item 10, decisions
-- § 2268).
--
-- A creator wants to know which of their links bring people in, without a
-- third-party analytics vendor. Everything here is an aggregate the creator
-- reads about their own links; nothing records who visited.
--
-- 1. The gate. Counting visits to a page and attributing a sign-up to a link
--    are new processing, so the whole path is fail-closed behind a
--    'share_attribution' row in private.feature_flags that NO MIGRATION
--    WRITES. It waits on the CISO / Security Analyst review (aggregate counter
--    vs cookie consent; DPIA for sign-up attribution) in
--    docs/ops/deployment.md (§ 150); seed.sql opens it for local + CI.
--
-- 2. private.share_ref_codes: one opaque ten-character code per creator, the
--    `ref` their own share links carry. Not the @handle: a handle is optional,
--    changes, and would put the creator's username into every link a follower
--    forwards. The code says nothing on its own and outlives a handle change.
--
-- 3. private.share_link_daily: one row per (kind, entity, UTC day) with four
--    counters. A row is written only for an entity that exists and is shared
--    publicly, so a flood of invented ids writes nothing, and the row count is
--    bounded by real shared entities times days. Each counter is capped per
--    day. No visitor identifier of any kind is stored: no cookie, IP address,
--    user agent or user id. Rows older than 90 days are purged daily; the
--    creator view reads the same window.
--
-- 4. public.record_share_visit(kind, id, ref, bot): called once per page view
--    by the /share/<kind>/<id> page in the visitor's browser. Not by the
--    share-entity Lambda: CloudFront caches that HTML for five minutes and
--    strips the query string, so the Lambda sees one request per edge per
--    five minutes and never sees `ref`. Unfurl bots do not run the page's
--    script, so they never reach this call; a script-running crawler that
--    names itself is counted in bot_visits, apart from visits. The owner's own
--    views are not counted.
--
-- 5. Sign-ups. A sign-up made from a share page carries `signup_share`
--    ({kind, id, ref}) in its GoTrue metadata, set by the client only on the
--    sign-up the person submits. When the account is confirmed (or, for
--    OAuth, when the metadata is written after the first callback) a trigger
--    adds one to that link's `signups`, but only when `ref` is the code of the
--    entity's owner, once per account (private.signup_share_counted), and
--    only within a day of the account's creation.
--
-- 6. Plan starts and challenge joins. private.plan_share_starts and
--    private.challenge_share_joins mark a copy or a join that came through the
--    owner's link. Private tables, not columns: challenge_participants carries
--    table-level SELECT for anon (20270408_001), so a column there would
--    publish how each participant of a public challenge arrived, and a column
--    on training_plans would need a freeze trigger and reach every client row
--    type for a fact only the counter reads. Each goes with its plan copy or
--    participant row by FK cascade. Both are written only by
--    attribute_share_start (definer) within ten minutes of the clone or join,
--    and only when `ref` is the owner's code, so nobody can inflate a
--    creator's numbers by editing a row.
--
-- 7. public.my_share_stats(): the creator view. Per link, over the last 90
--    days: visits (and how many came through the creator's own link), bot
--    visits, sign-ups, plan starts and challenge joins (and how many of those
--    came through the link). Only the caller's own entities.
--
-- Locks: new private tables, functions and triggers (catalogue only). The FKs
-- from plan_share_starts to training_plans and from challenge_share_joins to
-- challenge_participants are validated against empty children, so the SHARE
-- ROW EXCLUSIVE lock on each parent is momentary; no populated table gains a
-- column or is scanned. The auth.users triggers take a brief catalogue lock
-- and scan nothing.

-- ── 1. The gate ─────────────────────────────────────────────────────────────

create or replace function private.share_attribution_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'share_attribution'),
    false
  );
$$;

revoke execute on function private.share_attribution_enabled() from public, anon, authenticated;
grant execute on function private.share_attribution_enabled() to service_role;

create or replace function public.share_attribution_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.share_attribution_enabled();
$$;

revoke execute on function public.share_attribution_enabled() from public;
grant execute on function public.share_attribution_enabled() to anon, authenticated, service_role;

comment on function public.share_attribution_enabled() is
  'Whether share-link attribution is live (decisions § 2268). Clients add no '
  'ref, record no visit and hide Your shares when false.';

-- ── 2. Ref codes ────────────────────────────────────────────────────────────

create table private.share_ref_codes (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  code       text not null unique check (code ~ '^[a-z0-9]{10}$'),
  created_at timestamptz not null default now()
);

comment on table private.share_ref_codes is
  'The opaque ref code a creator''s own share links carry (decisions § 2268). '
  'Private schema; reached only through my_share_ref and the definer counters.';

alter table private.share_ref_codes enable row level security;
revoke all on table private.share_ref_codes from public, anon, authenticated;

-- The owner a ref names, or null for anything that is not a well-formed,
-- issued code.
create or replace function private.share_ref_owner(p_ref text)
returns uuid
language sql
stable
security definer
set search_path = public, private
as $$
  select c.user_id
    from private.share_ref_codes c
   where p_ref is not null
     and p_ref ~ '^[a-z0-9]{10}$'
     and c.code = p_ref;
$$;

revoke execute on function private.share_ref_owner(text) from public, anon, authenticated;
grant execute on function private.share_ref_owner(text) to service_role;

create or replace function public.my_share_ref()
returns text
language plpgsql
volatile
security definer
set search_path = public, private, extensions
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_try int := 0;
begin
  if v_uid is null or not private.share_attribution_enabled() then
    return null;
  end if;

  select c.code into v_code from private.share_ref_codes c where c.user_id = v_uid;
  if v_code is not null then
    return v_code;
  end if;

  -- 36^10 codes; a collision is a retry, not an error.
  loop
    v_try := v_try + 1;
    select string_agg(substr('abcdefghijklmnopqrstuvwxyz0123456789', (b % 36) + 1, 1), '')
      into v_code
      from (select get_byte(extensions.gen_random_bytes(10), i) as b
              from generate_series(0, 9) as i) bytes;
    begin
      insert into private.share_ref_codes (user_id, code) values (v_uid, v_code)
        on conflict (user_id) do nothing;
      exit;
    exception when unique_violation then
      if v_try >= 5 then
        raise;
      end if;
    end;
  end loop;

  select c.code into v_code from private.share_ref_codes c where c.user_id = v_uid;
  return v_code;
end;
$$;

revoke execute on function public.my_share_ref() from public, anon;
grant execute on function public.my_share_ref() to authenticated, service_role;

comment on function public.my_share_ref() is
  'The caller''s share ref code, minted on first call. Null while the '
  'share_attribution gate is closed (decisions § 2268).';

-- ── 3. Which entity, and whose ──────────────────────────────────────────────
-- The owner of a publicly shared entity, or null when it does not exist, is
-- not shared publicly, or the kind is not one the creator view covers. Clubs,
-- events and race listings are left out: they belong to a club or to nobody,
-- and the creator view is one person's.

create or replace function private.share_link_owner(p_kind text, p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, private
as $$
  select case p_kind
    when 'plan' then (
      select p.user_id from training_plans p
       where p.id = p_id and p.is_template = true and p.is_public_template = true)
    when 'challenge' then (
      select c.creator_id from challenges c
       where c.id = p_id and c.is_public = true)
    when 'profile' then (
      select u.id from user_profiles u
       where u.id = p_id and u.shadow_hidden = false
         and private.profile_visible_to(u.id, null))
    when 'session' then (
      select s.author_id from session_plans s
       where s.id = p_id and s.is_public = true)
    when 'workout' then (
      select w.user_id from gym_workouts w
       where w.id = p_id and w.is_public = true)
  end;
$$;

revoke execute on function private.share_link_owner(text, uuid) from public, anon, authenticated;
grant execute on function private.share_link_owner(text, uuid) to service_role;

-- ── 4. The daily buckets ────────────────────────────────────────────────────

create table private.share_link_daily (
  kind       text not null check (kind in ('plan', 'challenge', 'profile', 'session', 'workout')),
  entity_id  uuid not null,
  day        date not null,
  owner_id   uuid not null references auth.users (id) on delete cascade,
  visits     integer not null default 0 check (visits >= 0),
  ref_visits integer not null default 0 check (ref_visits >= 0),
  bot_visits integer not null default 0 check (bot_visits >= 0),
  signups    integer not null default 0 check (signups >= 0),
  primary key (kind, entity_id, day)
);

create index share_link_daily_owner_day_idx on private.share_link_daily (owner_id, day);

comment on table private.share_link_daily is
  'Aggregate per-link counters by UTC day (decisions § 2268). No visitor '
  'identifier of any kind. Purged after 90 days by purge-share-link-daily.';

alter table private.share_link_daily enable row level security;
revoke all on table private.share_link_daily from public, anon, authenticated;

-- One counter's ceiling per link per day. A flood can push a counter to it
-- and no further, and the row count does not grow with the flood at all.
create or replace function private.share_link_daily_cap()
returns integer
language sql
immutable
as $$ select 1000000 $$;

revoke execute on function private.share_link_daily_cap() from public, anon, authenticated;

create or replace function public.record_share_visit(
  p_kind text,
  p_id uuid,
  p_ref text default null,
  p_bot boolean default false
)
returns void
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_owner uuid;
  v_ref boolean;
  v_bot boolean := coalesce(p_bot, false);
  v_cap integer := private.share_link_daily_cap();
begin
  if p_id is null or not private.share_attribution_enabled() then
    return;
  end if;

  v_owner := private.share_link_owner(p_kind, p_id);
  if v_owner is null or v_owner = (select auth.uid()) then
    return;
  end if;

  v_ref := not v_bot and private.share_ref_owner(p_ref) = v_owner;

  insert into private.share_link_daily as d
    (kind, entity_id, day, owner_id, visits, ref_visits, bot_visits)
  values (
    p_kind, p_id, (now() at time zone 'utc')::date, v_owner,
    case when v_bot then 0 else 1 end,
    case when v_ref then 1 else 0 end,
    case when v_bot then 1 else 0 end
  )
  on conflict (kind, entity_id, day) do update
    set visits     = least(d.visits + excluded.visits, v_cap),
        ref_visits = least(d.ref_visits + excluded.ref_visits, v_cap),
        bot_visits = least(d.bot_visits + excluded.bot_visits, v_cap);
end;
$$;

revoke execute on function public.record_share_visit(text, uuid, text, boolean) from public;
grant execute on function public.record_share_visit(text, uuid, text, boolean) to anon, authenticated, service_role;

comment on function public.record_share_visit(text, uuid, text, boolean) is
  'Count one view of a public share page in today''s bucket (decisions § 2268). '
  'No-op while the share_attribution gate is closed, for an entity that is not '
  'shared publicly, and for the owner''s own view. Stores no visitor identifier.';

create or replace function private.purge_share_link_daily()
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_deleted bigint;
begin
  with deleted as (
    delete from private.share_link_daily
    where day < (now() at time zone 'utc')::date - 90
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_share_link_daily: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_share_link_daily() from public, anon, authenticated;

select cron.schedule(
  'purge-share-link-daily',
  '7 4 * * *',  -- 04:07 UTC daily, a minute no other job holds.
  $$select private.purge_share_link_daily()$$
);

comment on function private.purge_share_link_daily() is
  'Storage limitation for the share-link counters: drops buckets older than '
  '90 days, the window the creator view reads. Scheduled by pg_cron entry '
  '`purge-share-link-daily` (04:07 UTC daily). decisions § 2268.';

-- ── 5. Sign-ups ─────────────────────────────────────────────────────────────

create table private.signup_share_counted (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  counted_at timestamptz not null default now()
);

comment on table private.signup_share_counted is
  'Marks an account whose sign-up has been counted for a share link, so it is '
  'counted once (decisions § 2268). Holds no link and no creator.';

alter table private.signup_share_counted enable row level security;
revoke all on table private.signup_share_counted from public, anon, authenticated;

create or replace function private.count_signup_share()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_share jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb) -> 'signup_share';
  v_kind text;
  v_id uuid;
  v_owner uuid;
  v_cap integer := private.share_link_daily_cap();
begin
  if new.email_confirmed_at is null
     or jsonb_typeof(v_share) is distinct from 'object'
     or coalesce(new.created_at, now()) < now() - interval '1 day'
     or not private.share_attribution_enabled() then
    return new;
  end if;

  v_kind := v_share ->> 'kind';
  if coalesce(v_share ->> 'id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return new;
  end if;
  v_id := (v_share ->> 'id')::uuid;

  v_owner := private.share_link_owner(v_kind, v_id);
  if v_owner is null
     or v_owner = new.id
     or private.share_ref_owner(v_share ->> 'ref') is distinct from v_owner then
    return new;
  end if;

  insert into private.signup_share_counted (user_id) values (new.id)
    on conflict (user_id) do nothing;
  if not found then
    return new;
  end if;

  insert into private.share_link_daily as d (kind, entity_id, day, owner_id, signups)
  values (v_kind, v_id, (now() at time zone 'utc')::date, v_owner, 1)
  on conflict (kind, entity_id, day) do update
    set signups = least(d.signups + 1, v_cap);

  return new;
end;
$$;

revoke execute on function private.count_signup_share() from public, anon, authenticated;

comment on function private.count_signup_share() is
  'Adds one sign-up to a share link when a confirmed account''s signup_share '
  'metadata names a public entity and its owner''s ref code; once per account, '
  'within a day of creation, behind share_attribution. decisions § 2268.';

-- Email sign-up with confirmation off: confirmed at insert.
create trigger auth_users_count_signup_share_on_insert
  after insert on auth.users
  for each row
  when (new.email_confirmed_at is not null and new.raw_user_meta_data ? 'signup_share')
  execute function private.count_signup_share();

-- Email sign-up: the confirmation link.
create trigger auth_users_count_signup_share_on_confirm
  after update of email_confirmed_at on auth.users
  for each row
  when (old.email_confirmed_at is null and new.email_confirmed_at is not null
        and new.raw_user_meta_data ? 'signup_share')
  execute function private.count_signup_share();

-- OAuth sign-up: no metadata at insert, so the callback writes it with
-- updateUser on the account's first sign-in.
create trigger auth_users_count_signup_share_on_metadata
  after update of raw_user_meta_data on auth.users
  for each row
  when (new.raw_user_meta_data ? 'signup_share'
        and (old.raw_user_meta_data -> 'signup_share')
            is distinct from (new.raw_user_meta_data -> 'signup_share'))
  execute function private.count_signup_share();

-- ── 6. Plan starts and challenge joins ──────────────────────────────────────

create table private.plan_share_starts (
  plan_id    uuid primary key references public.training_plans (id) on delete cascade,
  created_at timestamptz not null default now()
);

comment on table private.plan_share_starts is
  'A copy of a public plan started from its author''s own share link '
  '(decisions § 2268). Goes with the copy. Written by attribute_share_start only.';

alter table private.plan_share_starts enable row level security;
revoke all on table private.plan_share_starts from public, anon, authenticated;

create table private.challenge_share_joins (
  challenge_id uuid not null,
  user_id      uuid not null,
  created_at   timestamptz not null default now(),
  primary key (challenge_id, user_id),
  foreign key (challenge_id, user_id)
    references public.challenge_participants (challenge_id, user_id) on delete cascade
);

comment on table private.challenge_share_joins is
  'A challenge join that came through the creator''s own share link '
  '(decisions § 2268). Goes with the participant row on leave or account '
  'deletion. Written by attribute_share_start only.';

alter table private.challenge_share_joins enable row level security;
revoke all on table private.challenge_share_joins from public, anon, authenticated;

create or replace function public.attribute_share_start(
  p_kind text,
  p_id uuid,
  p_ref text
)
returns boolean
language plpgsql
volatile
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
begin
  if v_uid is null or p_id is null or not private.share_attribution_enabled() then
    return false;
  end if;

  v_owner := private.share_ref_owner(p_ref);
  if v_owner is null or v_owner = v_uid then
    return false;
  end if;

  if p_kind = 'plan' then
    -- p_id is the caller's new copy, as clone_public_plan returned it.
    insert into private.plan_share_starts (plan_id)
    select p.id
      from training_plans p
      join training_plans t on t.id = p.parent_template_id and t.is_public_template = true
     where p.id = p_id
       and p.user_id = v_uid
       and p.source_author_id = v_owner
       and p.created_at > now() - interval '10 minutes'
    on conflict (plan_id) do nothing;
    return found;
  elsif p_kind = 'challenge' then
    insert into private.challenge_share_joins (challenge_id, user_id)
    select cp.challenge_id, cp.user_id
      from challenge_participants cp
      join challenges c on c.id = cp.challenge_id
     where cp.challenge_id = p_id
       and cp.user_id = v_uid
       and cp.joined_at > now() - interval '10 minutes'
       and c.creator_id = v_owner
    on conflict (challenge_id, user_id) do nothing;
    return found;
  end if;
  return false;
end;
$$;

revoke execute on function public.attribute_share_start(text, uuid, text) from public, anon;
grant execute on function public.attribute_share_start(text, uuid, text) to authenticated, service_role;

comment on function public.attribute_share_start(text, uuid, text) is
  'Mark the caller''s own just-made plan copy (kind plan, id = the copy) or '
  'challenge join (kind challenge, id = the challenge) as started from the '
  'owner''s share link, when ref is the owner''s code and the copy or join is '
  'under ten minutes old. Once per row. decisions § 2268.';

-- ── 7. The creator view ─────────────────────────────────────────────────────

create or replace function public.my_share_stats()
returns table (
  kind       text,
  entity_id  uuid,
  title      text,
  visits     integer,
  ref_visits integer,
  bot_visits integer,
  signups    integer,
  starts     integer,
  ref_starts integer,
  joins      integer,
  ref_joins  integer
)
language sql
stable
security definer
set search_path = public, private
as $$
  with me as (
    select (select auth.uid()) as uid,
           (now() at time zone 'utc')::date - 89 as since
  ),
  buckets as (
    select d.kind, d.entity_id,
           sum(d.visits)::int as visits,
           sum(d.ref_visits)::int as ref_visits,
           sum(d.bot_visits)::int as bot_visits,
           sum(d.signups)::int as signups
      from private.share_link_daily d, me
     where d.owner_id = me.uid and d.day >= me.since
     group by d.kind, d.entity_id
  ),
  plan_starts as (
    select t.id as entity_id,
           count(c.id)::int as starts,
           count(ss.plan_id)::int as ref_starts
      from training_plans t
      cross join me
      left join training_plans c
        on c.parent_template_id = t.id
       and c.source_author_id = me.uid
       and c.created_at >= me.since
      left join private.plan_share_starts ss on ss.plan_id = c.id
     where t.user_id = me.uid and t.is_template = true and t.is_public_template = true
     group by t.id
  ),
  challenge_joins as (
    select ch.id as entity_id,
           count(cp.user_id)::int as joins,
           count(sj.user_id)::int as ref_joins
      from challenges ch
      cross join me
      left join challenge_participants cp
        on cp.challenge_id = ch.id
       and cp.user_id <> me.uid
       and cp.joined_at >= me.since
      left join private.challenge_share_joins sj
        on sj.challenge_id = cp.challenge_id and sj.user_id = cp.user_id
     where ch.creator_id = me.uid
     group by ch.id
  ),
  links as (
    select b.kind, b.entity_id from buckets b
    union
    select 'plan', ps.entity_id from plan_starts ps
    union
    select 'challenge', cj.entity_id from challenge_joins cj
  )
  select
    l.kind,
    l.entity_id,
    case l.kind
      when 'plan' then (select p.name from training_plans p where p.id = l.entity_id)
      when 'challenge' then (select c.title from challenges c where c.id = l.entity_id)
      when 'session' then (select s.title from session_plans s where s.id = l.entity_id)
      when 'workout' then (select w.title from gym_workouts w where w.id = l.entity_id)
    end as title,
    coalesce(b.visits, 0),
    coalesce(b.ref_visits, 0),
    coalesce(b.bot_visits, 0),
    coalesce(b.signups, 0),
    coalesce(ps.starts, 0),
    coalesce(ps.ref_starts, 0),
    coalesce(cj.joins, 0),
    coalesce(cj.ref_joins, 0)
  from links l
  cross join me
  left join buckets b on b.kind = l.kind and b.entity_id = l.entity_id
  left join plan_starts ps on l.kind = 'plan' and ps.entity_id = l.entity_id
  left join challenge_joins cj on l.kind = 'challenge' and cj.entity_id = l.entity_id
  where me.uid is not null
    and private.share_attribution_enabled()
    and case l.kind
      when 'plan' then exists (select 1 from training_plans p where p.id = l.entity_id and p.user_id = me.uid)
      when 'challenge' then exists (select 1 from challenges c where c.id = l.entity_id and c.creator_id = me.uid)
      when 'profile' then l.entity_id = me.uid
      when 'session' then exists (select 1 from session_plans s where s.id = l.entity_id and s.author_id = me.uid)
      when 'workout' then exists (select 1 from gym_workouts w where w.id = l.entity_id and w.user_id = me.uid)
      else false
    end
  order by coalesce(b.visits, 0) desc, l.kind, l.entity_id;
$$;

revoke execute on function public.my_share_stats() from public, anon;
grant execute on function public.my_share_stats() to authenticated, service_role;

comment on function public.my_share_stats() is
  'The caller''s own share links over the last 90 days: visits, visits through '
  'their ref, bot visits, sign-ups, plan starts and challenge joins (and how '
  'many came through their ref). Empty while share_attribution is closed. '
  'decisions § 2268.';
