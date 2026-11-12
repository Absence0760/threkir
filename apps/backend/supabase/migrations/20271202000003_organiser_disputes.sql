-- Organiser name disputes, part 3: filing, review and audit (issue #1363,
-- decisions § 2441). Part 1 (20271202000001) widened `reports`; part 2
-- (20271202000002) added the `organiser_dispute` notification kind.
--
-- ── Filing ──────────────────────────────────────────────────────────────────
--
-- submit_organiser_dispute(kind, id, club, notes) files a pending report with
-- reason 'organiser_dispute' and the reporting club. The caller must be an
-- ACTIVE owner or admin of a public, verified, unhidden club
-- (private.is_official_publisher, the one derivation of "official",
-- 20271021000030), checked here in the definer body; the client only decides
-- whether to offer the option. The general submit_report() refuses the reason
-- (its hard-coded list), so this is the only way in. The target must be one
-- the organiser can have seen (a public club or route, a public plan or
-- routine template, a public challenge, a race listing claimed by ANOTHER
-- club), and must not be the reporting club or its own content. Filing shares
-- submit_report's rate-limit bucket (10 an hour) and its one-pending-report-
-- per-target index. Filing notifies nobody: the reviewer decides, and an
-- unreviewed claim is not the owner's to answer.
--
-- ── No automation ───────────────────────────────────────────────────────────
--
-- A dispute never hides anything by itself (the same rule as the verification
-- review, § 2398). The reports_auto_hide trigger returns early for one, and
-- auto_hide_target's vetted-reporter count leaves disputes out, so they never
-- tip a later general report over the threshold either. Both bodies are
-- re-emitted whole from 20270218_001.
--
-- ── Review (site admins only) ───────────────────────────────────────────────
--
-- resolve_organiser_dispute(kind, id, action, note, deadline_days):
--   * 'takedown': the existing hide path. A club or route gets shadow_hidden (the
--     flag auto-hide and admin_unhide_target already use). A plan or routine
--     template and a challenge have no such flag, so they are unpublished
--     (is_public_template / is_public false) and a trigger refuses a
--     republish while the takedown stands; for a library plan copy the lock
--     also holds against publishing its source plan again. A race listing's claim is released
--     (organiser club, course link and course stamps cleared) so the rightful
--     organiser can claim it. The dispute reports are marked reviewed.
--   * 'rename_notice': the owner is asked to rename or change the content by
--     a deadline (default 14 days, 1 to 60). The reports stay pending, so the
--     target stays at the top of the queue, which shows the deadline; after
--     it the reviewer hides or dismisses. Nothing happens at the deadline on
--     its own.
--   * 'dismiss': the dispute reports are dismissed.
-- Only the dispute reports are touched; general reports on the same target
-- keep their own triage, and resolve_target_reports (re-emitted) now leaves
-- dispute reports alone. reports.reviewed_by stays null on a dispute: the
-- reporter can read their own report row, and must not learn the reviewer. Every action, and every filing, is written to the
-- append-only organiser_dispute_actions log with the reviewer's id; the
-- notices to both sides carry no actor, and my_organiser_disputes() never
-- returns one. admin_unhide_target (re-emitted) lifts a takedown on the new
-- kinds by logging 'unhide'; the owner republishes when they choose.
--
-- ── Reads ───────────────────────────────────────────────────────────────────
--
--   * fetch_pending_reports gains organiser_dispute, organiser_clubs and
--     rename_deadline_at, and sorts targets carrying a pending dispute first.
--   * fetch_reports_for_target gains the reporting club (id, name, slug,
--     verified now) per report.
--   * private.report_target_page_id / report_target_shadow_hidden learn the
--     new kinds, so the resolved list links and badges them too.
--   * my_organiser_disputes(): the caller's side of every dispute that has
--     been acted on: as the owner of disputed content, or as an owner/admin
--     of the reporting club (which also sees its pending filings).
--   * organiser_dispute_history(kind, id): the admin's full log, reviewer
--     included.
--
-- Locks (docs/backend/migration_locks.md): a new table and its indexes; new
-- and replaced functions; three BEFORE UPDATE triggers on training_plans,
-- gym_routines and challenges, each CREATE TRIGGER a brief SHARE ROW
-- EXCLUSIVE on a bounded content table that no row is rewritten on.

set search_path = public, extensions;

-- ── 1. The audit log ────────────────────────────────────────────────────────

