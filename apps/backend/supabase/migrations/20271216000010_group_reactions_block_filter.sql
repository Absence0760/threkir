-- Group conversations, slice 1 (issue #1365, decisions § 2461): a block
-- filters reactions as it filters messages.
--
-- In a group the person someone blocked still reads and reacts to the
-- blocker's messages: refusing the reaction would tell them about the block
-- (group_messages.md § 3). So the blocker no longer SEES a reaction from
-- someone they blocked, on any message, as they no longer see that person's
-- group messages. Only the caller's own block is read. In a 1:1 conversation
-- set_direct_message_reaction already refuses a reaction across a block, so
-- nothing changes there.
--
-- Locking: one ALTER POLICY on direct_message_reactions (catalogue-only).

alter policy "participants read reactions on messages they can read" on direct_message_reactions
  using (
    exists (
      select 1 from direct_messages m
       where m.id = direct_message_reactions.message_id
         and m.unsent_at is null
    )
    and not exists (
      select 1 from user_blocks b
       where b.blocker_id = (select auth.uid())
         and b.blocked_id = direct_message_reactions.user_id
    )
  );
