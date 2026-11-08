-- The course-suggestion review queue across races (issue #1297, decisions
-- § 2396).
--
-- race_course_suggestions_for_review (20271114002381) answers for one race,
-- so a verified club's admin only found a pending suggestion by opening that
-- race's page, and nothing listed suggestions on races nobody had claimed.
-- race_course_review_queue() lists every race with at least one pending
-- suggestion the caller may review there, under the same rule:
--
--   * a claimed race, to an active owner/admin of its organiser club while
--     that club is verified, public and not hidden (is_official_publisher);
--   * an unclaimed race, to an active owner/admin of ANY such club, who
--     reviews it by claiming it first.
--
-- It counts only the suggestions the per-race queue would return (a pending
-- suggestion whose route is public and not hidden), never names a suggester,
-- and writes nothing: claiming and reviewing stay the existing RPCs.
--
-- Locks: a new function only.

set search_path = public, extensions;

create or replace function race_course_review_queue()
returns table (
  listing_id        uuid,
  name              text,
  race_date         date,
  organiser_club_id uuid,
  pending_count     integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_any_publisher boolean;
begin
  if v_uid is null then
    return;
  end if;

  select exists (
    select 1 from club_members m
     where m.user_id = v_uid
       and m.status = 'active'
       and m.role in ('owner', 'admin')
       and private.is_official_publisher(m.club_id, v_uid)
  ) into v_any_publisher;
  if not v_any_publisher then
    return;
  end if;

  return query
    select l.id, l.name, l.race_date, l.organiser_club_id, count(*)::integer
      from race_listings l
      join race_course_suggestions s
        on s.listing_id = l.id
       and s.status = 'pending'
      join routes r
        on r.id = s.route_id
       and r.is_public = true
       and r.shadow_hidden = false
     where l.organiser_club_id is null
        or private.is_official_publisher(l.organiser_club_id, v_uid)
     group by l.id, l.name, l.race_date, l.organiser_club_id
     order by l.race_date, l.name
     limit 200;
end;
$$;

revoke execute on function race_course_review_queue() from public, anon;
grant execute on function race_course_review_queue() to authenticated;
