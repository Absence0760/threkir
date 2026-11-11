-- Group conversations, slice 1 (issue #1365, docs/features/group_messages.md,
-- decisions § 2458): conversations gains its second kind.
--
-- A group is a conversation of 3 to 32 people its members created. It has a
-- title (1 to 60 characters after trim, required for a group and absent for a
-- direct conversation) and the account that created it (set null when that
-- account is deleted; ownership itself lives on the participant row).
--
-- Club channels (kind 'club', club_id, posting_mode) are slice 5 and are not
-- added here: a column nothing writes is a vocabulary nobody enforces.
--
-- Locking: conversations is populated but not on the high-volume list. Both
-- columns are nullable with no default (catalogue-only). The kind CHECK swap,
-- the two new CHECKs and the FK go on NOT VALID and are validated by
-- 20271216000005 in its own transaction (docs/backend/migration_locks.md).

alter table conversations
  drop constraint conversations_kind_check;
alter table conversations
  add constraint conversations_kind_check
  check (kind in ('direct', 'group')) not valid;

alter table conversations
  add column title text,
  add column created_by uuid;

alter table conversations
  add constraint conversations_created_by_fkey
  foreign key (created_by) references auth.users (id) on delete set null
  not valid;

alter table conversations
  add constraint conversations_title_check
  check (title is null or char_length(btrim(title)) between 1 and 60) not valid;

alter table conversations
  add constraint conversations_group_title_check
  check ((kind = 'group') = (title is not null)) not valid;

comment on column conversations.title is
  'A group''s name, 1 to 60 characters after trim; null for a direct conversation. Written only by create_group_conversation / rename_group.';
comment on column conversations.created_by is
  'The account that created a group; null for a direct conversation and after that account is deleted. Not the owner: ownership is conversation_participants.role.';
