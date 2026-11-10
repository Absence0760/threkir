-- Direct messages: search the caller's own conversations (issue #1216).
--
-- ── The read ────────────────────────────────────────────────────────────
--
-- search_direct_messages(query, limit) is SECURITY INVOKER: it reads
-- direct_messages, conversation_participants and user_blocks under the
-- caller's own RLS and column grants, so it can return nothing a client could
-- not already select row by row. A definer search was rejected outright: it
-- would have to re-implement the participant and hidden_before rules, and one
-- missed clause would turn a search box into a read of anyone's messages.
--
-- On top of what the SELECT policy already hides (other people's messages,
-- and messages at or before the caller's hidden_before), it leaves out:
--
--   * unsent messages (no body to match, and the placeholder is not text);
--   * conversations where the caller has a pending or declined request:
--     search covers the inbox and its Archived list, not the Requests list
--     and not what the caller declined;
--   * conversations with someone the caller blocked. Only the caller's own
--     block is consulted (user_blocks is owner-read), so whether the other
--     person blocked the caller changes nothing and reveals nothing.
--
-- The query is trimmed, must be 2 to 100 characters, and is matched as a
-- literal substring (ILIKE with %, _ and \ escaped), newest first, at most 50
-- rows. read_at and original_body are not returned (and not granted).
--
-- ── The index ───────────────────────────────────────────────────────────
--
-- A trigram GIN index on live bodies makes the substring match indexable.
-- Built ONLINE, per docs/backend/migration_locks.md: CREATE INDEX
-- CONCURRENTLY cannot run in the wrapped apply transaction, so the build is a
-- pg_cron job whose whole command is that one statement (pg_cron runs it over
-- its own libpq connection, cron.use_background_workers = off, where a single
-- statement is not in a transaction block). Writers are not blocked while it
-- builds. The job is idempotent (IF NOT EXISTS) and, once the index exists,
-- costs a catalogue lookup every ten minutes. It stays scheduled so a
-- database rebuilt from migrations gets the index too. If a build fails it leaves an INVALID index that IF NOT EXISTS will not
-- rebuild: drop it by hand and the next run retries. Search is correct
-- without the index, only slower (the RLS participant filter still bounds
-- the scan to the caller's own messages through the sender / recipient
-- indexes).

create function search_direct_messages(p_query text, p_limit integer default 30)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  recipient_id uuid,
  deleted_partner_key uuid,
  body text,
  created_at timestamptz,
  kind text
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with q as (
    select btrim(coalesce(p_query, '')) as t
  )
  select m.id, m.conversation_id, m.sender_id, m.recipient_id,
         m.deleted_partner_key, m.body, m.created_at, m.kind
    from direct_messages m, q
   where char_length(q.t) between 2 and 100
     and m.unsent_at is null
     and m.body is not null
     and (m.sender_id = (select auth.uid()) or m.recipient_id = (select auth.uid()))
     and m.body ilike '%' || replace(replace(replace(q.t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
     and not exists (
       select 1 from conversation_participants p
        where p.conversation_id = m.conversation_id
          and p.user_id = (select auth.uid())
          and p.request_state in ('pending', 'declined')
     )
     and not exists (
       select 1 from user_blocks b
        where b.blocker_id = (select auth.uid())
          and b.blocked_id in (m.sender_id, m.recipient_id)
     )
   order by m.created_at desc, m.id desc
   limit least(greatest(coalesce(p_limit, 30), 1), 50);
$$;

revoke execute on function search_direct_messages(text, integer) from public, anon;
grant execute on function search_direct_messages(text, integer) to authenticated, service_role;

comment on function search_direct_messages(text, integer) is
  'Substring search over the caller''s own direct messages (issue #1216). '
  'SECURITY INVOKER: the direct_messages SELECT policy decides what is '
  'searchable. Leaves out unsent messages, Requests and declined '
  'conversations, and conversations with someone the caller blocked. 2-100 '
  'characters, newest first, at most 50.';

select cron.schedule(
  'build-direct-messages-body-trgm',
  '*/10 * * * *',
  $$create index concurrently if not exists direct_messages_body_trgm on public.direct_messages using gin (body extensions.gin_trgm_ops) where unsent_at is null$$
);
