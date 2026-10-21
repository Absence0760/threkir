-- Direct messages: unsend instead of a cross-user hard delete, keep the
-- remaining user's copy when the other side deletes their account, and let a
-- recipient report a message with a snapshot that unsend cannot destroy
-- (issue #1216, decisions § 2221).
--
-- ── 1. No client hard delete; a sender-only soft unsend ──────────────────
--
-- "participants delete their messages" (20261026_001, initplan-wrapped by
-- 20270416_001) let EITHER participant hard-delete EITHER side's message, and
-- the row is shared, so one delete erased it for both. A harasser could erase
-- what the recipient needed as evidence; a recipient could erase the sender's
-- own copy of what they wrote. No UI exposed it; any anon-key client could.
--
-- The policy is dropped and DELETE revoked outright, so no client path can
-- hard-delete a message. Unsend is `unsend_direct_message(id)`: SECURITY
-- DEFINER, sender only, and a soft delete — `body` and the route attachment
-- are nulled, `unsent_at` is stamped, and both sides render a "Message unsent"
-- placeholder. There is no time window, because a report (3, below) snapshots
-- the message, so unsending cannot destroy evidence that was reported first.
--
-- The UPDATE side had the same shape of hole. "recipient marks read" gated the
-- ROW on recipient_id, but the table-level UPDATE grant covered every column,
-- so the recipient could rewrite the sender's `body` — and, after this
-- migration, could have stamped `unsent_at` on the sender's message. UPDATE is
-- narrowed to `read_at`, the one column the policy exists for, and INSERT to
-- the five columns a send writes: a sender could otherwise insert a message
-- pre-read (`read_at`), backdated (`created_at`), pre-unsent or carrying a
-- deleted-partner key. With DELETE gone, every insertable-but-not-updatable
-- column is write-once by construction (column_grant_write_lockdown_registry_test).
--
-- ── 2. Account deletion keeps the remaining user's sent messages ─────────
--
-- Both FKs cascaded, so deleting one account deleted the OTHER person's sent
-- messages too. `sender_id` keeps ON DELETE CASCADE: the leaver's own words
-- are erased (Art 17(1)). `recipient_id` becomes ON DELETE SET NULL: the
-- messages the remaining user sent are their own correspondence and stay,
-- with the other side shown as "Deleted account". The 2-year purge
-- (20261119_001) still applies to them.
--
-- A null partner alone would merge every deleted partner's conversation into
-- one thread, so the set-null also stamps `deleted_partner_key`: a random uuid,
-- one per (remaining sender, deleted recipient), generated at deletion time.
-- It is NOT derived from the deleted user's id — the mapping lives only in a
-- transaction-local setting for the duration of the cascade — so the key keeps
-- the conversations apart without being a pseudonym for the leaver.
--
-- ── 3. Report a message ──────────────────────────────────────────────────
--
-- `direct_message` joins `reports.target_kind`. submit_report copies the
-- message's body, sender and sent time into the report at report time
-- (`snapshot_*`, no FK, so it outlives an unsend, the sender's account
-- deletion and the 2-year purge — kept under the report's own retention,
-- Art 17(3)(e)). Only the RECIPIENT may report a message: the reporter can
-- read their own report, so a sender-or-anyone gate would turn the RPC into a
-- way to read any message by id.
--
-- ── Locking ──────────────────────────────────────────────────────────────
--
-- Neither table is in check_migration_online_safety.mjs's GUARDED_TABLES; the
-- house pattern is followed anyway (docs/backend/migration_locks.md). Every
-- added constraint is NOT VALID here (a metadata flip under a brief ACCESS
-- EXCLUSIVE) and is validated by 20271021000004, in its own transaction, under
-- SHARE UPDATE EXCLUSIVE. The two DROP NOT NULLs and the ADD COLUMNs (nullable,
-- no default) are catalogue-only. No row is rewritten or backfilled: every
-- existing message already satisfies the new checks (recipient not null, key
-- null, not unsent, body present).

-- ─── direct_messages: columns ───────────────────────────────────────────

alter table direct_messages
  add column unsent_at timestamptz,
  add column deleted_partner_key uuid;

alter table direct_messages
  alter column body drop not null,
  alter column recipient_id drop not null;

-- An unsent message carries nothing: no body, no attachment. A live one keeps
-- 20261026_001's 1..4000 rule.
alter table direct_messages
  drop constraint direct_messages_body_check;

alter table direct_messages
  add constraint direct_messages_body_check
  check (
    (unsent_at is null and body is not null and length(btrim(body)) between 1 and 4000)
    or (unsent_at is not null and body is null and route_id is null)
  ) not valid;

-- The key exists exactly when the recipient has been deleted.
alter table direct_messages
  add constraint direct_messages_deleted_partner_key_check
  check ((recipient_id is null) = (deleted_partner_key is not null)) not valid;

alter table direct_messages
  drop constraint direct_messages_recipient_id_fkey,
  add constraint direct_messages_recipient_id_fkey
    foreign key (recipient_id) references auth.users (id) on delete set null
    not valid;

-- The deleted-partner thread read: my messages to one deleted partner.
create index direct_messages_deleted_partner
  on direct_messages (sender_id, deleted_partner_key, created_at desc)
  where deleted_partner_key is not null;

comment on column direct_messages.unsent_at is
  'When the sender unsent the message (unsend_direct_message). body and '
  'route_id are null from then on; both sides render a placeholder. A report '
  'filed before the unsend keeps its own snapshot (reports.snapshot_*).';

comment on column direct_messages.deleted_partner_key is
  'Set when the recipient deletes their account (recipient_id ON DELETE SET '
  'NULL): a random uuid per (sender, deleted recipient) so each deleted '
  'partner''s conversation stays its own thread. Not derived from the deleted '
  'user''s id. Null while the recipient exists.';

-- ─── direct_messages: deleted-partner key on the set-null ──────────────
--
-- The FK action is one UPDATE over every row that named the deleted user, so a
-- per-row trigger sees each row separately and cannot read the rows already
-- updated in the same statement. The key is remembered per (sender, deleted
-- recipient) in a transaction-local custom setting instead: random on first
-- use, gone at commit. The setting's NAME hashes the pair only so it is a
-- valid identifier; it is never stored.

create or replace function direct_messages_key_deleted_partner()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_setting text := 'threkir_dm.k' || md5(new.sender_id::text || old.recipient_id::text);
  v_key text := nullif(current_setting(v_setting, true), '');
begin
  if v_key is null then
    v_key := gen_random_uuid()::text;
    perform set_config(v_setting, v_key, true);
  end if;
  new.deleted_partner_key := v_key::uuid;
  return new;
end;
$$;

revoke execute on function direct_messages_key_deleted_partner() from public, anon, authenticated;

create trigger direct_messages_key_deleted_partner
  before update of recipient_id on direct_messages
  for each row
  when (old.recipient_id is not null and new.recipient_id is null)
  execute function direct_messages_key_deleted_partner();

-- ─── direct_messages: no client hard delete, column-scoped writes ──────

drop policy "participants delete their messages" on direct_messages;

revoke delete on direct_messages from anon, authenticated;
revoke insert, update on direct_messages from anon, authenticated;
grant insert (id, sender_id, recipient_id, body, route_id) on direct_messages to authenticated;
grant update (read_at) on direct_messages to authenticated;

-- ─── unsend_direct_message ──────────────────────────────────────────────

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
         route_id = null,
         unsent_at = now()
   where id = p_message_id
     and sender_id = v_me
     and unsent_at is null
  returning * into v_row;

  if v_row.id is not null then
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

  return v_row;
end;
$$;

revoke execute on function unsend_direct_message(uuid) from public, anon;
grant execute on function unsend_direct_message(uuid) to authenticated, service_role;

comment on function unsend_direct_message(uuid) is
  'Sender-only soft unsend (issue #1216): nulls body + route_id and stamps '
  'unsent_at. The only client path that removes a message''s content; there '
  'is no client DELETE on direct_messages. Idempotent for an already-unsent '
  'message; P0002 for an id the caller did not send.';

-- ─── dm_threads: deleted partners + unsent previews ─────────────────────
--
-- The return shape changes, so the function is dropped and re-created rather
-- than replaced. A conversation is keyed on the partner, or — when the partner
-- deleted their account — on deleted_partner_key, which only the remaining
-- sender's own messages carry (the leaver's were cascaded away). An unsent
-- message no longer counts as unread: the recipient cannot read it.

