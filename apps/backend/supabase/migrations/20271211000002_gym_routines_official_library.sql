-- An official gym routine can reach the public library (issue #1190,
-- decisions § 2446).
--
-- "Official" is derived from the routine's club (`is_official`, § 2228), and
-- `gym_routines_public_not_club` kept every public template club-free, so no
-- routine in the public library could ever read as official. The CHECK goes,
-- and its rule moves to a trigger that holds it for client writes only:
-- anon and authenticated still cannot insert a public club routine, flip a
-- club routine public, or move a public routine into a club, exactly as
-- before. `set_gym_routine_public` (definer) keeps its own club-owned refusal
-- and `clone_gym_routine_template` still writes a club-free private copy, so
-- the one writer that now makes a public club template is the service-role
-- catalogue load (20271211000004). A club admin may still edit or unpublish
-- such a routine through the existing club-admin policies; the next load
-- writes the catalogue's version back.
--
-- public_gym_routines gains a trailing `is_official` (until now it "could
-- only ever be false", § 2228), and its `club_id` is masked unless the club
-- is public, as public_routes does, so a public routine never names a
-- private club.
--
-- Locks (docs/backend/migration_locks.md): gym_routines is a small per-user
-- table. Dropping a CHECK and creating a trigger each take a brief lock with
-- no scan; `create or replace view` with a trailing column locks only the
-- view.

alter table public.gym_routines drop constraint gym_routines_public_not_club;

create or replace function private.gym_routines_public_not_club()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if new.is_public_template and new.club_id is not null
     and (tg_op = 'INSERT'
          or not old.is_public_template
          or old.club_id is distinct from new.club_id) then
    raise exception 'gym_routines: a club routine cannot be published to the public library'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke execute on function private.gym_routines_public_not_club() from public, anon, authenticated;

create trigger gym_routines_public_not_club
  before insert or update of is_public_template, club_id on public.gym_routines
  for each row execute function private.gym_routines_public_not_club();

create or replace view public.public_gym_routines as
select
  r.id,
  r.author_id,
  case when is_public_club_by_id(r.club_id) then r.club_id else null::uuid end as club_id,
  r.is_public_template,
  r.title,
  r.notes,
  r.periodisation,
  r.exercise_count,
  r.created_at,
  (r.club_id is not null and private.is_official_publisher(r.club_id, r.author_id)) as is_official
from public.gym_routines r
where r.is_public_template = true;
