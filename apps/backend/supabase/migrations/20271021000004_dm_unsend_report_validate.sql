-- Validates the five constraints 20271021000003 added NOT VALID, in their own
-- transaction (docs/backend/migration_locks.md): each scan runs under SHARE
-- UPDATE EXCLUSIVE, so reads and writes on direct_messages and reports
-- proceed while it runs. Every pre-existing row already satisfies them — no
-- message was unsent or lost its recipient before 20271021000003, and no
-- report could name a direct_message — so nothing here can fail on data.

alter table direct_messages validate constraint direct_messages_body_check;
alter table direct_messages validate constraint direct_messages_deleted_partner_key_check;
alter table direct_messages validate constraint direct_messages_recipient_id_fkey;
alter table reports validate constraint reports_target_kind_check;
alter table reports validate constraint reports_direct_message_snapshot_check;
