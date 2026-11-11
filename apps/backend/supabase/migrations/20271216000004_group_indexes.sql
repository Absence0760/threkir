-- Group conversations, slice 1 (issue #1365, decisions § 2461): the indexes,
-- alone in their file so each build runs under SHARE with no ACCESS
-- EXCLUSIVE held on its table (docs/backend/migration_locks.md § Index builds).
--
--   conversation_participants_active   the read branch and the member list:
--                                      the active members of a conversation.
--   conversation_participants_one_owner  a group has one active owner.
--   *_invited_by / *_removed_by / conversations_created_by
--                                      covering indexes for the three new FKs
--                                      to auth.users (fk_covering_index_test).

create index if not exists conversation_participants_active
  on conversation_participants (conversation_id, joined_at)
  where membership_state = 'active';

create unique index if not exists conversation_participants_one_owner
  on conversation_participants (conversation_id)
  where role = 'owner' and membership_state = 'active';

create index if not exists conversation_participants_invited_by
  on conversation_participants (invited_by) where invited_by is not null;

create index if not exists conversation_participants_removed_by
  on conversation_participants (removed_by) where removed_by is not null;

create index if not exists conversations_created_by
  on conversations (created_by) where created_by is not null;
