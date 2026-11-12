-- Group conversations, slice 1 (issue #1365, decisions § 2461, security memo
-- C1/C5): who reads a conversations row.
--
-- "participants read their conversations" admitted any participant row. For a
-- group that now includes left rows (leavers, removed members, decliners), so
-- a removed member could keep reading the group's title, renames included,
-- straight from the table. A group row is now readable by an active member
-- and by someone holding a live invite (the invite list's title); a leaver's
-- inbox row gets its title from dm_threads(), a definer. Direct conversations
-- are unchanged.
--
-- Locking: one ALTER POLICY on conversations (catalogue-only ACCESS
-- EXCLUSIVE, released at commit).

alter policy "participants read their conversations" on conversations
  using (
    exists (
      select 1 from conversation_participants p
       where p.conversation_id = conversations.id
         and p.user_id = (select auth.uid())
         and (
           conversations.kind = 'direct'
           or p.membership_state = 'active'
           or (p.membership_state = 'invited' and p.invited_at > now() - interval '14 days')
         )
    )
  );
