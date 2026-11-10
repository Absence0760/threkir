-- An athlete shares an AI Coach answer with their coach (issue #1215 Phase 3).
--
-- The athlete picks paragraphs of one of their own AI Coach answers and sends
-- them into the athlete<->coach direct-message thread, where both sides see a
-- quoted card labelled as AI output. Nothing new goes to Anthropic: the text
-- is an answer the athlete already holds, copied between two tables here.
--
-- ── Storage ─────────────────────────────────────────────────────────────
--
-- A typed message on the rail that already carries the conversation, not a
-- new table. The card has to sit in the thread's order, be unsent, reported,
-- purged after two years, exported both ways and erased with an account,
-- and direct_messages already does all of that for its body. Two columns:
--
--   kind              'text' for every message so far; 'coach_share' for the
--                     card. Clients render on it, so it is CHECKed and
--                     registered with check_constraint_unions.mjs.
--   coach_message_id  the coach_messages row the excerpt was copied from.
--                     Only the athlete can read that row (owner-only RLS), so
--                     the id is a link back for the sender and an opaque
--                     value for the coach. ON DELETE SET NULL: the Coach
--                     retention purge or an archive clean-up must not delete
--                     a message the coach has already received.
--
-- ── Who writes it ───────────────────────────────────────────────────────
--
-- Only share_coach_message. The INSERT policy now admits kind 'text' with no
-- coach_message_id and nothing else, so a client cannot write a card whose
-- "AI" label it chose itself: the RPC copies the text out of the caller's own
-- assistant row, by paragraph index, so what is labelled AI is AI text, and
-- edit_direct_message refuses a card for the same reason (decisions § 110:
-- AI text that crosses users is rendered as text, never as HTML, and here it
-- is also never text the sender typed under an AI label).
--
-- The recipient has to be the caller's active coach, and an active coaching
-- link now admits direct messages between the pair as a follow edge does
-- (private.dm_follow_edge below), so the card is an ordinary message in an
-- ordinary conversation: notified, and answerable. A block either way and a
-- declined request still refuse it, and every trigger an ordinary send fires
-- (conversation, rate limit, request state, notification) fires for it.
--
-- ── Gate ────────────────────────────────────────────────────────────────
--
-- private.coach_share_enabled() reads a row of private.feature_flags that NO
-- MIGRATION WRITES, so prod refuses the RPC until the CISO / Security Analyst
-- has confirmed the AI labelling (issue #1215; docs/ops/deployment.md).
-- seed.sql opens it for local and CI. public.coach_share_enabled() is how
-- both clients decide whether to offer "Share with coach".
--
-- ── Locks ───────────────────────────────────────────────────────────────
--
-- ADD COLUMN with a constant default is catalogue-only. Both CHECKs go on NOT
-- VALID and are validated by 20271210001216 in its own transaction. The FK
-- column is new, so every row is NULL and its VALIDATE here has nothing to
-- scan (the 20270619_001 precedent). direct_messages is not one of
-- check_migration_online_safety.mjs's GUARDED_TABLES; the two-step is taken
-- anyway as the house pattern.

alter table direct_messages
  add column kind text not null default 'text',
  add column coach_message_id uuid;

alter table direct_messages
  add constraint direct_messages_kind_check
    check (kind in ('text', 'coach_share'))
    not valid;

alter table direct_messages
  add constraint direct_messages_coach_message_kind_check
    check (coach_message_id is null or kind = 'coach_share')
    not valid;

alter table direct_messages
  add constraint direct_messages_coach_message_id_fkey
    foreign key (coach_message_id) references coach_messages (id) on delete set null
    not valid;

alter table direct_messages
  validate constraint direct_messages_coach_message_id_fkey;

create index direct_messages_coach_message_id
  on direct_messages (coach_message_id) where coach_message_id is not null;

comment on column direct_messages.kind is
  'What the message is (issue #1215): text, or coach_share, an excerpt of the '
  'sender''s own AI Coach answer that both sides render as an AI-labelled '
  'quote. Only share_coach_message writes coach_share.';
comment on column direct_messages.coach_message_id is
  'The sender''s coach_messages row a coach_share excerpt was copied from. '
  'Readable as a row by the sender only; ON DELETE SET NULL.';

grant select (kind, coach_message_id) on direct_messages to anon, authenticated;

-- Re-emitted whole (bare-body rule): 20271115002384's expression plus the
-- kind clause.
alter policy "send when not blocked and within follow graph" on direct_messages
  with check (
    sender_id = (select auth.uid())
    and not is_blocked_either_way(sender_id, recipient_id)
    and private.dm_send_admitted(recipient_id)
    and (
      direct_messages.route_id is null
      or private.is_route_visible_to(direct_messages.route_id, (select auth.uid()))
    )
    and direct_messages.kind = 'text'
    and direct_messages.coach_message_id is null
  );

-- ─── an active coaching link is a direct-message edge ───────────────────
--
-- Bare-body re-emit of 20271115002384's private.dm_follow_edge, which the
-- INSERT policy (through dm_send_admitted) and the request-state trigger read
-- as "this pair may write to each other without a request". An active
-- coaching link now counts too: the coach minted the invite and the athlete
-- redeemed it, and a plan-change card (§ 2382) and a shared answer both sit in
-- that pair's thread. Without it a shared answer would land in the coach's
-- Requests with no notification, and the coach could not reply to it. Ending
-- the link (or a block, which the policy checks first) removes the edge on
-- the next send; a conversation the link opened stays readable.

create or replace function private.dm_follow_edge(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from user_follows f
     where (f.follower_id = p_a and f.followee_id = p_b)
        or (f.follower_id = p_b and f.followee_id = p_a)
  )
  or private.is_active_coach_of(p_a, p_b)
  or private.is_active_coach_of(p_b, p_a);
$$;

revoke execute on function private.dm_follow_edge(uuid, uuid) from public, anon, authenticated;

-- ─── the gate ───────────────────────────────────────────────────────────

create or replace function private.coach_share_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'coach_share'),
    false
  );
