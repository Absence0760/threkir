-- Reports outlive their reporter, gain a legal hold, and get a retention
-- window that is built but switched off (decisions § 2231).
--
-- ── 1. Reporter deletion keeps the report, pseudonymised ──────────────────
--
-- `reports.reporter_id` cascaded since 20260908_001, so a harassment victim
-- who deleted their account destroyed every report they had filed — the
-- evidence about the person they reported, including the direct-message
-- snapshot 20271021000003 copies into the report (§ 2221). The FK becomes ON
-- DELETE SET NULL: the report, its reason, notes and snapshot stay; the
-- reporter becomes "Deleted account". Nothing derived from the leaver's id is
-- kept on the row.
--
-- Readers of a null reporter, each checked:
--   * RLS "reporters read their own reports" compares auth.uid() to
--     reporter_id — a null matches no caller, so an orphaned report is
--     readable by moderators only.
--   * reports_no_duplicate_pending is unique on (reporter_id, target_kind,
--     target_id) WHERE pending; nulls are distinct, so orphaned rows never
--     collide with each other or with a live reporter.
--   * auto_hide_target() counts DISTINCT VETTED reporters (>= 5 public runs).
--     A null reporter owns no runs, so it is never vetted and never counted:
--     an account that deleted itself cannot help hide a target. Left as is —
--     the trigger only fires on INSERT, and submit_report always inserts a
--     non-null reporter — and pinned by reports_retention_test.
--   * fetch_pending_reports' reporter_count used count(distinct reporter_id),
--     which drops nulls, so a deleted reporter vanished from the count while
--     report_count still included them. Re-emitted below to add one per
--     pending null row. That is exact, not an estimate: the partial unique
--     index allowed one pending row per (reporter, target), so every pending
--     orphan was filed by a different, now-deleted person, none of whom is a
--     live reporter.
--   * fetch_reports_for_target returns reporter_id, now nullable; the
--     /admin/reports page renders a null as "Deleted account".
--   * The Art 20 exports select by reporter_id = the subject (own reports) or
--     by target / snapshot author with reporter_id projected away, so an
--     orphaned report is in nobody's archive — correct, the reporter is gone.
--
-- ── 2. Legal hold ──────────────────────────────────────────────────────────
--
-- `legal_hold boolean not null default false`. A held report is never purged
-- (3) and is kept by delete-account's sweep of reports naming the deleted user
-- as their target. Set only by set_report_legal_hold (admin-gated) or the
-- service role. Every client write verb on `reports` is revoked below: no
-- write policy existed, so RLS already refused, but the table-level grants
-- from 20270408_001 meant any future write policy would open legal_hold,
-- status and reviewed_at with it. submit_report is SECURITY DEFINER and
-- unaffected.
--
-- ── 3. Retention window, fail-closed off ───────────────────────────────────
--
-- private.purge_stale_reports() deletes RESOLVED reports (and so their
-- snapshots) a fixed time after `reviewed_at`:
--   * `dismissed` (no action taken)          — 6 months
--   * `reviewed`  ("Mark reviewed": acted on) — 12 months
-- The schema has exactly these two resolved states and the moderator picks
-- one ("Dismiss" vs "Mark reviewed", whose note prompt is "What action did you
-- take?"), so no new column is needed. A `reviewed` that was in fact a no-op
-- falls in the longer window, the safe direction. Never deleted: a pending
-- report, a held report, or a resolved row with no reviewed_at.
--
-- The windows live in ONE place, private.report_retention_window(), which the
-- purge and the admin read (purge_after) both call.
--
-- The purge runs daily from pg_cron, the 20261119_001 pattern, but does
-- nothing unless `private.feature_flags` has `reports_retention_purge` enabled.
-- An absent row is off and no migration writes one: the window waits on
-- counsel's sign-off (CLAUDE.md § Compliance sign-offs gate prod, not code).
--
-- ── Locking ────────────────────────────────────────────────────────────────
--
-- `reports` is not one of migration_locks.md's high-volume tables; the house
-- pattern is followed anyway. DROP NOT NULL and ADD COLUMN ... DEFAULT false
-- are catalogue-only. The re-pointed FK is added NOT VALID (brief ACCESS
-- EXCLUSIVE, no scan) and validated by 20271021000041 in its own transaction.
-- REVOKE takes no relation lock. No row is rewritten or backfilled. No index
-- is added for the purge: it scans a table the purge itself bounds, once a day.

-- ─── reports: reporter set-null + legal hold ─────────────────────────────

alter table reports
  alter column reporter_id drop not null;

alter table reports
  drop constraint reports_reporter_id_fkey,
  add constraint reports_reporter_id_fkey
    foreign key (reporter_id) references auth.users (id) on delete set null
    not valid;

alter table reports
  add column legal_hold boolean not null default false;

comment on column reports.reporter_id is
  'Who filed the report. ON DELETE SET NULL (20271021000040): a reporter''s '
  'account deletion keeps the report and its snapshot as evidence, with the '
  'reporter shown as "Deleted account".';

comment on column reports.legal_hold is
  'When true the report is never removed by purge_stale_reports() nor by '
  'delete-account''s sweep of reports against the deleted user. Written only '
  'by set_report_legal_hold() (admin) or the service role.';

revoke insert, update, delete on reports from anon, authenticated;

-- ─── the retention windows: the one place they are written ──────────────

create or replace function private.report_retention_window(p_status text)
returns interval
language sql
immutable
set search_path = public, pg_temp
as $$
  select case p_status
    when 'dismissed' then interval '6 months'
    when 'reviewed'  then interval '12 months'
    else null
  end;
$$;

revoke execute on function private.report_retention_window(text) from public, anon, authenticated;

comment on function private.report_retention_window(text) is
  'Retention after resolution per report status: dismissed (no action) 6 '
  'months, reviewed (action taken) 12 months, null (never) otherwise. The '
  'single source for purge_stale_reports() and the admin purge_after column. '
  'Pending counsel sign-off (decisions § 2231).';

-- When a report becomes eligible for the purge; null when it never will.
-- STABLE, not IMMUTABLE: timestamptz + a month interval depends on TimeZone.
create or replace function private.report_purge_after(
  p_status text,
  p_reviewed_at timestamptz,
  p_legal_hold boolean
)
returns timestamptz
language sql
stable
set search_path = public, private, pg_temp
as $$
  select case
    when p_legal_hold or p_reviewed_at is null then null
    else p_reviewed_at + private.report_retention_window(p_status)
  end;
$$;

revoke execute on function private.report_purge_after(text, timestamptz, boolean) from public, anon, authenticated;

-- ─── purge_stale_reports + its gate ─────────────────────────────────────

create or replace function private.purge_stale_reports()
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_deleted bigint;
begin
  if not coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'reports_retention_purge'),
    false
  ) then
    return;
  end if;

  with deleted as (
    delete from reports r
    where r.status in ('reviewed', 'dismissed')
      and not r.legal_hold
      and private.report_purge_after(r.status, r.reviewed_at, r.legal_hold) < now()
    returning 1
  )
  select count(*) into v_deleted from deleted;
  if v_deleted > 0 then
    raise notice 'purge_stale_reports: removed % row(s)', v_deleted;
  end if;
