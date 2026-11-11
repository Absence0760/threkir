-- Group conversations, slice 1 (issue #1365, decisions § 2461): the
-- participant row gains a lifecycle and the group state.
--
--   membership_state  'invited' (an invite the person has not answered),
--                     'active' (a member) or 'left' (left, was removed, or
--                     declined an invite). Direct conversations stay 'active'.
--   role              'owner' (one per group), 'admin' or 'member'; null for a
--                     direct conversation.
--   invited_by        who sent the current invite; set null with their account.
--   invited_at        when the current invite was sent. An invite expires 14
--                     days after it (group_messages.md § 2).
--   left_at           when the person left or was removed.
--   removed_by        who removed them; null when they left on their own.
--   last_read_at      a group's read position (groups have no per-message
--                     read_at: there is no single recipient).
--
-- joined_at already exists. For a group member it is stamped from the server
-- clock by accept_group_invite and is the start of their readable window, so
-- a client cannot backdate it (no client write grant on this table).
--
-- Locking: membership_state is NOT NULL with a constant default, the PG11+
-- fast path (no rewrite); the rest are nullable with no default. Every CHECK
-- and FK goes on NOT VALID and is validated by 20271216000005.

alter table conversation_participants
  add column membership_state text not null default 'active',
  add column role text,
  add column invited_by uuid,
  add column invited_at timestamptz,
  add column left_at timestamptz,
  add column removed_by uuid,
  add column last_read_at timestamptz;

alter table conversation_participants
  add constraint conversation_participants_membership_state_check
  check (membership_state in ('invited', 'active', 'left')) not valid;

alter table conversation_participants
  add constraint conversation_participants_left_at_check
  check ((membership_state = 'left') = (left_at is not null)) not valid;

alter table conversation_participants
  add constraint conversation_participants_invited_at_check
  check (membership_state <> 'invited' or invited_at is not null) not valid;

alter table conversation_participants
  add constraint conversation_participants_role_check
  check (role in ('owner', 'admin', 'member')) not valid;

alter table conversation_participants
  add constraint conversation_participants_invited_by_fkey
  foreign key (invited_by) references auth.users (id) on delete set null
  not valid;

alter table conversation_participants
  add constraint conversation_participants_removed_by_fkey
  foreign key (removed_by) references auth.users (id) on delete set null
  not valid;

comment on column conversation_participants.membership_state is
  '''invited'', ''active'' or ''left''. Only an active participant reads other people''s messages in a group, and only from joined_at on (group_messages.md § 3).';
comment on column conversation_participants.role is
  'A group member''s role: ''owner'', ''admin'' or ''member''; null for a direct conversation.';
comment on column conversation_participants.last_read_at is
  'A group''s read position, written by mark_conversation_read. Direct conversations keep direct_messages.read_at.';
