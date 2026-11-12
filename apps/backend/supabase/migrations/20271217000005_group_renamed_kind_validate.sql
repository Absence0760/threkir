-- Validates the direct_messages_kind_check 20271217000004 widened NOT VALID.
-- The list only widened, so every existing row passes.

alter table direct_messages validate constraint direct_messages_kind_check;
