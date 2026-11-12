-- RSVP, edit and delete notifications on `events` and `event_attendees`
-- (decisions § 2358, issue #1300 BUG-009 / BUG-016). The kinds, the
-- `event_title` column and the dropped RSVP index are 20271112000010; this
-- file replaces the RSVP trigger function and adds the two `events` triggers.
-- CREATE OR REPLACE FUNCTION takes no table lock; CREATE TRIGGER takes SHARE
-- ROW EXCLUSIVE on `events`, catalogue-only, with no lock on `notifications`
-- held alongside it.

-- ── 1. RSVPs: wider recipients, per-occurrence 24 h dedupe ─────────────────

create or replace function public.notify_event_rsvp()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_club uuid;
  v_creator uuid;
begin
  if NEW.status is distinct from 'going' then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' and OLD.status = 'going' then
    return NEW;
  end if;

  select club_id, author_id into v_club, v_creator
  from events where id = NEW.event_id;
  if v_club is null then
    return NEW;
  end if;

  -- Serialises two racing RSVPs from one member to one occurrence, which the
  -- window check below cannot see from inside each other's transactions.
  perform pg_advisory_xact_lock(hashtextextended(
    'event_rsvp|' || NEW.event_id::text || '|' || NEW.user_id::text || '|'
      || coalesce(NEW.instance_start::text, ''), 0));

  insert into notifications (user_id, actor_id, kind, event_id, event_instance_start)
  select r.recipient, NEW.user_id, 'event_rsvp', NEW.event_id, NEW.instance_start
  from (
    select v_creator as recipient
    union
    select cm.user_id
    from club_members cm
    where cm.club_id = v_club
      and cm.status = 'active'
      and cm.role in ('owner', 'admin', 'event_organiser', 'race_director')
  ) r
  where r.recipient is not null
    and r.recipient <> NEW.user_id
    and not exists (
      select 1 from notifications n
      where n.user_id = r.recipient
        and n.actor_id = NEW.user_id
        and n.kind = 'event_rsvp'
        and n.event_id = NEW.event_id
        and n.event_instance_start is not distinct from NEW.instance_start
        and n.created_at > now() - interval '24 hours'
    );

  return NEW;
end;
$function$;

-- ── 2. event edited ─────────────────────────────────────────────────────────

-- Everyone holding a place on an occurrence of the event that has not
-- started and has not been cancelled, with the earliest such occurrence.
create or replace function private.event_upcoming_attendees(p_event uuid)
returns table (user_id uuid, instance_start timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select p.user_id, min(p.instance_start)
  from (
    select a.user_id, a.instance_start
    from public.event_attendees a
    where a.event_id = p_event
      and a.status in ('going', 'maybe', 'waitlisted')
    union all
    select o.buyer_user_id, o.instance_start
    from public.event_orders o
    where o.event_id = p_event
      and o.status in ('paid', 'partially_refunded')
  ) p
  where p.user_id is not null
    and p.instance_start >= now()
    and not exists (
      select 1 from public.event_exceptions x
      where x.event_id = p_event and x.instance_start = p.instance_start
    )
  group by p.user_id;
$$;

revoke execute on function private.event_upcoming_attendees(uuid) from public, anon, authenticated;

create or replace function private.notify_event_updated()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  perform pg_advisory_xact_lock(hashtextextended('event_updated|' || new.id::text, 0));

  insert into public.notifications (user_id, actor_id, kind, event_id, event_instance_start)
  select u.user_id, v_actor, 'event_updated', new.id, u.instance_start
  from private.event_upcoming_attendees(new.id) u
  where u.user_id is distinct from v_actor
    and not exists (
      select 1 from public.notifications n
      where n.user_id = u.user_id
        and n.kind = 'event_updated'
        and n.event_id = new.id
        and n.created_at > now() - interval '15 minutes'
    );
  return null;
end;
$$;

revoke execute on function private.notify_event_updated() from public, anon, authenticated;

create trigger events_notify_updated
  after update of starts_at, duration_min, timezone, recurrence_freq, recurrence_byday,
                  recurrence_until, recurrence_count, meet_lat, meet_lng, meet_label,
                  description on public.events
  for each row
  when (old.starts_at        is distinct from new.starts_at
     or old.duration_min     is distinct from new.duration_min
     or old.timezone         is distinct from new.timezone
     or old.recurrence_freq  is distinct from new.recurrence_freq
     or old.recurrence_byday is distinct from new.recurrence_byday
     or old.recurrence_until is distinct from new.recurrence_until
     or old.recurrence_count is distinct from new.recurrence_count
     or old.meet_lat         is distinct from new.meet_lat
     or old.meet_lng         is distinct from new.meet_lng
     or old.meet_label       is distinct from new.meet_label
     or old.description      is distinct from new.description)
  execute function private.notify_event_updated();

-- ── 3. event deleted ────────────────────────────────────────────────────────

create or replace function private.notify_event_deleted()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_club  uuid;
begin
  -- A club or account delete cascades here after its own row is gone, and a
  -- notification naming that row would fail its foreign key and abort the
  -- whole delete; the notice is sent without the link instead.
  select c.id into v_club from public.clubs c where c.id = old.club_id;
  if v_actor is not null and not exists (select 1 from auth.users u where u.id = v_actor) then
    v_actor := null;
  end if;

  -- An account delete reaches here through `events.author_id`; the author's
  -- own place on the event names a user who no longer exists.
  insert into public.notifications (user_id, actor_id, kind, club_id, event_title, event_instance_start)
  select u.user_id, v_actor, 'event_cancel', v_club, old.title, u.instance_start
  from private.event_upcoming_attendees(old.id) u
  where u.user_id is distinct from v_actor
    and exists (select 1 from auth.users x where x.id = u.user_id);
  return old;
end;
$$;

revoke execute on function private.notify_event_deleted() from public, anon, authenticated;

create trigger events_notify_deleted
  before delete on public.events
  for each row
  execute function private.notify_event_deleted();
