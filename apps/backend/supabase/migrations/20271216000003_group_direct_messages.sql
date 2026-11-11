-- Group conversations, slice 1 (issue #1365, decisions § 2461): a group
-- message is a direct_messages row with no recipient.
--
-- One message rail (group_messages.md § 1): a group message inherits unsend,
-- edit, the report snapshot, reactions, photos, search, both purges, the
-- sender's account-deletion cascade and both export rails.
--
--   is_group  set by the BEFORE INSERT trigger from the conversation's kind;
--             there is no client grant on it, so a client can neither claim a
--             group message nor disown one.
--
-- The deleted-partner CHECK is replaced by one that knows both audiences: a
-- group message has no recipient, no deleted-partner key and no per-message
-- read state; a direct message keeps the old rule (a null recipient iff its
-- partner's account is gone).
--
-- A group send names its conversation, so conversation_id gains an INSERT
-- grant. A direct send still has it overwritten from the pair by
-- direct_messages_set_conversation, so the grant changes nothing there.
--
-- Locking: is_group is NOT NULL with a constant default (fast path, no
-- rewrite). The new CHECK goes on NOT VALID and is validated by
-- 20271216000005; dropping the old one is catalogue-only. GRANT takes no lock
-- on the relation.

alter table direct_messages
  add column is_group boolean not null default false;

alter table direct_messages
  drop constraint direct_messages_deleted_partner_key_check;

alter table direct_messages
  add constraint direct_messages_audience_check check (
    (is_group and recipient_id is null and deleted_partner_key is null
       and read_at is null and seen_at is null)
    or (not is_group and (recipient_id is null) = (deleted_partner_key is not null))
  ) not valid;

grant insert (conversation_id) on direct_messages to authenticated;
grant select (is_group) on direct_messages to anon, authenticated;

comment on column direct_messages.is_group is
  'True for a message in a group conversation (no recipient). Set by direct_messages_set_conversation; no client grant.';