create table organiser_dispute_actions (
  id                 bigint generated always as identity primary key,
  target_kind        text not null,
  target_id          uuid not null,
  organiser_club_id  uuid references clubs (id) on delete set null,
  organiser_club_name text not null,
  target_owner_id    uuid references auth.users (id) on delete set null,
  actor_id           uuid references auth.users (id) on delete set null,
  action             text not null,
  deadline_at        timestamptz,
  note               text,
  -- For a library plan copy, the owner's plan it was published from, so a
  -- takedown also holds against publishing that plan again (no FK: the log
  -- outlives the plan).
  source_plan_id     uuid,
  created_at         timestamptz not null default now(),
  constraint organiser_dispute_actions_kind_check
    check (target_kind in ('club', 'route', 'training_plan', 'gym_routine', 'challenge', 'race_listing')),
  constraint organiser_dispute_actions_action_check
    check (action in ('filed', 'takedown', 'rename_notice', 'dismiss', 'unhide')),
  constraint organiser_dispute_actions_deadline_check
    check ((action = 'rename_notice') = (deadline_at is not null)),
  constraint organiser_dispute_actions_note_len
    check (note is null or char_length(note) <= 1000),
  constraint organiser_dispute_actions_club_name_len
    check (char_length(organiser_club_name) <= 200)
);

create index organiser_dispute_actions_target_idx
  on organiser_dispute_actions (target_kind, target_id, created_at desc);
create index organiser_dispute_actions_club_idx on organiser_dispute_actions (organiser_club_id);
create index organiser_dispute_actions_owner_idx on organiser_dispute_actions (target_owner_id);
create index organiser_dispute_actions_actor_idx on organiser_dispute_actions (actor_id);

-- Read only through the definer RPCs below, which never project actor_id to
-- either side. No client policy and no client grant: default-deny, and so
-- append-only for every client; only the definer bodies here write it.
alter table organiser_dispute_actions enable row level security;
revoke all on organiser_dispute_actions from public, anon, authenticated;
grant select, insert, update, delete on organiser_dispute_actions to service_role;

-- ── 2. Target facts, one place each ─────────────────────────────────────────

