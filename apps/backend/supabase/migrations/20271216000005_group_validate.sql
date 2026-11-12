-- Validates the CHECKs and FKs 20271216000001 to 20271216000003 added NOT
-- VALID (issue #1365, decisions § 2461). Its own file, so each scan holds only
-- SHARE UPDATE EXCLUSIVE and reads and writes carry on
-- (docs/backend/migration_locks.md).

alter table conversations validate constraint conversations_kind_check;
alter table conversations validate constraint conversations_created_by_fkey;
alter table conversations validate constraint conversations_title_check;
alter table conversations validate constraint conversations_group_title_check;

alter table conversation_participants validate constraint conversation_participants_membership_state_check;
alter table conversation_participants validate constraint conversation_participants_left_at_check;
alter table conversation_participants validate constraint conversation_participants_invited_at_check;
alter table conversation_participants validate constraint conversation_participants_role_check;
alter table conversation_participants validate constraint conversation_participants_invited_by_fkey;
alter table conversation_participants validate constraint conversation_participants_removed_by_fkey;

alter table direct_messages validate constraint direct_messages_audience_check;