$$;

revoke execute on function private.coach_share_enabled() from public, anon;
grant execute on function private.coach_share_enabled() to authenticated, service_role;

create or replace function public.coach_share_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.coach_share_enabled();
$$;

revoke execute on function public.coach_share_enabled() from public, anon;
grant execute on function public.coach_share_enabled() to authenticated, service_role;

comment on function public.coach_share_enabled() is
  'Whether an athlete may share an AI Coach answer with their coach (issue '
  '#1215 Phase 3). Clients hide "Share with coach" when false.';

-- ─── the paragraphs of an answer ────────────────────────────────────────
--
-- An answer split on blank lines, each paragraph trimmed, empty ones dropped.
-- The clients split the same way to offer the paragraphs (coach_share.ts,
-- coach_share.dart; coach_share_test.sql pins the shared fixtures), and the
-- server is authoritative: the card holds what this returns.

create or replace function private.coach_answer_paragraphs(p_content text)
returns text[]
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(
    array_agg(btrim(t.p, E' \t\n\r') order by t.ord)
      filter (where btrim(t.p, E' \t\n\r') <> ''),
    '{}'::text[]
  )
  from regexp_split_to_table(replace(coalesce(p_content, ''), E'\r\n', E'\n'), E'\n[ \t]*\n')
    with ordinality as t(p, ord);
$$;

revoke execute on function private.coach_answer_paragraphs(text) from public, anon, authenticated;

-- ─── share_coach_message ────────────────────────────────────────────────

create or replace function share_coach_message(
  p_coach_message_id uuid,
  p_coach_id uuid,
  p_paragraphs integer[]
)
returns direct_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_content text;
  v_paragraphs text[];
  v_picked integer[];
  v_body text;
  v_state text;
  v_row direct_messages;
