-- Validates the two CHECKs 20271210001215 added NOT VALID, in their own
-- transaction so the scan runs under SHARE UPDATE EXCLUSIVE alone
-- (docs/backend/migration_locks.md). Every existing row is kind 'text' with
-- no coach_message_id, so neither can fail.

alter table direct_messages validate constraint direct_messages_kind_check;
alter table direct_messages validate constraint direct_messages_coach_message_kind_check;
