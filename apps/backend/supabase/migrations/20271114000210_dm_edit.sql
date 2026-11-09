-- Direct messages: edit a sent message within 15 minutes, marked "edited"
-- (issue #1216, decisions § 2373).
--
-- ── What it is ───────────────────────────────────────────────────────────
--
-- The sender may rewrite the text of a message they sent for 15 minutes after
-- sending it. Both sides then see the new text and an "edited" mark. The route
-- attachment is not editable, and neither is an unsent message.
--
-- ── Why 15 minutes ───────────────────────────────────────────────────────
--
-- It is the window both iMessage (iOS 16) and WhatsApp (2023) settled on: long
-- enough to fix a typo or a wrong time noticed after sending, short enough
-- that a conversation is not rewritten under the reader after they have
-- replied to it. The server holds the only authoritative copy, as c_window in
-- edit_direct_message below; the clients' DM_EDIT_WINDOW_MS / kDmEditWindow
-- only decide whether to offer the action, and a unit test on each side reads
-- this file to keep them equal.
--
-- ── The write path ───────────────────────────────────────────────────────
--
-- Clients hold no UPDATE grant on direct_messages (20271113000001), and this
-- does not give them one: an edit is edit_direct_message(), SECURITY DEFINER,
-- which checks the caller is the sender, the message is live, inside the
-- window, not hidden from the caller, and that neither participant has
-- blocked the other. A message the caller did not send answers P0002 exactly
-- like one that does not exist (as unsend does), so the RPC cannot probe ids.
-- Every other refusal answers one 55000 "can no longer be edited", so an edit
-- refused by a block does not tell the sender they were blocked. A body the
-- same as the current one is a no-op and leaves edited_at alone. Edits share a
-- rate-limit bucket of their own (60 an hour), beside the send buckets.
--
-- ── What is kept for moderation ──────────────────────────────────────────
--
-- An edit could otherwise swap an abusive message for a harmless one before
-- the recipient reports it, and the report's snapshot would hold only the
-- harmless one. So the first edit copies the text as sent into original_body,
-- which no client may select (column grant; registered in
-- column_grant_lockdown_registry_test), and submit_report snapshots it into
-- reports.snapshot_original_body beside snapshot_body. Only the text as sent
-- and the latest text are kept, not every intermediate version. Unsend nulls
-- original_body with body, so unsending still erases the message's words from
-- the conversation; a report filed before the unsend keeps both snapshots.
-- The 2-year purge and account deletion delete the row, original_body with it.
--
-- ── Exports ──────────────────────────────────────────────────────────────
--
-- export-data's direct_messages_sent.json (and the Go worker's) gains
-- edited_at and original_body: both are the subject's own words and dates.
-- The received side is select *, so it carries them too: the recipient
-- received the original text. reports_against_my_messages.json gains
-- snapshot_original_body for the same reason it carries snapshot_body.
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- Every ADD COLUMN is nullable with no default: catalogue-only. The two CHECKs
-- are added NOT VALID here and validated in 20271114000211, a separate file,
-- so the validating scan holds only SHARE UPDATE EXCLUSIVE
-- (docs/backend/migration_locks.md). The rest is grants and functions.

alter table direct_messages
  add column edited_at timestamptz,
  add column original_body text;

comment on column direct_messages.edited_at is
  'When the sender last edited the message (edit_direct_message, within 15 '
  'minutes of created_at). Null on a message never edited. Clients show an '
  '"edited" mark while it is set.';

comment on column direct_messages.original_body is
  'The text as first sent, copied by the first edit_direct_message call. Not '
  'granted to clients: it exists so a report (reports.snapshot_original_body) '
  'still shows what was sent after an edit. Null when never edited, and nulled '
  'by unsend.';

alter table direct_messages
  add constraint direct_messages_original_body_check
  check (
    original_body is null
    or (unsent_at is null and edited_at is not null and char_length(original_body) <= 4000)
  ) not valid;

grant select (edited_at) on direct_messages to anon, authenticated;

alter table reports
  add column snapshot_original_body text;

comment on column reports.snapshot_original_body is
  'For target_kind = direct_message: the message as first sent, when it had '
  'been edited before the report (direct_messages.original_body). Null when '
  'the message was never edited. snapshot_body holds the text as reported.';

alter table reports
  add constraint reports_snapshot_original_body_check
  check (
    snapshot_original_body is null
    or (target_kind = 'direct_message' and char_length(snapshot_original_body) <= 4000)
  ) not valid;

-- ─── edit_direct_message ────────────────────────────────────────────────

create function edit_direct_message(p_message_id uuid, p_body text)
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

comment on function edit_direct_message(uuid, text) is
  'Replaces the text of the caller''s own live message within 15 minutes of '
  'sending and stamps edited_at; the first edit keeps the text as sent in '
  'original_body for reports. P0002 for a message the caller did not send; '
  '55000 when it is unsent, past the window or either side has blocked the '
  'other; 22023 for an empty or over-long body. Returns the row with read_at '
  'and original_body nulled.';

