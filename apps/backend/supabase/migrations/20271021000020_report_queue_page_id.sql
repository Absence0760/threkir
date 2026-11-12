-- The moderation queue links each reported target to the page that shows it,
-- and for four of the eight target kinds that page is not the target's own:
-- a comment lives on its run, a club post on its club, a review on its route.
-- The queue returned only `target_id`, so /admin/reports could not build those
-- links and fell through to `/clubs/<target_id>` for every kind it had no arm
-- for — a comment, post, run or review report opened as a missing club.
--
-- fetch_pending_reports gains `page_id`: the id the moderator's link opens.
-- The target itself for user / club / route / run; the parent run / club /
-- route for comment / club_post / route_review; null for a direct message
-- (the thread belongs to its two participants, so its evidence is the
-- report-time snapshot) and for a target whose row is gone. Resolved here
-- rather than by a client read because the parent may be private, and an
-- admin reads no other user's private run through RLS.
--
-- Full body re-emitted from 20270218_001 (the bare-body rule), still `stable`
-- per 20270722000001. The return type grows a column, so the old signature is
-- dropped first; that drop takes the grants with it, so they are restated,
-- including the anon revoke from 20270626000001.
--
-- Locks: function DDL only — no table lock, scan or rewrite.

drop function if exists fetch_pending_reports();
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
      count(distinct p.rid)         as reporter_count,
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