-- Who answers for the content: the club's owner, the route's, plan's,
-- routine's or challenge's author, and for a race listing the owner of the
-- club that claimed it (else whoever submitted it).
create or replace function private.organiser_dispute_target_owner(p_kind text, p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case p_kind
    when 'club'          then (select c.owner_id   from clubs c           where c.id = p_id)
    when 'route'         then (select r.user_id    from routes r          where r.id = p_id)
    when 'training_plan' then (select p.user_id    from training_plans p  where p.id = p_id)
    when 'gym_routine'   then (select g.author_id  from gym_routines g    where g.id = p_id)
    when 'challenge'     then (select ch.creator_id from challenges ch    where ch.id = p_id)
    when 'race_listing'  then (
      select coalesce(oc.owner_id, l.submitted_by)
        from race_listings l
        left join clubs oc on oc.id = l.organiser_club_id
       where l.id = p_id)
    else null
  end;
$$;

-- The content's name as it stands now.
create or replace function private.organiser_dispute_target_label(p_kind text, p_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case p_kind
    when 'club'          then (select c.name   from clubs c          where c.id = p_id)
    when 'route'         then (select r.name   from routes r         where r.id = p_id)
    when 'training_plan' then (select p.name   from training_plans p where p.id = p_id)
    when 'gym_routine'   then (select g.title  from gym_routines g   where g.id = p_id)
    when 'challenge'     then (select ch.title from challenges ch    where ch.id = p_id)
    when 'race_listing'  then (select l.name   from race_listings l  where l.id = p_id)
    else null
  end;
$$;

-- The club the content belongs to, if any (a club is its own).
create or replace function private.organiser_dispute_target_club(p_kind text, p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case p_kind
    when 'club'          then p_id
    when 'route'         then (select r.club_id  from routes r         where r.id = p_id)
    when 'training_plan' then (select p.club_id  from training_plans p where p.id = p_id)
    when 'gym_routine'   then (select g.club_id  from gym_routines g   where g.id = p_id)
    when 'challenge'     then (select ch.club_id from challenges ch    where ch.id = p_id)
    when 'race_listing'  then (select l.organiser_club_id from race_listings l where l.id = p_id)
    else null
  end;
$$;

-- Whether an organiser can have come across the content: what a stranger
-- may see of it. A race listing counts only while another club holds its
-- claim, since an unclaimed one the organiser can simply claim.
create or replace function private.organiser_dispute_target_visible(p_kind text, p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(case p_kind
    when 'club'          then (select c.is_public from clubs c where c.id = p_id)
    when 'route'         then (select r.is_public from routes r where r.id = p_id)
    when 'training_plan' then (select p.is_public_template from training_plans p where p.id = p_id)
    when 'gym_routine'   then (select g.is_public_template from gym_routines g where g.id = p_id)
    when 'challenge'     then (select ch.is_public from challenges ch where ch.id = p_id)
    when 'race_listing'  then (select l.organiser_club_id is not null from race_listings l where l.id = p_id)
    else false
  end, false);
$$;

-- A takedown stands while the latest hide/unhide on the target is a hide.
create or replace function private.organiser_dispute_hidden(p_kind text, p_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select a.action = 'takedown'
      from organiser_dispute_actions a
     where a.target_kind = p_kind
       and a.target_id = p_id
       and a.action in ('takedown', 'unhide')
     order by a.created_at desc, a.id desc
     limit 1
  ), false);
$$;

-- A plan whose library copy was taken down, while that takedown stands.
create or replace function private.organiser_dispute_source_locked(p_plan_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from (select distinct a.target_id
              from organiser_dispute_actions a
             where a.target_kind = 'training_plan'
               and a.source_plan_id = p_plan_id) t
     where private.organiser_dispute_hidden('training_plan', t.target_id)
  );
$$;

revoke execute on function private.organiser_dispute_source_locked(uuid) from public, anon, authenticated;
revoke execute on function private.organiser_dispute_target_owner(text, uuid) from public, anon, authenticated;
revoke execute on function private.organiser_dispute_target_label(text, uuid) from public, anon, authenticated;
revoke execute on function private.organiser_dispute_target_club(text, uuid) from public, anon, authenticated;
revoke execute on function private.organiser_dispute_target_visible(text, uuid) from public, anon, authenticated;
revoke execute on function private.organiser_dispute_hidden(text, uuid) from public, anon, authenticated;

-- ── 3. A takedown holds: no republish while it stands ───────────────────────

create or replace function private.organiser_dispute_publish_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce((to_jsonb(new) ->> tg_argv[1])::boolean, false)
     and not coalesce((to_jsonb(old) ->> tg_argv[1])::boolean, false)
     and private.organiser_dispute_hidden(tg_argv[0], new.id) then
    raise exception 'organiser_dispute_takedown'
      using errcode = '42501',
            hint = 'This was taken down after a naming dispute and cannot be published again until it is reviewed.';
  end if;
  return new;
end;
$$;

revoke execute on function private.organiser_dispute_publish_guard() from public, anon, authenticated;

create trigger training_plans_organiser_dispute_guard
  before update of is_public_template on training_plans
  for each row execute function private.organiser_dispute_publish_guard('training_plan', 'is_public_template');

-- A client publishes a plan only through publish_plan_to_library, which makes
-- a NEW library copy and then points the source's library_copy_id at it. The
-- row guard above cannot see that copy, so the lock also follows the lineage:
-- the source of a taken-down copy cannot be published again while the
-- takedown stands (the raise rolls the new copy back with it).
create or replace function private.organiser_dispute_republish_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.library_copy_id is not null
     and new.library_copy_id is distinct from old.library_copy_id
     and private.organiser_dispute_source_locked(new.id) then
    raise exception 'organiser_dispute_takedown'
      using errcode = '42501',
            hint = 'This plan''s library copy was taken down after a naming dispute and cannot be published again until it is reviewed.';
  end if;
  return new;
end;
$$;

revoke execute on function private.organiser_dispute_republish_guard() from public, anon, authenticated;

create trigger training_plans_organiser_dispute_lineage_guard
  before update of library_copy_id on training_plans
  for each row execute function private.organiser_dispute_republish_guard();

create trigger gym_routines_organiser_dispute_guard
  before update of is_public_template on gym_routines
  for each row execute function private.organiser_dispute_publish_guard('gym_routine', 'is_public_template');

create trigger challenges_organiser_dispute_guard
  before update of is_public on challenges
  for each row execute function private.organiser_dispute_publish_guard('challenge', 'is_public');

-- ── 4. No auto-hide from a dispute ──────────────────────────────────────────

-- Full body from 20270218_001; the vetted count leaves disputes out.
create or replace function auto_hide_target(
  p_target_kind text,
  p_target_id   uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vetted_count int;
  v_owner uuid;
begin
  if p_target_kind not in ('user', 'club', 'route') then
    return;
  end if;

  select count(distinct r.reporter_id)
    into v_vetted_count
  from reports r
  where r.target_kind = p_target_kind
    and r.target_id = p_target_id
    and r.status = 'pending'
    and r.reason <> 'organiser_dispute'
    and (
      select count(*) from runs run
      where run.user_id = r.reporter_id
        and run.is_public = true
    ) >= 5;

  if v_vetted_count < 3 then
    return;
  end if;

  if p_target_kind = 'user' then
    update user_profiles set shadow_hidden = true
      where id = p_target_id and shadow_hidden = false
      returning id into v_owner;
  elsif p_target_kind = 'club' then
    update clubs set shadow_hidden = true
      where id = p_target_id and shadow_hidden = false
      returning owner_id into v_owner;
  elsif p_target_kind = 'route' then
    update routes set shadow_hidden = true
      where id = p_target_id and shadow_hidden = false
      returning user_id into v_owner;
  end if;

  if v_owner is null then
    return;
  end if;

  insert into notifications (user_id, actor_id, kind)
  values (v_owner, null, 'content_hidden');
end;
$$;

revoke execute on function public.auto_hide_target(text, uuid) from public, anon, authenticated;

create or replace function reports_auto_hide_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.reason = 'organiser_dispute' then
    return NEW;
  end if;
  perform auto_hide_target(NEW.target_kind, NEW.target_id);
  return NEW;
end;
$$;

-- ── 5. Filing ───────────────────────────────────────────────────────────────

create or replace function submit_organiser_dispute(
  p_target_kind text,
  p_target_id uuid,
  p_club_id uuid,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_uid uuid := (select auth.uid());
  v_notes text := nullif(btrim(coalesce(p_notes, '')), '');
  v_club_name text;
  v_report_id uuid;
begin
  if v_uid is null then
    raise exception 'submit_organiser_dispute: not authorized' using errcode = '42501';
  end if;
  if not private.is_official_publisher(p_club_id, v_uid) then
    raise exception 'only an owner or admin of a verified club can report a naming dispute'
      using errcode = '42501';
  end if;
  if p_target_kind is null
     or p_target_kind not in ('club', 'route', 'training_plan', 'gym_routine', 'challenge', 'race_listing') then
    raise exception 'submit_organiser_dispute: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;
  if v_notes is not null and char_length(v_notes) > 600 then
    raise exception 'submit_organiser_dispute: notes too long' using errcode = '22023';
  end if;
  if not private.organiser_dispute_target_visible(p_target_kind, p_target_id) then
    raise exception 'submit_organiser_dispute: target % % not found', p_target_kind, p_target_id
      using errcode = '02000';
  end if;
  if private.organiser_dispute_target_club(p_target_kind, p_target_id) is not distinct from p_club_id then
    raise exception 'submit_organiser_dispute: this is your own club''s content'
      using errcode = '22023';
  end if;

  if private.organiser_dispute_target_owner(p_target_kind, p_target_id) is not distinct from v_uid then
    raise exception 'submit_organiser_dispute: this is your own content'
      using errcode = '22023';
  end if;

  perform enforce_create_rate_limit('create_report', v_uid, 10, 3600);

  begin
    insert into reports (reporter_id, target_kind, target_id, reason, notes, organiser_club_id)
    values (v_uid, p_target_kind, p_target_id, 'organiser_dispute', v_notes, p_club_id)
    returning id into v_report_id;
  exception when unique_violation then
    raise exception 'submit_report: already reported'
      using errcode = '23505',
            hint = 'You already have a pending report against this target.';
  end;

  select c.name into v_club_name from clubs c where c.id = p_club_id;
  insert into organiser_dispute_actions (
    target_kind, target_id, organiser_club_id, organiser_club_name, target_owner_id, actor_id, action, note
  )
  values (
    p_target_kind, p_target_id, p_club_id, left(v_club_name, 200),
    private.organiser_dispute_target_owner(p_target_kind, p_target_id), v_uid, 'filed', v_notes
  );

  return v_report_id;
end;
$$;

revoke execute on function submit_organiser_dispute(text, uuid, uuid, text) from public, anon;
grant execute on function submit_organiser_dispute(text, uuid, uuid, text) to authenticated;

-- ── 6. Review ───────────────────────────────────────────────────────────────

-- Both sides, no actor: the content's owner (and, for a club or a claimed
-- race listing, that club's active owner and admins), and each reporting
-- club's owner and active admins. The caller reads the owner side BEFORE a
-- hide, since releasing a race claim removes the club that answered for it.
create or replace function private.notify_organiser_dispute(
  p_owner uuid,
  p_owner_club uuid,
  p_clubs uuid[]
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into notifications (user_id, actor_id, kind, club_id)
  select distinct on (r.recipient) r.recipient, null::uuid, 'organiser_dispute', r.club_id
  from (
    select p_owner as recipient, p_clubs[1] as club_id
    union all
    select m.user_id, p_clubs[1]
      from club_members m
     where m.club_id = p_owner_club
       and m.status = 'active'
       and m.role in ('owner', 'admin')
    union all
    select m.user_id, m.club_id
      from club_members m
     where m.club_id = any (p_clubs)
       and m.status = 'active'
       and m.role in ('owner', 'admin')
    union all
    select c.owner_id, c.id from clubs c where c.id = any (p_clubs)
  ) r
  where r.recipient is not null
  order by r.recipient;
$$;

revoke execute on function private.notify_organiser_dispute(uuid, uuid, uuid[]) from public, anon, authenticated;

create or replace function resolve_organiser_dispute(
  p_target_kind text,
  p_target_id uuid,
  p_action text,
  p_note text default null,
  p_deadline_days integer default null
)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_admin uuid := (select auth.uid());
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_clubs uuid[];
  v_owner uuid;
  v_owner_club uuid;
  v_source_plan uuid;
  v_deadline timestamptz;
  v_count integer := 0;
begin
  if not private.is_admin(v_admin) then
    raise exception 'resolve_organiser_dispute: not authorized' using errcode = '42501';
  end if;
  if p_action is null or p_action not in ('takedown', 'rename_notice', 'dismiss') then
    raise exception 'resolve_organiser_dispute: invalid action %', p_action using errcode = '22023';
  end if;
  if v_note is not null and char_length(v_note) > 1000 then
    raise exception 'resolve_organiser_dispute: note too long' using errcode = '22023';
  end if;
  if p_action = 'rename_notice' then
    if p_deadline_days is not null and (p_deadline_days < 1 or p_deadline_days > 60) then
      raise exception 'resolve_organiser_dispute: deadline must be 1 to 60 days' using errcode = '22023';
    end if;
    v_deadline := now() + make_interval(days => coalesce(p_deadline_days, 14));
  end if;

  -- The lock serialises two reviewers acting on one target.
  perform 1 from reports r
   where r.target_kind = p_target_kind and r.target_id = p_target_id
     and r.status = 'pending' and r.reason = 'organiser_dispute'
   for update;
  if not found then
    raise exception 'resolve_organiser_dispute: no pending dispute on this target' using errcode = 'P0002';
  end if;

  -- Every reporting club still on record, oldest filing first.
  select coalesce(array_agg(x.organiser_club_id order by x.first_at), '{}')
    into v_clubs
    from (
      select r.organiser_club_id, min(r.created_at) as first_at
        from reports r
       where r.target_kind = p_target_kind
         and r.target_id = p_target_id
         and r.status = 'pending'
         and r.reason = 'organiser_dispute'
         and r.organiser_club_id is not null
       group by r.organiser_club_id
    ) x;

  -- Read before the hide: a released race listing no longer names the club
  -- that answered for it.
  v_owner := private.organiser_dispute_target_owner(p_target_kind, p_target_id);
  if p_target_kind in ('club', 'race_listing') then
    v_owner_club := private.organiser_dispute_target_club(p_target_kind, p_target_id);
  end if;
  if p_target_kind = 'training_plan' then
    select tp.id into v_source_plan from training_plans tp where tp.library_copy_id = p_target_id;
  end if;

  -- One log row per reporting club. A deleted club keeps the name its
  -- filing recorded.
  insert into organiser_dispute_actions (
    target_kind, target_id, organiser_club_id, organiser_club_name, target_owner_id,
    actor_id, action, deadline_at, note, source_plan_id
  )
  select p_target_kind, p_target_id, x.organiser_club_id,
         left(coalesce(
           (select c.name from clubs c where c.id = x.organiser_club_id),
           (select f.organiser_club_name from organiser_dispute_actions f
             where f.target_kind = p_target_kind and f.target_id = p_target_id
               and f.action = 'filed'
               and f.organiser_club_id is not distinct from x.organiser_club_id
             order by f.created_at desc, f.id desc limit 1),
           ''), 200),
         v_owner, v_admin, p_action, v_deadline, v_note, v_source_plan
    from (
      select r.organiser_club_id, min(r.created_at) as first_at
        from reports r
       where r.target_kind = p_target_kind
         and r.target_id = p_target_id
         and r.status = 'pending'
         and r.reason = 'organiser_dispute'
       group by r.organiser_club_id
    ) x
   order by x.first_at;

  if p_action = 'takedown' then
    if p_target_kind = 'club' then
      update clubs set shadow_hidden = true where id = p_target_id and shadow_hidden = false;
    elsif p_target_kind = 'route' then
      update routes set shadow_hidden = true where id = p_target_id and shadow_hidden = false;
    elsif p_target_kind = 'training_plan' then
      update training_plans set is_public_template = false where id = p_target_id and is_public_template;
    elsif p_target_kind = 'gym_routine' then
      update gym_routines set is_public_template = false where id = p_target_id and is_public_template;
    elsif p_target_kind = 'challenge' then
      update challenges set is_public = false where id = p_target_id and is_public;
    elsif p_target_kind = 'race_listing' then
      update race_listings
         set organiser_club_id = null,
             route_id = null,
             course_source = null,
             course_checked_at = null,
             course_updated_at = null,
             is_verified = case when provider = 'manual' then false else is_verified end
       where id = p_target_id;
    end if;
  end if;

  -- reviewed_by stays null: the reporter reads their own report rows, and
  -- the reviewer is not theirs to know. The log row above names them.
  if p_action in ('takedown', 'dismiss') then
    update reports
       set status      = case p_action when 'takedown' then 'reviewed' else 'dismissed' end,
           resolution  = v_note,
           reviewed_at = now()
     where target_kind = p_target_kind
       and target_id = p_target_id
       and status = 'pending'
       and reason = 'organiser_dispute';
    get diagnostics v_count = row_count;
  end if;

  perform private.notify_organiser_dispute(v_owner, v_owner_club, v_clubs);

  return v_count;
end;
$$;

revoke execute on function resolve_organiser_dispute(text, uuid, text, text, integer) from public, anon;
grant execute on function resolve_organiser_dispute(text, uuid, text, text, integer) to authenticated;

-- Full body from 20270218_001, widened to the dispute kinds: a plan,
-- routine or challenge takedown is lifted by logging 'unhide' (the owner
-- republishes when they choose); a released race claim cannot be undone
-- here, the rightful club claims it. A club or route hidden by a dispute
-- logs the lift too.
create or replace function admin_unhide_target(
  p_target_kind text,
  p_target_id   uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_admin uuid := auth.uid();
  v_rows integer := 0;
begin
  if not private.is_admin(v_admin) then
    raise exception 'admin_unhide_target: not authorized'
      using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route', 'training_plan', 'gym_routine', 'challenge') then
    raise exception 'admin_unhide_target: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_target_kind = 'user' then
    update user_profiles set shadow_hidden = false
      where id = p_target_id and shadow_hidden = true;
    get diagnostics v_rows = row_count;
  elsif p_target_kind = 'club' then
    update clubs set shadow_hidden = false
      where id = p_target_id and shadow_hidden = true;
    get diagnostics v_rows = row_count;
  elsif p_target_kind = 'route' then
    update routes set shadow_hidden = false
      where id = p_target_id and shadow_hidden = true;
    get diagnostics v_rows = row_count;
  elsif private.organiser_dispute_hidden(p_target_kind, p_target_id) then
    v_rows := 1;
  end if;

  if p_target_kind <> 'user' and private.organiser_dispute_hidden(p_target_kind, p_target_id) then
    insert into organiser_dispute_actions (
      target_kind, target_id, organiser_club_id, organiser_club_name, target_owner_id, actor_id, action,
      source_plan_id
    )
    select a.target_kind, a.target_id, a.organiser_club_id, a.organiser_club_name,
           private.organiser_dispute_target_owner(p_target_kind, p_target_id), v_admin, 'unhide',
           a.source_plan_id
      from organiser_dispute_actions a
     where a.target_kind = p_target_kind and a.target_id = p_target_id and a.action = 'takedown'
     order by a.created_at desc, a.id desc
     limit 1;
  end if;

  return v_rows > 0;
end;
$$;

revoke execute on function admin_unhide_target(text, uuid) from public, anon;
grant execute on function admin_unhide_target(text, uuid) to authenticated;

-- Body from 20270105_001; the general triage now leaves a target's dispute
-- reports to resolve_organiser_dispute, so a dispute is never closed without
-- its log entry and its notices.
create or replace function resolve_target_reports(
  p_target_kind text,
  p_target_id   uuid,
  p_status      text,
  p_resolution  text default null
)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_admin uuid := auth.uid();
  v_count integer;
begin
  if not private.is_admin(v_admin) then
    raise exception 'resolve_target_reports: not authorized'
      using errcode = '42501';
  end if;

  if p_status not in ('reviewed', 'dismissed') then
    raise exception 'resolve_target_reports: invalid status %', p_status
      using errcode = '22023';
  end if;

  update reports
    set status      = p_status,
        resolution  = p_resolution,
        reviewed_by = v_admin,
        reviewed_at = now()
  where target_kind = p_target_kind
    and target_id = p_target_id
    and status = 'pending'
    and reason <> 'organiser_dispute';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function resolve_target_reports(text, uuid, text, text) from public, anon;
grant execute on function resolve_target_reports(text, uuid, text, text) to authenticated;

-- ── 7. Admin reads ──────────────────────────────────────────────────────────

create or replace function private.report_target_page_id(p_kind text, p_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select case p_kind
    when 'user'          then (select up.id       from user_profiles up  where up.id = p_id)
    when 'club'          then (select c.id        from clubs c           where c.id = p_id)
    when 'route'         then (select rt.id       from routes rt         where rt.id = p_id)
    when 'run'           then (select ru.id       from runs ru           where ru.id = p_id)
    when 'comment'       then (select rc.run_id   from run_comments rc   where rc.id = p_id)
    when 'club_post'     then (select cp.club_id  from club_posts cp     where cp.id = p_id)
    when 'route_review'  then (select rr.route_id from route_reviews rr  where rr.id = p_id)
    when 'training_plan' then (select tp.id       from training_plans tp where tp.id = p_id)
    when 'gym_routine'   then (select g.id        from gym_routines g    where g.id = p_id)
    when 'challenge'     then (select ch.id       from challenges ch     where ch.id = p_id)
    when 'race_listing'  then (select l.id        from race_listings l   where l.id = p_id)
    else null
  end;
$$;

create or replace function private.report_target_shadow_hidden(p_kind text, p_id uuid)
returns boolean
language sql
stable
set search_path = public, private, pg_temp
as $$
  select coalesce(
    case p_kind
      when 'user'  then (select up.shadow_hidden from user_profiles up where up.id = p_id)
      when 'club'  then (select c.shadow_hidden  from clubs c          where c.id = p_id)
      when 'route' then (select rt.shadow_hidden from routes rt        where rt.id = p_id)
      when 'training_plan' then private.organiser_dispute_hidden(p_kind, p_id)
      when 'gym_routine'   then private.organiser_dispute_hidden(p_kind, p_id)
      when 'challenge'     then private.organiser_dispute_hidden(p_kind, p_id)
      else false
    end,
    false
  );
$$;

revoke execute on function private.report_target_page_id(text, uuid) from public, anon, authenticated;
revoke execute on function private.report_target_shadow_hidden(text, uuid) from public, anon, authenticated;

-- The rename deadline in force: the latest action on the target, when it is
-- a rename notice.
create or replace function private.organiser_dispute_deadline(p_kind text, p_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when a.action = 'rename_notice' then a.deadline_at end
    from organiser_dispute_actions a
   where a.target_kind = p_kind
     and a.target_id = p_id
     and a.action <> 'filed'
   order by a.created_at desc, a.id desc
   limit 1;
$$;

revoke execute on function private.organiser_dispute_deadline(text, uuid) from public, anon, authenticated;

-- Body from 20271021000040, with the shadow/page lookups now the shared
-- helpers, the three dispute columns, and disputes sorted first. The return
-- type grows, so drop and re-create.
drop function fetch_pending_reports();

create function fetch_pending_reports()
returns table (
  target_kind        text,
  target_id          uuid,
  report_count       bigint,
  reporter_count     bigint,
  reasons            jsonb,
  latest_at          timestamptz,
  shadow_hidden      boolean,
  page_id            uuid,
  organiser_dispute  boolean,
  organiser_clubs    jsonb,
  rename_deadline_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_pending_reports: not authorized'
      using errcode = '42501';
  end if;

  return query
    with pending as (
      select r.target_kind as tk, r.target_id as tid,
             r.reporter_id as rid, r.reason as rsn, r.created_at as cat,
             r.organiser_club_id as ocid
      from reports r
      where r.status = 'pending'
    ),
    by_reason as (
      select g.tk, g.tid, jsonb_object_agg(g.rsn, g.n) as reasons
      from (
        select p.tk, p.tid, p.rsn, count(*) as n
        from pending p
        group by p.tk, p.tid, p.rsn
      ) g
      group by g.tk, g.tid
    ),
    by_club as (
      select x.tk, x.tid,
             jsonb_agg(jsonb_build_object(
               'id', c.id, 'name', c.name, 'slug', c.slug, 'is_verified', c.is_verified
             ) order by x.first_at) as clubs
      from (
        select p.tk, p.tid, p.ocid, min(p.cat) as first_at
        from pending p
        where p.ocid is not null
        group by p.tk, p.tid, p.ocid
      ) x
      join clubs c on c.id = x.ocid
      group by x.tk, x.tid
    ),
    targets as (
      select
        p.tk,
        p.tid,
        count(*)                      as report_count,
        -- One pending row per (reporter, target) is unique-indexed, so each
        -- pending orphan is a distinct deleted reporter.
        count(distinct p.rid) + count(*) filter (where p.rid is null)
                                      as reporter_count,
        max(p.cat)                    as latest_at,
        bool_or(p.rsn = 'organiser_dispute') as dispute
      from pending p
      group by p.tk, p.tid
    )
    select
      t.tk,
      t.tid,
      t.report_count,
      t.reporter_count,
      br.reasons,
      t.latest_at,
      private.report_target_shadow_hidden(t.tk, t.tid),
      private.report_target_page_id(t.tk, t.tid),
      t.dispute,
      coalesce(bc.clubs, '[]'::jsonb),
      case when t.dispute then private.organiser_dispute_deadline(t.tk, t.tid) end
    from targets t
    join by_reason br on br.tk = t.tk and br.tid = t.tid
    left join by_club bc on bc.tk = t.tk and bc.tid = t.tid
    order by t.dispute desc, t.latest_at desc;
end;
$$;

revoke execute on function fetch_pending_reports() from public, anon;
grant execute on function fetch_pending_reports() to authenticated;

-- Body from 20271114000210 plus the reporting club. The return shape grows,
-- so drop and re-create.
drop function fetch_reports_for_target(text, uuid);

create function fetch_reports_for_target(p_target_kind text, p_target_id uuid)
returns table (
  id uuid,
  reporter_id uuid,
  reason text,
  notes text,
  status text,
  created_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  resolution text,
  snapshot_body text,
  snapshot_author_id uuid,
  snapshot_sent_at timestamptz,
  legal_hold boolean,
  purge_after timestamptz,
  snapshot_original_body text,
  organiser_club_id uuid,
  organiser_club_name text,
  organiser_club_slug text,
  organiser_club_verified boolean
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_reports_for_target: not authorized'
      using errcode = '42501';
  end if;

  return query
    select r.id, r.reporter_id, r.reason, r.notes, r.status,
           r.created_at, r.reviewed_at, r.reviewed_by, r.resolution,
           r.snapshot_body, r.snapshot_author_id, r.snapshot_sent_at,
           r.legal_hold,
           private.report_purge_after(r.status, r.reviewed_at, r.legal_hold),
           r.snapshot_original_body,
           r.organiser_club_id, c.name, c.slug, c.is_verified
    from reports r
    left join clubs c on c.id = r.organiser_club_id
    where r.target_kind = p_target_kind
      and r.target_id = p_target_id
    order by r.created_at desc;
end;
$$;

revoke execute on function fetch_reports_for_target(text, uuid) from public, anon;
grant execute on function fetch_reports_for_target(text, uuid) to authenticated, service_role;

create or replace function organiser_dispute_history(p_target_kind text, p_target_id uuid)
returns table (
  id bigint,
  action text,
  organiser_club_id uuid,
  organiser_club_name text,
  target_owner_id uuid,
  actor_id uuid,
  deadline_at timestamptz,
  note text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'organiser_dispute_history: not authorized' using errcode = '42501';
  end if;
  return query
    select a.id, a.action, a.organiser_club_id, a.organiser_club_name, a.target_owner_id,
           a.actor_id, a.deadline_at, a.note, a.created_at
      from organiser_dispute_actions a
     where a.target_kind = p_target_kind
       and a.target_id = p_target_id
     order by a.created_at desc, a.id desc;
end;
$$;

revoke execute on function organiser_dispute_history(text, uuid) from public, anon;
grant execute on function organiser_dispute_history(text, uuid) to authenticated;

-- ── 8. Each side's view ─────────────────────────────────────────────────────

-- One row per (dispute target, reporting club, side), carrying the latest
-- action. The owner's side starts at the first reviewer action (a filing
-- alone is not theirs to answer); the organiser's side includes its filing.
-- Never the reviewer.
create or replace function my_organiser_disputes()
returns table (
  side text,
  target_kind text,
  target_id uuid,
  target_label text,
  organiser_club_id uuid,
  organiser_club_name text,
  organiser_club_slug text,
  action text,
  deadline_at timestamptz,
  note text,
  acted_at timestamptz
)
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  with me as (select (select auth.uid()) as uid),
  mine as (
    select 'owner'::text as side, a.*
      from organiser_dispute_actions a, me
     where me.uid is not null
       and a.action <> 'filed'
       and (a.target_owner_id = me.uid
            or (a.target_kind in ('club', 'race_listing')
                and exists (
                  select 1 from club_members m
                   where m.club_id = private.organiser_dispute_target_club(a.target_kind, a.target_id)
                     and m.user_id = me.uid and m.status = 'active' and m.role in ('owner', 'admin'))))
    union all
    select 'organiser'::text, a.*
      from organiser_dispute_actions a, me
     where me.uid is not null
       and exists (
         select 1 from club_members m
          where m.club_id = a.organiser_club_id
            and m.user_id = me.uid and m.status = 'active' and m.role in ('owner', 'admin'))
  ),
  latest as (
    select distinct on (x.side, x.target_kind, x.target_id, x.organiser_club_id) x.*
      from mine x
     order by x.side, x.target_kind, x.target_id, x.organiser_club_id, x.created_at desc, x.id desc
  )
  select l.side, l.target_kind, l.target_id,
         private.organiser_dispute_target_label(l.target_kind, l.target_id),
         l.organiser_club_id, l.organiser_club_name, c.slug,
         l.action, l.deadline_at,
         -- A filing's note is the organiser's own complaint, for their side
         -- only; a reviewer's note is written for both sides.
         case when l.action = 'filed' and l.side = 'owner' then null else l.note end,
         l.created_at
    from latest l
    left join clubs c on c.id = l.organiser_club_id
   order by l.created_at desc;
$$;

revoke execute on function my_organiser_disputes() from public, anon;
grant execute on function my_organiser_disputes() to authenticated;
