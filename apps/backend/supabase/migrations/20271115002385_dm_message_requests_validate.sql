-- Validates the CHECK 20271115002384 added NOT VALID (issue #1216, decisions
-- § 2384). A separate file, so the scan runs in its own transaction holding
-- only SHARE UPDATE EXCLUSIVE, which lets reads and writes on
-- conversation_participants carry on (docs/backend/migration_locks.md).

alter table conversation_participants
  validate constraint conversation_participants_request_state_check;
