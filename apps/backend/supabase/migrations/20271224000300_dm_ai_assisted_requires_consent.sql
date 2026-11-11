-- An `ai_assisted` direct message needs the athlete's consent to the
-- assistant, not only an active coaching link (audit of PR #1359, Low).
--
-- The marker says the coach drafted the text with the assistant, which reads
-- the athlete's data. /api/coach/assist refuses a draft unless the link is
-- active and the athlete consented on it (coach_athletes
-- .ai_assist_consent_version, 1 .. coach_assist_consent_current_version()),
-- but the send policy admitted the kind from any active coach of the
-- recipient, so a coach whose athlete never consented, or withdrew, could
-- still file messages carrying the label. The policy now asks the same two
-- questions the endpoint does, through private.coach_assist_admitted. The
-- block check the endpoint also makes is the policy's own, above it. The
-- deploy flag, the coach's AI disclosure and Pro stay the endpoint's: they
-- gate the draft, and say nothing about the athlete.
--
-- Locks: ALTER POLICY takes a brief ACCESS EXCLUSIVE on direct_messages for
-- the catalog change only; nothing is scanned.

create or replace function private.coach_assist_admitted(p_coach_id uuid, p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from coach_athletes ca
     where ca.coach_id = p_coach_id
       and ca.athlete_id = p_athlete_id
       and ca.status = 'active'
       and ca.ai_assist_consent_version between 1 and coach_assist_consent_current_version()
  );
$$;

revoke execute on function private.coach_assist_admitted(uuid, uuid) from public, anon;
grant execute on function private.coach_assist_admitted(uuid, uuid) to authenticated;

comment on function private.coach_assist_admitted(uuid, uuid) is
  'Whether p_coach_id may send p_athlete_id a message marked ai_assisted: an '
  'active coaching link whose athlete consented to the assistant at a version '
  'this release knows. The send policy''s half of /api/coach/assist''s gates.';

alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    direct_messages.sender_id = (select auth.uid())
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
    and direct_messages.coach_message_id is null
    and (
      (
        not direct_messages.is_group
        and not is_blocked_either_way(direct_messages.sender_id, direct_messages.recipient_id)
        and private.dm_send_admitted(direct_messages.recipient_id)
        and (
          direct_messages.kind = 'text'
          or (
            direct_messages.kind = 'ai_assisted'
            and private.coach_assist_admitted((select auth.uid()), direct_messages.recipient_id)
          )
        )
        and (
          direct_messages.image_id is null
          or private.dm_image_send_admitted(direct_messages.recipient_id, direct_messages.image_id)
        )
      )
      or (
        direct_messages.is_group
        and direct_messages.kind = 'text'
        and private.group_send_admitted(direct_messages.conversation_id)
        and (
          direct_messages.image_id is null
          or private.dm_group_image_send_admitted(direct_messages.image_id)
        )
      )
    )
  );