begin
  if v_me is null then
    raise exception 'share_coach_message: not authorized' using errcode = '42501';
  end if;

  if not private.coach_share_enabled() then
    raise exception 'share_coach_message: sharing with a coach is not available'
      using errcode = '0A000';
  end if;

  select c.content into v_content
    from coach_messages c
   where c.id = p_coach_message_id
     and c.user_id = v_me
     and c.role = 'assistant';

  if v_content is null then
    raise exception 'share_coach_message: answer not found' using errcode = 'P0002';
  end if;

  -- The coach, the block and a declined request all answer the same 42501,
  -- so the call cannot be used to learn which of them refused it.
  v_state := private.dm_recipient_request_state(v_me, p_coach_id);
  if p_coach_id is null
     or not private.is_active_coach_of(p_coach_id, v_me)
     or is_blocked_either_way(v_me, p_coach_id)
     or v_state = 'declined' then
    raise exception 'share_coach_message: not your coach' using errcode = '42501';
  end if;

  v_paragraphs := private.coach_answer_paragraphs(v_content);

  select array_agg(distinct i order by i) into v_picked
    from unnest(coalesce(p_paragraphs, '{}'::integer[])) as i;

  if v_picked is null
     or v_picked[1] < 0
     or v_picked[array_length(v_picked, 1)] >= coalesce(array_length(v_paragraphs, 1), 0) then
    raise exception 'share_coach_message: pick at least one paragraph of the answer'
      using errcode = '22023';
  end if;

  select string_agg(v_paragraphs[i + 1], E'\n\n' order by i) into v_body
    from unnest(v_picked) as i;

  if char_length(v_body) > 4000 then
    raise exception 'share_coach_message: the excerpt is longer than 4000 characters'
      using errcode = '22001';
  end if;

  insert into direct_messages (sender_id, recipient_id, body, kind, coach_message_id)
  values (v_me, p_coach_id, v_body, 'coach_share', p_coach_message_id)
  returning * into v_row;

  v_row.read_at := null;
  v_row.original_body := null;
  return v_row;
end;
$$;

revoke execute on function share_coach_message(uuid, uuid, integer[]) from public, anon;
grant execute on function share_coach_message(uuid, uuid, integer[]) to authenticated, service_role;

comment on function share_coach_message(uuid, uuid, integer[]) is
  'Sends paragraphs (0-based indexes) of the caller''s own AI Coach answer to '
  'their active coach as a coach_share direct message (issue #1215 Phase 3). '
  '0A000 while the coach_share gate is closed; P0002 when the answer is not '
  'the caller''s; 42501 when the recipient is not their active coach, either '
  'side blocked or the coach declined; 22023 for no valid paragraph; 22001 '
  'past 4000 characters.';

-- ─── dm_threads: what the newest message is ─────────────────────────────
--
-- Bare-body re-emit of 20271115002384's dm_threads with last_kind appended,
-- so an inbox whose newest message is a shared Coach answer labels its
-- preview as AI as the thread does (Art. 50). A new OUT column changes the
-- return type, hence the drop.

drop function dm_threads();