end;
$$;

revoke all on function private.purge_stale_reports() from public, anon, authenticated;

select cron.schedule(
  'purge-stale-reports',
  '59 3 * * *',  -- 03:59 UTC daily — after the other 03:xx retention jobs
                 -- (17/23/29/35/41/47/53).
  $$select private.purge_stale_reports()$$
);

comment on function private.purge_stale_reports() is
  'GDPR Art 5(1)(e) storage limitation for reports: deletes resolved, '
  'unheld reports (and their direct-message snapshots) once '
  'private.report_retention_window() has passed since reviewed_at. Never '
  'touches a pending or legal_hold report. Does nothing unless '
  'private.feature_flags has reports_retention_purge enabled (absent = off), '
  'pending counsel sign-off. Scheduled by pg_cron `purge-stale-reports` '
  '(03:59 UTC daily). decisions § 2231.';

-- ─── target lookups for fetch_resolved_reports ──────────────────────────
--
-- Called only from that SECURITY DEFINER read, so they run as the function
-- owner and see past RLS (an admin reads no other user's private run through
-- RLS). Copies of 20271021000020's per-kind cases; fetch_pending_reports
-- below keeps its own inline copy so its re-emit stays a one-change diff.

create or replace function private.report_target_page_id(p_kind text, p_id uuid)
returns uuid
language sql
stable
set search_path = public, pg_temp
as $$
  select case p_kind
    when 'user'         then (select up.id       from user_profiles up where up.id = p_id)
    when 'club'         then (select c.id        from clubs c          where c.id = p_id)
    when 'route'        then (select rt.id       from routes rt        where rt.id = p_id)
    when 'run'          then (select ru.id       from runs ru          where ru.id = p_id)
    when 'comment'      then (select rc.run_id   from run_comments rc  where rc.id = p_id)
    when 'club_post'    then (select cp.club_id  from club_posts cp    where cp.id = p_id)
    when 'route_review' then (select rr.route_id from route_reviews rr where rr.id = p_id)
    else null
  end;
