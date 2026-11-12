-- Validates the two CHECKs 20271210001217 added NOT VALID, in their own
-- transaction (docs/backend/migration_locks.md). No existing row carries a
-- consent or the new kind, so neither can fail.

alter table coach_athletes validate constraint coach_athletes_ai_assist_consent_check;
alter table direct_messages validate constraint direct_messages_kind_check;
