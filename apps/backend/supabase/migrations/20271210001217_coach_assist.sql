-- A private AI assistant for coaches (issue #1215 Phase 4).
--
-- In a conversation with an athlete they coach, a coach can ask the AI for a
-- draft reply or a plan suggestion. Only the coach sees the draft; they edit
-- it and send it as themselves, and the message carries an "AI-assisted"
-- marker on both sides. The drafting endpoint (apps/web/src/lib/coach/
-- assist/) sends the ATHLETE's data to Anthropic under the coach's account,
-- which is why this needs the athlete's own consent, per coaching link.
--
-- ── The athlete's consent ───────────────────────────────────────────────
--
-- coach_athletes.ai_assist_consent_version / ai_assist_consent_at: the
-- athlete's acceptance of the coach-assistant copy for THIS link, at a
-- version of its own ladder (coach_assist_consent_current_version(), 1 for
-- now; a version only ever widens what it names, as the AI disclosure's
-- ladder does). Null is no consent. It is written only by
-- set_coach_ai_assist_consent, by the athlete, on an active link, and is
-- cleared when either party ends the link. A coach can never set it: the
-- invite INSERT policy now refuses a row that carries it, and no client holds
-- an UPDATE path to coach_athletes.
--
-- The endpoint sends nothing unless all three hold, each checked server-side:
-- the athlete's consent on the active link, the coach's own AI disclosure at
-- the version naming the assistant, and the deploy flag (COACH_ASSIST_ENABLED,
-- default off everywhere). Each data lane is gated on the athlete's consent
-- version through COACH_ASSIST_CONTEXT_REGISTRY, the #1217 pattern.
--
-- ── The marker ──────────────────────────────────────────────────────────
--
-- direct_messages.kind gains 'ai_assisted'. It is the sender's own label on
-- their own words, so a client sets it, and the INSERT policy admits it only
-- from a coach to an athlete they actively coach: nobody else has an
-- assistant to declare. 'coach_share' stays RPC-only.
--
-- ── Locks ───────────────────────────────────────────────────────────────
--
-- Both ADD COLUMNs are nullable with no default (catalogue-only). The new
-- coach_athletes CHECK and the swapped direct_messages.kind CHECK go on NOT
-- VALID and are validated by 20271210001218 in its own transaction. The rest
-- is functions and policy expressions.

alter table coach_athletes
  add column ai_assist_consent_version smallint,
  add column ai_assist_consent_at timestamptz;

alter table coach_athletes
  add constraint coach_athletes_ai_assist_consent_check
    check (
      (ai_assist_consent_version is null) = (ai_assist_consent_at is null)
      and (ai_assist_consent_version is null or ai_assist_consent_version >= 1)
    )
    not valid;

comment on column coach_athletes.ai_assist_consent_version is
  'The athlete''s acceptance of the coach-assistant copy for this link (issue '
  '#1215 Phase 4), at coach_assist_consent_current_version(); null is no '
  'consent. Written only by set_coach_ai_assist_consent; cleared when the '
  'link ends.';
comment on column coach_athletes.ai_assist_consent_at is
  'When the athlete gave the consent in ai_assist_consent_version.';

-- Re-emitted whole (bare-body rule): 20270416_001's expression plus the
-- consent columns, so a coach cannot mint an invite that arrives consented.
alter policy "coach creates own pending invite" on coach_athletes
  with check (
    coach_id = (select auth.uid())
    and athlete_id is null
    and status = 'pending'
    and ai_assist_consent_version is null
    and ai_assist_consent_at is null
  );

-- ─── the athlete-side copy's ladder ─────────────────────────────────────

create or replace function coach_assist_consent_current_version()
returns smallint
language sql
immutable
set search_path = public
as $$ select 1::smallint $$;

revoke all on function coach_assist_consent_current_version() from public, anon;
grant execute on function coach_assist_consent_current_version() to authenticated, service_role;

comment on function coach_assist_consent_current_version() is
  'Highest known coach-assistant consent version. The TS mirror is '
  'COACH_ASSIST_CONSENT_VERSION in apps/web/src/lib/coach/assist/consent.ts, '
  'whose test fails if the two drift.';

-- ─── set_coach_ai_assist_consent ────────────────────────────────────────

create or replace function set_coach_ai_assist_consent(p_link_id uuid, p_version smallint)
returns coach_athletes
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_row coach_athletes;
begin
  if v_me is null then
    raise exception 'set_coach_ai_assist_consent: not authorized' using errcode = '42501';
  end if;

  if p_version is not null
     and (p_version < 1 or p_version > coach_assist_consent_current_version()) then
    raise exception 'set_coach_ai_assist_consent: unknown consent version'
      using errcode = '22023';
  end if;

  update coach_athletes
     set ai_assist_consent_version = p_version,
         ai_assist_consent_at = case when p_version is null then null else now() end
   where id = p_link_id
     and athlete_id = v_me
     and status = 'active'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'set_coach_ai_assist_consent: link not found' using errcode = 'P0002';
  end if;

  v_row.invite_token := null;
  return v_row;
end;
$$;

revoke execute on function set_coach_ai_assist_consent(uuid, smallint) from public, anon;
grant execute on function set_coach_ai_assist_consent(uuid, smallint) to authenticated, service_role;

comment on function set_coach_ai_assist_consent(uuid, smallint) is
  'The athlete allows (a version) or withdraws (null) the coach assistant on '
  'one active coaching link (issue #1215 Phase 4). P0002 for a link that is '
  'not the caller''s as athlete or not active; 22023 for an unknown version. '
  'The returned row carries no invite_token.';

-- ─── end_coach_link: the consent goes with the link ─────────────────────
--
-- Bare-body re-emit of 20261102_001 with the consent cleared, so an ended
-- link keeps no record of a consent that no longer applies.

create or replace function end_coach_link(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n int;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  update coach_athletes
    set status = 'ended',
        ended_at = now(),
        ai_assist_consent_version = null,
        ai_assist_consent_at = null
    where id = p_id
      and status = 'active'
      and (coach_id = uid or athlete_id = uid);
  get diagnostics n = row_count;
  return n > 0;
end;
$$;

-- ─── the marker ─────────────────────────────────────────────────────────

alter table direct_messages drop constraint direct_messages_kind_check;
alter table direct_messages
  add constraint direct_messages_kind_check
    check (kind in ('text', 'coach_share', 'ai_assisted'))
    not valid;

comment on column direct_messages.kind is
  'What the message is (issue #1215): text; coach_share, an excerpt of the '
  'sender''s own AI Coach answer both sides render as an AI-labelled quote '
  '(written only by share_coach_message); or ai_assisted, a coach''s own '
  'message drafted with the coach assistant, marked as such on both sides.';

grant insert (kind) on direct_messages to authenticated;

-- Re-emitted whole (bare-body rule): 20271210001215's expression with the
-- kind clause widened to the coach's marker.
alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    sender_id = (select auth.uid())
    and not is_blocked_either_way(sender_id, recipient_id)
    and private.dm_send_admitted(recipient_id)
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
    and (
      direct_messages.kind = 'text'
      or (
        direct_messages.kind = 'ai_assisted'
        and private.is_active_coach_of((select auth.uid()), direct_messages.recipient_id)
      )
    )
    and direct_messages.coach_message_id is null
  );