$$;

create or replace function private.report_target_shadow_hidden(p_kind text, p_id uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(
    case p_kind
      when 'user'  then (select up.shadow_hidden from user_profiles up where up.id = p_id)
      when 'club'  then (select c.shadow_hidden  from clubs c          where c.id = p_id)
      when 'route' then (select rt.shadow_hidden from routes rt        where rt.id = p_id)
      else false
    end,
    false
  );
$$;

revoke execute on function private.report_target_page_id(text, uuid) from public, anon, authenticated;
revoke execute on function private.report_target_shadow_hidden(text, uuid) from public, anon, authenticated;

-- ─── fetch_pending_reports: a deleted reporter still counts ─────────────
--
-- Full body re-emitted from 20271021000020 (still `stable`); the only change
-- is the reporter_count fix from (1). Return type unchanged, so CREATE OR
-- REPLACE keeps the grants; they are restated anyway.

create or replace function fetch_pending_reports()
returns table (
  target_kind     text,
  target_id       uuid,
  report_count    bigint,
  reporter_count  bigint,
  reasons         jsonb,
  latest_at       timestamptz,
  shadow_hidden   boolean,
  page_id         uuid
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
             r.reporter_id as rid, r.reason as rsn, r.created_at as cat
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
    )
    select
      p.tk,
      p.tid,
      count(*)                      as report_count,
      -- One pending row per (reporter, target) is unique-indexed, so each
      -- pending orphan is a distinct deleted reporter.
      count(distinct p.rid) + count(*) filter (where p.rid is null)
                                    as reporter_count,
      br.reasons,
      max(p.cat)                    as latest_at,
      coalesce(
        case p.tk
          when 'user'  then (select up.shadow_hidden from user_profiles up where up.id = p.tid)
          when 'club'  then (select c.shadow_hidden  from clubs c          where c.id = p.tid)
          when 'route' then (select rt.shadow_hidden from routes rt        where rt.id = p.tid)
          else false
        end,
        false
      )                             as shadow_hidden,
      case p.tk
        when 'user'         then (select up.id       from user_profiles up where up.id = p.tid)
        when 'club'         then (select c.id        from clubs c          where c.id = p.tid)
        when 'route'        then (select rt.id       from routes rt        where rt.id = p.tid)
        when 'run'          then (select ru.id       from runs ru          where ru.id = p.tid)
        when 'comment'      then (select rc.run_id   from run_comments rc  where rc.id = p.tid)
        when 'club_post'    then (select cp.club_id  from club_posts cp    where cp.id = p.tid)
        when 'route_review' then (select rr.route_id from route_reviews rr where rr.id = p.tid)
        else null
      end                           as page_id
    from pending p
    join by_reason br on br.tk = p.tk and br.tid = p.tid
    group by p.tk, p.tid, br.reasons
    order by max(p.cat) desc;
end;
$$;

revoke execute on function fetch_pending_reports() from public, anon;
grant execute on function fetch_pending_reports() to authenticated;

-- ─── fetch_resolved_reports: where a hold is placed after resolution ────
--
-- The pending queue drops a target once its last report is resolved, and a
-- resolved report is the only kind the purge can delete — so without this
-- list a hold could only be placed while the target still had something
-- pending. One row per target with at least one resolved report, capped,
-- ordered by the earliest purge date first: the cap must never hide the
-- reports closest to deletion, which are the ones a hold has to reach before
-- the next 03:59 run. Fully held targets (no purge date) follow, most
-- recently resolved first.

create or replace function fetch_resolved_reports(p_limit int default 100)
returns table (
  target_kind      text,
  target_id        uuid,
  report_count     bigint,
  held_count       bigint,
  last_reviewed_at timestamptz,
  next_purge_after timestamptz,
  shadow_hidden    boolean,
  page_id          uuid
)
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'fetch_resolved_reports: not authorized'
      using errcode = '42501';
  end if;

  return query
    select
      r.target_kind,
      r.target_id,
      count(*)                                  as report_count,
      count(*) filter (where r.legal_hold)      as held_count,
      max(r.reviewed_at)                        as last_reviewed_at,
      min(private.report_purge_after(r.status, r.reviewed_at, r.legal_hold))
                                                as next_purge_after,
      private.report_target_shadow_hidden(r.target_kind, r.target_id),
      private.report_target_page_id(r.target_kind, r.target_id)
    from reports r
    where r.status <> 'pending'
    group by r.target_kind, r.target_id
    order by min(private.report_purge_after(r.status, r.reviewed_at, r.legal_hold)) asc nulls last,
             max(r.reviewed_at) desc nulls last
    limit least(greatest(coalesce(p_limit, 100), 1), 500);
end;
$$;

revoke execute on function fetch_resolved_reports(int) from public, anon;
grant execute on function fetch_resolved_reports(int) to authenticated;

-- ─── fetch_reports_for_target: legal_hold + purge_after ─────────────────
--
-- The return shape grows, so drop and re-create; body is 20271021000003's.

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
  purge_after timestamptz
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
           private.report_purge_after(r.status, r.reviewed_at, r.legal_hold)
    from reports r
    where r.target_kind = p_target_kind
      and r.target_id = p_target_id
    order by r.created_at desc;
end;
$$;

revoke execute on function fetch_reports_for_target(text, uuid) from public, anon;
grant execute on function fetch_reports_for_target(text, uuid) to authenticated, service_role;

-- ─── set_report_legal_hold: the admin write ─────────────────────────────

create or replace function set_report_legal_hold(p_report_id uuid, p_hold boolean)
returns boolean
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_hold boolean;
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'set_report_legal_hold: not authorized'
      using errcode = '42501';
  end if;

  if p_hold is null then
    raise exception 'set_report_legal_hold: hold must be true or false'
      using errcode = '22004';
  end if;

  update reports
     set legal_hold = p_hold
   where id = p_report_id
  returning legal_hold into v_hold;

  if v_hold is null then
    raise exception 'set_report_legal_hold: report not found'
      using errcode = 'P0002';
  end if;

  return v_hold;
end;
$$;

revoke execute on function set_report_legal_hold(uuid, boolean) from public, anon;
grant execute on function set_report_legal_hold(uuid, boolean) to authenticated, service_role;

comment on function set_report_legal_hold(uuid, boolean) is
  'Admin-only: place or lift a legal hold on one report. A held report is '
  'kept by purge_stale_reports() and by delete-account. Idempotent; P0002 '
  'for an unknown id. decisions § 2231.';
