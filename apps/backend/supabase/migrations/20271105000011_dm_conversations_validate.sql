-- Validates the two constraints 20271105000010 added NOT VALID, in their own
-- transaction (docs/backend/migration_locks.md): each scan runs under SHARE
-- UPDATE EXCLUSIVE, so reads and writes on direct_messages proceed while it
-- runs. 20271105000010 backfilled every existing message and its trigger
-- assigns every new one, so nothing here can fail on data.
--
-- SET NOT NULL then trusts the validated CHECK and skips its own scan (PG12+),
-- and the CHECK, now redundant, is dropped.

alter table direct_messages validate constraint direct_messages_conversation_id_fkey;
alter table direct_messages validate constraint direct_messages_conversation_id_not_null;

alter table direct_messages alter column conversation_id set not null;

alter table direct_messages drop constraint direct_messages_conversation_id_not_null;
