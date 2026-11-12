-- Group conversations, slice 2 (issue #1365, decisions § 2463): the rename
-- system line.
--
-- direct_messages.kind 'group_renamed' is the line "X renamed the group to Y"
-- in a group's thread. Only rename_group writes it (20271217000006), as the
-- renamer's own row with the new title as its body; the INSERT policy admits
-- kind 'text' alone from a client, so nobody can forge one, and
-- edit_direct_message refuses it, so nobody can rewrite one into other words.
-- Being a message row, it is read through private.can_read_message (so a late
-- joiner does not see a rename from before they joined), exported as the
-- renamer's sent message, reportable, unsendable by its sender and erased by
-- both purges, with no rail of its own.
--
-- Locks: direct_messages is populated but not on the high-volume list; the
-- widened CHECK is added NOT VALID anyway and validated in 20271217000005.

alter table direct_messages drop constraint direct_messages_kind_check;
alter table direct_messages
  add constraint direct_messages_kind_check
    check (kind in ('text', 'coach_share', 'ai_assisted', 'group_renamed'))
    not valid;

comment on column direct_messages.kind is
  'What the message is (issue #1215): text; coach_share, an excerpt of the '
  'sender''s own AI Coach answer both sides render as an AI-labelled quote; '
  'ai_assisted, a coach''s message drafted with the coach assistant; '
  'group_renamed, the system line rename_group writes in a group (body = the new title).';
