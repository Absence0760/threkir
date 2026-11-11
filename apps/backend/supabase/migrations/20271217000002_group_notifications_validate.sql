-- Validates the notifications_kind_check and notifications_conversation_id_fkey
-- that 20271217000001 added NOT VALID, in their own file so the scan of a
-- high-volume table holds nothing on any other (docs/backend/migration_locks.md
-- § One table per migration). VALIDATE runs under SHARE UPDATE EXCLUSIVE, so
-- inserts proceed; the kind list only widened and the column is null on every
-- existing row, so both pass.

alter table notifications validate constraint notifications_kind_check;
alter table notifications validate constraint notifications_conversation_id_fkey;