-- ─── unsend_direct_message: erase original_body too ─────────────────────
--
-- Body as 20271113000001, with original_body nulled by the update and on both
-- returns.

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

  -- Already unsent is not an error: a retried tap converges on the same row.
  select * into v_row
    from direct_messages
   where id = p_message_id
     and sender_id = v_me;

  if v_row.id is null then
    -- Someone else's message and no message at all answer the same, so the
    -- RPC cannot be used to probe for message ids.
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

-- ─── submit_report: snapshot the text as sent ───────────────────────────
--
-- Bare-body re-emit: the COMPLETE 20271021000003 body plus
-- snapshot_original_body on the INSERT.

create or replace function submit_report(
  p_target_kind text,
  p_target_id uuid,
  p_reason text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reporter uuid := auth.uid();
  v_target_exists boolean;
  v_report_id uuid;
  v_dm direct_messages;
begin
  if v_reporter is null then
    raise exception 'submit_report: not authorized' using errcode = '42501';
  end if;

  if p_target_kind not in ('user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message') then
    raise exception 'submit_report: invalid target_kind %', p_target_kind
      using errcode = '22023';
  end if;

  if p_reason not in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other') then
    raise exception 'submit_report: invalid reason %', p_reason
      using errcode = '22023';
  end if;

  -- Don't let a user report themselves — most likely a misclick, and
  -- the queue noise isn't worth carrying.
  if p_target_kind = 'user' and p_target_id = v_reporter then
    raise exception 'submit_report: cannot report yourself'
      using errcode = '22023';
  end if;

  -- Validate the target exists. The FROM clauses run as the function owner
  -- (postgres) so RLS doesn't block visibility.
  if p_target_kind = 'user' then
    select exists (select 1 from user_profiles where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'club' then
    select exists (select 1 from clubs where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'route' then
    select exists (select 1 from routes where id = p_target_id) into v_target_exists;
  elsif p_target_kind = 'comment' then
    select exists (select 1 from run_comments where id = p_target_id) into v_target_exists;
    -- Reporting your own comment is a misclick; reject like self-user.
    if v_target_exists and exists (
      select 1 from run_comments where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own comment'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'club_post' then
    select exists (select 1 from club_posts where id = p_target_id) into v_target_exists;
    -- Reporting your own post is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from club_posts where id = p_target_id and author_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own post'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'run' then
    select exists (select 1 from runs where id = p_target_id) into v_target_exists;
    -- Reporting your own run is a misclick; reject like self-comment.
    if v_target_exists and exists (
      select 1 from runs where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own run'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'route_review' then
    select exists (select 1 from route_reviews where id = p_target_id) into v_target_exists;
    -- Reporting your own review is a misclick; reject like self-comment.
    -- route_reviews' author column is `user_id` (no `author_id`).
    if v_target_exists and exists (
      select 1 from route_reviews where id = p_target_id and user_id = v_reporter
    ) then
      raise exception 'submit_report: cannot report your own review'
        using errcode = '22023';
    end if;
  elsif p_target_kind = 'direct_message' then
    -- Only a participant can have seen the message, and the reporter reads
    -- their own report back, snapshot included. So the gate is the
    -- participant check itself: a message the caller neither sent nor
    -- received answers "not found", exactly like one that does not exist.
    select * into v_dm
      from direct_messages
     where id = p_target_id
       and (sender_id = v_reporter or recipient_id = v_reporter);
    v_target_exists := v_dm.id is not null;
    if v_target_exists and v_dm.sender_id = v_reporter then
      raise exception 'submit_report: cannot report your own message'
        using errcode = '22023';
    end if;
    if v_target_exists and v_dm.unsent_at is not null then
      raise exception 'submit_report: message was unsent'
        using errcode = '22023';
    end if;
  end if;

  if not v_target_exists then
    raise exception 'submit_report: target % % not found', p_target_kind, p_target_id
      using errcode = '02000';
  end if;

  -- Rate-limit: 10 reports per hour per reporter.
  perform enforce_create_rate_limit('create_report', v_reporter, 10, 3600);

  begin
    insert into reports (
      reporter_id, target_kind, target_id, reason, notes,
      snapshot_body, snapshot_author_id, snapshot_sent_at, snapshot_original_body
    )
    values (
      v_reporter, p_target_kind, p_target_id, p_reason, p_notes,
      -- v_dm is only ever filled by the direct_message arm, so every other
      -- kind stores null snapshots.
      v_dm.body, v_dm.sender_id, v_dm.created_at, v_dm.original_body
    )
    returning id into v_report_id;
  exception when unique_violation then
    raise exception 'submit_report: already reported'
      using errcode = '23505',
            hint = 'You already have a pending report against this target.';
  end;

  return v_report_id;
end;
$$;

revoke execute on function submit_report(text, uuid, text, text) from public, anon;
grant execute on function submit_report(text, uuid, text, text) to authenticated;

-- ─── fetch_reports_for_target: the moderator sees the text as sent ──────
--
-- The return shape grows, so drop and re-create; body is 20271021000040's.

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
  snapshot_original_body text
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
           r.snapshot_original_body
    from reports r
    where r.target_kind = p_target_kind
      and r.target_id = p_target_id
    order by r.created_at desc;
end;
$$;

revoke execute on function fetch_reports_for_target(text, uuid) from public, anon;
grant execute on function fetch_reports_for_target(text, uuid) to authenticated, service_role;