drop function dm_threads();

create function dm_threads()
returns table (
  partner_id uuid,
  deleted_partner_key uuid,
  last_body text,
  last_unsent boolean,
  last_at timestamptz,
  last_from_me boolean,
  unread bigint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with my_msgs as (
    select
      case when sender_id = (select auth.uid()) then recipient_id else sender_id end as partner_id,
      deleted_partner_key,
      coalesce(
        case when sender_id = (select auth.uid()) then recipient_id else sender_id end,
        deleted_partner_key
      ) as thread_key,
      sender_id,
      recipient_id,
      body,
      unsent_at,
      created_at,
      read_at
    from direct_messages
    where sender_id = (select auth.uid()) or recipient_id = (select auth.uid())
  ),
  latest as (
    select distinct on (thread_key)
      thread_key,
      partner_id,
      deleted_partner_key,
      body as last_body,
      (unsent_at is not null) as last_unsent,
      created_at as last_at,
      (sender_id = (select auth.uid())) as last_from_me
    from my_msgs
    order by thread_key, created_at desc
  ),
  unread as (
    select thread_key, count(*) as cnt
    from my_msgs
    where recipient_id = (select auth.uid()) and read_at is null and unsent_at is null
    group by thread_key
  )
  select
    l.partner_id,
    l.deleted_partner_key,
    l.last_body,
    l.last_unsent,
    l.last_at,
    l.last_from_me,
    coalesce(u.cnt, 0) as unread
  from latest l
  left join unread u using (thread_key)
  order by l.last_at desc;
$$;

revoke execute on function dm_threads() from public, anon;
grant execute on function dm_threads() to authenticated, service_role;

-- ─── reports: direct_message target + snapshot ──────────────────────────

alter table reports
  add column snapshot_body text,
  add column snapshot_author_id uuid,
  add column snapshot_sent_at timestamptz;

comment on column reports.snapshot_body is
  'For target_kind = direct_message: the message body as it read when '
  'reported. Copied by submit_report so an unsend, the sender''s account '
  'deletion or the 2-year DM purge cannot destroy reported evidence. '
  'Readable by the reporter (their own report) and moderators.';
comment on column reports.snapshot_author_id is
  'For target_kind = direct_message: the sender at report time. Deliberately '
  'no FK, so the evidence survives the sender''s account deletion.';
comment on column reports.snapshot_sent_at is
  'For target_kind = direct_message: when the reported message was sent.';

alter table reports drop constraint reports_target_kind_check;
alter table reports
  add constraint reports_target_kind_check
  check (target_kind in ('user', 'club', 'route', 'comment', 'club_post', 'run', 'route_review', 'direct_message'))
  not valid;

alter table reports
  add constraint reports_direct_message_snapshot_check
  check (
    target_kind <> 'direct_message'
    or (
      snapshot_body is not null
      and char_length(snapshot_body) <= 4000
      and snapshot_author_id is not null
      and snapshot_sent_at is not null
    )
  ) not valid;

-- Bare-body re-emit: the COMPLETE 20270402_001 body plus the direct_message
-- arm and the snapshot columns on the INSERT.
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
      snapshot_body, snapshot_author_id, snapshot_sent_at
    )
    values (
      v_reporter, p_target_kind, p_target_id, p_reason, p_notes,
      -- v_dm is only ever filled by the direct_message arm, so every other
      -- kind stores null snapshots.
      v_dm.body, v_dm.sender_id, v_dm.created_at
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

-- ─── fetch_reports_for_target: the snapshot reaches the moderator ──────
--
-- A reported message has no other surface a moderator can open — the thread
-- is the two participants' alone — so the snapshot rides on each report. The
-- return shape changes, so drop and re-create; the body is 20270105_001's,
-- with 20270722000001's STABLE.

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
  snapshot_sent_at timestamptz
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
           r.snapshot_body, r.snapshot_author_id, r.snapshot_sent_at
    from reports r
    where r.target_kind = p_target_kind
      and r.target_id = p_target_id
    order by r.created_at desc;
end;
$$;

revoke execute on function fetch_reports_for_target(text, uuid) from public, anon;
grant execute on function fetch_reports_for_target(text, uuid) to authenticated, service_role;