create function dm_threads()
returns table (
  conversation_id uuid,
  partner_id uuid,
  deleted_partner_key uuid,
  last_body text,
  last_unsent boolean,
  last_at timestamptz,
  last_from_me boolean,
  unread bigint,
  muted boolean,
  archived boolean,
  marked_unread boolean,
  request boolean,
  last_kind text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with my_msgs as (
    select
      m.conversation_id,
      case when m.sender_id = (select auth.uid()) then m.recipient_id else m.sender_id end as partner_id,
      m.deleted_partner_key,
      m.sender_id,
      m.recipient_id,
      m.body,
      m.unsent_at,
      m.created_at,
      m.read_at,
      m.id,
      m.kind
    from direct_messages m
    where (m.sender_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
      and not exists (
        select 1 from conversation_participants hp
         where hp.conversation_id = m.conversation_id
           and hp.user_id = (select auth.uid())
           and hp.hidden_before is not null
           and m.created_at <= hp.hidden_before
      )
  ),
  latest as (
    select distinct on (conversation_id)
      conversation_id,
      partner_id,
      deleted_partner_key,
      body as last_body,
      (unsent_at is not null) as last_unsent,
      created_at as last_at,
      (sender_id = (select auth.uid())) as last_from_me,
      kind as last_kind
    from my_msgs
    order by conversation_id, created_at desc, id desc
  ),
  unread as (
    select conversation_id, count(*) as cnt
    from my_msgs
    where recipient_id = (select auth.uid()) and read_at is null and unsent_at is null
    group by conversation_id
  )
  select
    l.conversation_id,
    l.partner_id,
    l.deleted_partner_key,
    l.last_body,
    l.last_unsent,
    l.last_at,
    l.last_from_me,
    greatest(coalesce(u.cnt, 0), case when p.marked_unread_at is not null then 1 else 0 end) as unread,
    coalesce(p.muted_at is not null, false) as muted,
    coalesce(p.archived_at is not null and p.archived_at >= l.last_at, false) as archived,
    coalesce(p.marked_unread_at is not null, false) as marked_unread,
    coalesce(p.request_state = 'pending', false) as request,
    l.last_kind
  from latest l
  left join unread u using (conversation_id)
  left join conversation_participants p
    on p.conversation_id = l.conversation_id
   and p.user_id = (select auth.uid())
  where p.request_state is distinct from 'declined'
  order by l.last_at desc;
$$;

revoke execute on function dm_threads() from public, anon;
grant execute on function dm_threads() to authenticated, service_role;

-- ─── edit_direct_message: a card cannot be edited ───────────────────────
--
-- Bare-body re-emit of 20271114000210 with coach_share refused by the same
-- 55000 a closed window answers.

create or replace function edit_direct_message(p_message_id uuid, p_body text)
returns direct_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_window constant interval := interval '15 minutes';
  v_me uuid := auth.uid();
  v_body text := btrim(coalesce(p_body, ''));
  v_row direct_messages;
begin
  if v_me is null then
    raise exception 'edit_direct_message: not authorized' using errcode = '42501';
  end if;

  if char_length(v_body) not between 1 and 4000 then
    raise exception 'edit_direct_message: body must be 1 to 4000 characters'
      using errcode = '22023';
  end if;

  select * into v_row
    from direct_messages m
   where m.id = p_message_id
     and m.sender_id = v_me
     and not exists (
       select 1 from conversation_participants p
        where p.conversation_id = m.conversation_id
          and p.user_id = v_me
          and p.hidden_before is not null
          and m.created_at <= p.hidden_before
     )
   for update;

  if v_row.id is null then
    raise exception 'edit_direct_message: message not found' using errcode = 'P0002';
  end if;

  if v_row.unsent_at is not null
     or v_row.kind = 'coach_share'
     or v_row.created_at < now() - c_window
     or (v_row.recipient_id is not null and is_blocked_either_way(v_me, v_row.recipient_id)) then
    raise exception 'edit_direct_message: message can no longer be edited'
      using errcode = '55000';
  end if;

  if v_row.body is distinct from v_body then
    perform enforce_create_rate_limit('edit_direct_message', v_me, 60, 3600);

    update direct_messages
       set original_body = coalesce(original_body, body),
           body = v_body,
           edited_at = now()
     where id = v_row.id
    returning * into v_row;
  end if;

  v_row.read_at := null;
  v_row.original_body := null;
  return v_row;
end;
$$;

revoke execute on function edit_direct_message(uuid, text) from public, anon;
grant execute on function edit_direct_message(uuid, text) to authenticated, service_role;

-- ─── unsend_direct_message: drop the link back too ──────────────────────
--
-- Body as 20271114000210, with coach_message_id nulled beside route_id: an
-- unsent card keeps no pointer to the answer it quoted.

create or replace function unsend_direct_message(p_message_id uuid)
returns direct_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := auth.uid();
  v_row direct_messages;
begin
  if v_me is null then
    raise exception 'unsend_direct_message: not authorized' using errcode = '42501';
  end if;

  update direct_messages
     set body = null,
         original_body = null,
         route_id = null,
         coach_message_id = null,
         unsent_at = now()
   where id = p_message_id
     and sender_id = v_me
     and unsent_at is null
  returning * into v_row;

  if v_row.id is not null then
    v_row.read_at := null;
    v_row.original_body := null;
    return v_row;
  end if;

  select * into v_row
    from direct_messages
   where id = p_message_id
     and sender_id = v_me;

  if v_row.id is null then
    raise exception 'unsend_direct_message: message not found'
      using errcode = 'P0002';
  end if;

  v_row.read_at := null;
  v_row.original_body := null;
  return v_row;
end;
$$;

revoke execute on function unsend_direct_message(uuid) from public, anon;
grant execute on function unsend_direct_message(uuid) to authenticated, service_role;
