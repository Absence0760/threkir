# Group conversations, club channels and Realtime delivery (spec)

**Status: slices 1 (the backend), 2 (web) and 3 (mobile) built, slices 4–5 not (issue #1365, split from #1216; [decisions § 2461](../architecture/decisions.md), [§ 2463](../architecture/decisions.md), [§ 2468](../architecture/decisions.md)).** The owner signed off the security review and accepted D1–D12 as recommended on 2026-11-10 (#1097). Migrations `20271216000001`–`…10` hold the schema, the read rule `private.can_read_message`, the send gate, the group RPCs, the group rows of `dm_threads()`, the purge and deletion extensions and both export rails; `20271217000001`–`…06` (slice 2) add the group message and `group_invite` notifications (`notifications.conversation_id`), the `group_renamed` system line, `group_blocked_placeholders` for the blocker's "Message from someone you blocked" lines, `admin_report_conversation` for the reports queue, and a flag gate on `dm_threads()` / `group_invites()`; all of it sits behind the default-off `group_messages` flag (pre-deploy items in [deployment.md](../ops/deployment.md)). [api_database.md](../backend/api_database.md) is the reference for what shipped. **Web (slice 2):** group rows in the inbox (title, member count, "You left"), invites in Requests (Join, confirmed Decline), New group (a title and 2 to 31 people from the follow graph), the group thread at `/messages/group/[id]` (sender names and avatars, the rename line, blocked placeholders, a note that history before joining is not shown, mute, confirmed Leave) and its member sheet (invite, rename, admin roles, confirmed hand-over of ownership, confirmed removal or invite cancel), all reusing the 1:1 bubble, reaction, photo, edit, unsend and report components on the § 2223 polling cadences; a reported message's audience in `/admin/reports`. **Mobile (slice 3):** the same surfaces on the phone, behind the same flag and read fail-closed: group rows and "You left" rows in the inbox, invitations in Requests (Join, confirmed Decline), New group from the inbox's app bar (`group_create_screen.dart`), the group thread (`group_thread_screen.dart`: sender names and avatars, the rename line, the blocker's placeholders, the before-you-joined note, mute, confirmed Leave in the overflow menu, a draft kept per account and group), and the member sheet (`widgets/group_members_sheet.dart`: invite, rename, admin roles, confirmed hand-over, confirmed removal or invite cancel). The thread reuses the 1:1 bubble and edit dialog (`widgets/dm_bubble.dart`), reactions, photos, unsend and report, on the § 2223 polling cadences. A group message notice or push opens the group and a `group_invite` opens the inbox on Requests; the bell collapses group notices by conversation on both platforms (the `notification_groups` pair), and the pure rules are the `group_messages` parity pair. § 1916 / § 2223 (polling, not Realtime) stand. Where slices 1 and 2 differ from the sketch below: the send/remove serialisation is a per-member transaction advisory lock, not row locks (§ 2461); a group message notice reuses kind `message` with `conversation_id` set rather than a kind of its own (§ 2463); club-channel columns are slice 5.

**Condition C12 (pre-deploy): docs done, owner sign-off pending at flag-open.** The DPIA section is [dpia.md § Group conversations, club channels and Realtime](../compliance/dpia.md#group-conversations-club-channels-and-realtime-issue-1365); `/privacy` names group conversations in § 2 and § 7 (who sees a message, leave / removal / deletion, the export difference, retention); the group rows are in [retention.md](../compliance/retention.md); both audit command lists carry the new columns (slice 1). Club channels are covered in the DPIA as specced, and their `/privacy` copy lands with slice 5. What remains is the owner's sign-off as controller on #1097 when the `group_messages` flag opens. **And a 30-day privacy-change notice (owner decision, 2026-11-11):** groups go live only after every user has been sent a notice of the `/privacy` change at least 30 days before the flag opens; the send date is recorded on #1097 beside the sign-off, and the flag-open PR is not merged before that date plus 30 days ([deployment.md](../ops/deployment.md)).

The 1:1 model this extends: every message is a `direct_messages` row in a `conversations` row (`kind = 'direct'`), and each participant has a `conversation_participants` row holding their own view (`hidden_before`, `muted_at`, `archived_at`, `marked_unread_at`, `request_state`), owner-read and written only by definer RPCs (migration `20271105000010`, § 2287). The send gate is the INSERT policy through `private.dm_send_admitted` (§ 2384, § 2447, § 2451). This page answers each open question in #1365 with a **recommendation**, the alternatives considered, and the reason.

Terms used below:

- **group**: a conversation of 3 to N people that its members created (`kind = 'group'`).
- **club channel**: a conversation attached to one club, whose audience is that club's active members (`kind = 'club'`).
- **readable window**: the span of messages a participant may read, from their `joined_at` to their `left_at` (or now).

## 1. One message rail, not a second table

**Recommended: group and club-channel messages are `direct_messages` rows**, with `recipient_id` null and a server-set `is_group` flag. A group message then inherits unsend, edit and its window, the report snapshot, reactions, photos and their re-encode, search, the 2-year purge, the erase-what-nobody-can-see purge, the sender's account-deletion cascade, and both export rails, each of which has pgtap coverage today.

- **Alternative: a `conversation_messages` table.** Cleaner RLS on day one, since nothing in it assumes a recipient. Rejected for the reason § 2447 rejected `coach_share_messages`: it is a second rail with its own retention, export, report, reaction, photo and search paths for what is a message, and each of those has to be built and audited again. A rail that is missed in one of those paths is a retention or export gap.
- **The cost of reuse:** every definer RPC that touches a message today assumes a sender and a recipient (`mark_direct_messages_read(partner, …)`, `edit_direct_message`, `unsend_direct_message`, `set_direct_message_reaction`, `submit_report`, the image gate, the purge). Each one has to gain a group branch through **one** shared helper, `private.can_read_message(message, user)`, and a pgtap matrix pins every RPC against a non-member, an ex-member, an invitee and a member reading before their `joined_at` (slice 1). An RPC that keeps its 1:1 check refuses a group message, so a missed branch fails closed, not open.

## 2. Who creates a group, who adds and removes members, size cap

**Recommended:**

| Question | Recommendation | Alternatives |
|---|---|---|
| Who creates | Any signed-in runner. The creator becomes the group's `owner`. | Pro only (rejected: groups are a social basic, not a perk, and the paywall would split a running group); club admins only (rejected: a group of friends is not a club). |
| Who can be invited | Anyone the inviter could message 1:1 under `private.dm_send_admitted`: a follow edge either way, an active coaching link, or a shared club or event context. A block either way refuses, with the same single 42501 sentence as a send (§ 1916), and a block made after the invite withdraws it and refuses its acceptance (`20271224000400`). The invitee's `dm_requests = false` setting narrows it to follow edges and coaching links, as for 1:1 requests (§ 2451). | Mutual follows only (stricter; rejected as the default because a running group is often people who met at a club run and follow one way). Anyone with a link (rejected: an invite link is a spam and enumeration surface; it can come later with its own review). |
| Consent to join | **Always an invite, never a silent add.** An invitee gets a pending row; they see the group's title, who invited them and the member count, and no messages, until they accept. Pending invites live in the Requests list beside message requests and raise one `group_invite` notification. An invite expires after 14 days. | Silent add for follow edges (rejected: consent to a 1:1 conversation is not consent to a group with people you may not know, and being added to a group is a harassment vector in every chat product). |
| Who adds | Owner and admins. | Any member (WhatsApp's optional mode; rejected as the default because it lets one member pull strangers in front of everyone). |
| Who removes | Owner and admins can remove any member below their own role; nobody removes the owner. | Any member removes anyone (rejected). |
| Roles | `owner` (one), `admin`, `member`. The owner can promote and demote admins and transfer ownership. When the owner leaves or deletes their account, ownership passes to the longest-standing admin, else the longest-standing member; a group with no active member left is purged. | No roles, creator-only control (rejected: an owner who leaves strands the group). |
| Leave | Any member, at any time, one action, **confirmed** (it cannot be undone from the app: rejoining needs a new invite; [conventions.md § Destructive actions](../architecture/conventions.md)). | Undo bar (rejected: leaving takes effect on the server at once, as it must for the read path). |
| Size cap | **32 members** including pending invites, as a CHECK-like guard in the invite RPC (`c_group_max_members`), recorded as a default the owner can raise. A running group is 6 to 15 people (the `runner-social-group` persona). | 256 or more (rejected for v1: notification fan-out and per-member state grow with it, and a group that large is a club, which has its own channel). |
| Creation limits | `create_group_conversation` and `invite_to_group` get their own rate-limit buckets (default 10 groups a day, 50 invites a day) on top of the send buckets. | — |
| Title | Required, 1 to 60 characters after trim, editable by owner and admins; a rename is a system line in the thread. No group avatar in v1. | — |

## 3. RLS for N participants

The participant row gains a lifecycle: `membership_state` is `invited`, `active` or `left` (a removal is `left` with `removed_by` set), plus `left_at`, `role`, `invited_by` and `last_read_at`. Direct conversations keep `active` and a null role.

**Read.** A message in a group is readable by a participant whose state is `active` and whose readable window contains the message's `created_at`, and by its own sender always (their own words, which the export and Art 15 cover). The window starts at `joined_at`, which the accept RPC stamps from the server clock. `hidden_before` still applies on top. The SELECT policy gains one group branch through a SECURITY DEFINER, `STABLE` helper; the 1:1 branch is unchanged.

**History before joining: not visible (recommended).** A new member reads from the moment they accepted. People wrote earlier messages to the members of that time. Alternative: full history for new members (Slack style), rejected as the group default; offered as a per-group owner choice only if the owner decides so (decision D3).

**After leaving or removal: no further reads of other members' messages (recommended).** The moment a member leaves or is removed, the group branch stops admitting them, including for the messages inside their old window; they keep their own sent messages. Their inbox row becomes "You left {group}" with only their own messages, and they may delete it for themselves. Alternative: read-only access to the old window (WhatsApp keeps the local copy), rejected because the server would then keep serving a removed person (often removed for cause) the group's history. A client that cached messages keeps what it cached; that is outside the server's control and the memo says so.

**Send.** The INSERT policy admits a group message only from an `active` member, and in an `announce` club channel only from its owner, admins and event organisers (§ 5). A block does not stop a member posting to a group they share with the blocker; it filters what the blocker reads (below). The BEFORE INSERT trigger locks the sender's participant row `FOR SHARE`, and leave/remove take it `FOR UPDATE`, so a send racing a removal either commits before the removal or is refused; it cannot land after it.

**Report.** Any participant who can read the message under the read rule may report it, through the same `submit_report` and the same server-side snapshot (§ 2221). The read rule is the gate, so the RPC cannot be used to read a message the reporter could not already read. The sender cannot report their own message. **An invite can be reported before it is accepted** (`20271224000800`): from the invite row in Requests, `submit_report('group_invite', <conversation>)` files with the general reasons, open only to someone holding a pending invite to that group, and snapshots the title and the inviter they were shown for the admin queue.

**Block.** Recommended: **a block filters, it does not dissolve.**

- The blocker no longer sees the blocked person's messages in any group they share (the read branch reads only the **caller's own** block, as search does in § 2451, so being blocked reveals nothing). Their place in the thread shows "Message from someone you blocked" with no text, so replies still make sense.
- The blocked person still sees the blocker's messages. Hiding them would tell the blocked person about the block the moment the blocker posts and others reply.
- Neither can invite the other to a group; an invite between them is the generic refusal.
- An existing group is not broken up. The blocker is offered Leave beside the confirmation of the block.
- Alternatives: a block hides the whole group from the blocker (rejected: one difficult member would cost the blocker every running group they share); a block removes the blocked person from groups the blocker owns (rejected: it leaks the block to the whole group and lets a block become a moderation tool).

**Mute, archive, delete for me, mark unread.** Per participant, as today, through the existing RPCs, which gain the group branch. Mute in a group suppresses the `message` notification for that participant only.

**Unread count and read receipts.** Groups cannot use the per-message `read_at` (there is no single recipient). The unread count is messages newer than `conversation_participants.last_read_at`, written by a new `mark_conversation_read(conversation, through message)`. **No read receipts in groups (recommended):** an "N seen" or per-member list tells every member each other member's reading habits. Alternative: "Seen by N" for members whose `dm_read_receipts` is on, deferred to a later decision (D6).

**Enumeration.** Every group RPC answers a conversation the caller is not in, one that does not exist and one they left with the same P0002. The member list is readable by active members only. An invitee sees the title, the inviter and a count, never the member names, until they accept.

## 4. Account deletion, the 2-year purge and the exports

Extends § 2221 (keep-on-delete for the other side's sent messages) and § 2234 (the owner's sign-off on that rule).

| Event | Recommended rule |
|---|---|
| A member deletes their account | Their sent group messages are erased (`sender_id` cascade, the § 2221 rule; Art 17(1)). The group sees "Deleted account" for their participant line and nothing in its place for their messages. Their participant row cascades. Ownership passes as in § 2. Reactions they made go with them (existing cascade). |
| A member leaves or is removed | Nothing is erased; their sent messages stay in the group (they wrote them to that audience), and remain theirs to unsend while they are a member. **After leaving they can still unsend their own messages** (recommended, so leaving is not a trap that freezes what they said). |
| 2-year purge | Unchanged: `created_at` older than two years is erased, group or not. |
| Erase what nobody can see (`20271107000002`) | Extended: a group message is erased when no `active` participant whose window contains it can still see it (each has `hidden_before` past it) **and** its sender cannot (they deleted for themselves, left and deleted, or their account is gone). A group with no active member is purged with its messages on the next run. |
| A report holds a message | Unchanged: the snapshot outlives unsend, deletion and purge under the reports windows (§ 2231, `20271022000001`). |
| Art 15 / Art 20 export (both rails: `export-data/backup_spec.ts` and the Go worker) | **Sent group messages in full** (`direct_messages_sent.json`, as today), the subject's own group memberships with role, joined, left and invited-by (`conversation_settings.json`), and their reactions and photos (existing files). **Other members' messages are not exported** (recommended). Art 20(1) covers data the subject provided; the rest of a group's messages are other people's data, and Art 20(4) and Art 15(4) protect their rights. The 1:1 export carries received messages because a 1:1 thread is correspondence addressed to the subject; a group message is not addressed to one person. Alternative: export the subject's readable window with other senders as stable per-export pseudonyms (decision D5). |

Both audit commands (`.claude/commands/audit/data-export-completeness.md`, `account-deletion-completeness.md`) gain the new columns in slice 1, and `retention.md` gains the group rows.

## 5. Club channels

**Recommended: opt-in, one per club, members-only, open discussion by default, built after groups.**

| Question | Recommendation | Alternatives |
|---|---|---|
| Does every club get one | **No.** A club owner or admin turns the channel on from the club's admin panel. Many clubs are an event calendar and do not want an unmoderated chat in front of their members. | Automatic for every club (rejected: it creates a moderation duty the club admin did not take on, and makes every existing club a chat room overnight). |
| Who posts | `posting_mode` on the conversation: `open` (every active member) or `announce` (owner, admins and event organisers). Default `open`. Announcements already exist as `club_posts` (the Feed), so an announce channel mostly duplicates the Feed; `announce` is kept for clubs that want chat-style announcements with reactions. | `announce` as the default (rejected: it duplicates the Feed). |
| Audience | Active `club_members` only, **derived at read time** from `private.is_club_member`, with no per-member participant row until a member mutes, archives or marks read (state rows are created lazily). A pending, rejected or removed member reads nothing. The channel is never readable by a non-member, by anon, or through `/share/club`, **whatever the club's `is_public`**. | Participant rows synced by a `club_members` trigger (rejected: a sync has a lag, and a lag is a window in which a removed member still reads). |
| Joining and leaving | Follows membership: becoming active admits the member, leaving or being removed from the club ends it at once. A member can leave the channel without leaving the club (a lazy row in state `left`) and rejoin from the club page. | — |
| History | **Visible from the member's join** (recommended, the group rule), with the composer saying "Visible to the club's current members". Alternative: full history for every current member, decision D4. | — |
| Notifications | **Off by default** (the lazy row is created muted): a club channel badge counts, but no `message` notification fans out to every member. A member can unmute. `notifications` is a high-volume table ([migration_locks.md](../backend/migration_locks.md)), and a 500-member club would otherwise write 500 rows per message. | On by default (rejected). |
| Blocks | The § 3 filter rule. A block does not remove anyone from a club channel. | — |
| Size | No cap of its own; the club is the cap. Realtime for club channels waits for § 6's per-user fan-out to be measured. | — |

## 6. Moderation in a shared space

| Space | Who moderates | Reports and auto-hide |
|---|---|---|
| Group | The group owner and admins remove members. Nobody but the sender (unsend) and a site admin removes a message. | Reports go to the site admin queue (`/admin/reports`). **No auto-hide** (recommended): in a 5-person group, three people acting together could hide a fourth member's messages, and the group's own remedy (remove, block, leave) already exists. |
| Club channel | Club owner and admins can **hide a message** from the channel (`moderated_at` plus an admin-only action log naming who and when, the `organiser_dispute_actions` pattern of § 2441), and remove a member from the channel without removing them from the club. The sender sees "Hidden by a club admin" on their own message. Club admins never see who reported what. | Reports go to the site admin queue. Auto-hide pending review at **3 distinct vetted reporters** (the `20270218_001` rule, vetted = 5 public runs) who are active members, never from disputes. Site admins can restore. |

Site admins remain the only people who read a report's snapshot. A report filed in a group or a channel names the conversation kind in the queue so the reviewer knows the audience.

## 7. Realtime delivery

**Recommended: ship Realtime after groups (slice 4), as a per-user signal over Broadcast from the database, with no message content in the payload, and keep polling as the fallback.**

**Mechanism.** An AFTER INSERT / UPDATE trigger on `direct_messages` (and on the participant changes that matter: invite, leave, remove) calls `realtime.send` once **per active participant**, on a private topic named for that participant (`inbox:<user id>`), with a payload of `{conversation_id, event}` and nothing else. The client hears the signal and re-reads the conversation and the inbox through the REST paths it already polls with, so every byte the client draws comes through the existing RLS and column grants, and `mergeDmPollPage` already handles the merge.

**Channel authorization.** One `realtime.messages` SELECT policy: `extension = 'broadcast'` and `realtime.topic() = 'inbox:' || auth.uid()`. No INSERT policy: clients never send on the channel. Supabase evaluates these policies when the client joins and caches them for the life of the connection ([Realtime Authorization](https://supabase.com/docs/guides/realtime/authorization)); a per-user topic makes that harmless, because membership is decided by the trigger choosing whom to send to at send time, not by a cached join check.

**Why not Postgres Changes on `direct_messages`.** It needs `direct_messages` in the `supabase_realtime` publication; it authorizes every event against every subscriber, so throughput falls with subscriber count ([Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes)); RLS is not applied to DELETE events; and it delivers the row, while `direct_messages` hides `read_at` and `original_body` with column grants, which the Realtime docs do not describe applying. Supabase itself recommends Broadcast "for scalability and security" ([Subscribing to database changes](https://supabase.com/docs/guides/realtime/subscribing-to-database-changes)).

**Why no content in the payload.** Broadcast-from-database rows are stored in `realtime.messages` and dropped after about three days ([Broadcast](https://supabase.com/docs/guides/realtime/broadcast)). A body there would outlive an unsend, a delete-for-me, an account deletion and the purge for up to four days, outside both exports. A signal carries no personal data beyond a conversation id the recipient can already read.

**Presence and typing: none (recommended).** A typing indicator tells the other members when someone is composing, and Presence tells them who is online; both are behavioural data the product does not need. Alternative: typing in 1:1 only, opt-in, deferred (decision D8).

**Fallback.** Polling stays exactly as § 2223 has it while no channel is joined, when the join fails, when the connection limit is reached, and while a joined channel has delivered no heartbeat for 60 s. With a healthy channel the thread poll relaxes from 10 s to 60 s and the inbox poll from 30 s to 120 s, as a safety net for a missed signal. The cadences stay pinned across platforms by `dm_thread.test.ts`.

**Cost and limits on the current tier.** Production is on the Supabase **Free** tier ([deployment.md](../ops/deployment.md)): 200 concurrent Realtime connections and 2 million messages a month on Free; Pro is 500 connections and 5 million, then $10 per 1,000 peak connections and $2.50 per million messages ([Realtime limits](https://supabase.com/docs/guides/realtime/limits), [billing](https://supabase.com/docs/guides/platform/billing-on-supabase)). A connection is shared by every channel the client joins (100 channels per connection), and the web app already holds one for club, notification and coach subscriptions, so the inbox channel adds a channel, not a connection. A message delivered to one participant counts once: 1,000 daily senders writing 20 messages each into 5-person groups is about 3 million signals a month, which is over Free and inside Pro. **The 200-connection ceiling is the binding limit, and polling is what a client past it gets.** The Go live hub (`live.threkir.com`) is the scale path if Supabase Realtime limits bind, at the cost of its own authorization; it is not proposed for v1.

**Why after groups and not with them.** Realtime changes delivery, not the data model; the group RLS can be reviewed and tested on its own first. The per-user fan-out cost depends on group size, which slice 1's cap fixes. And polling already works on both platforms.

## 8. Schema sketch

Illustrative, not final. Each migration follows [migration_locks.md](../backend/migration_locks.md): `conversations`, `conversation_participants` and `direct_messages` are populated but not on the high-volume list, so the online forms are cheap ceremony, used anyway because the forward guard and the pre-merge checklist expect them for CHECK and FK changes.

```sql
-- conversations: the kind widens; group and club columns are nullable, no default
alter table conversations drop constraint conversations_kind_check;
alter table conversations add constraint conversations_kind_check
  check (kind in ('direct', 'group', 'club')) not valid;            -- VALIDATE next file
alter table conversations
  add column title text,                       -- group only, 1..60 trimmed
  add column club_id uuid,                     -- club only; FK NOT VALID, own file
  add column created_by uuid,                  -- FK auth.users on delete set null
  add column posting_mode text;                -- club only: 'open' | 'announce'
-- CHECKs (each NOT VALID, validated later):
--   (kind = 'group') = (title is not null)
--   (kind = 'club')  = (club_id is not null)
--   (kind = 'club')  = (posting_mode is not null)
--   posting_mode in ('open', 'announce')
--   title is null or length(btrim(title)) between 1 and 60
-- unique index conversations_one_per_club on (club_id) where kind = 'club'

-- conversation_participants: lifecycle and group state
alter table conversation_participants
  add column membership_state text not null default 'active',  -- constant default: fast path
  add column role text,                        -- 'owner' | 'admin' | 'member'; null for direct
  add column invited_by uuid,                  -- FK auth.users on delete set null
  add column left_at timestamptz,
  add column removed_by uuid,                  -- FK auth.users on delete set null
  add column last_read_at timestamptz;
-- CHECKs: membership_state in ('invited', 'active', 'left');
--         (membership_state = 'left') = (left_at is not null);
--         role in ('owner', 'admin', 'member')
-- partial unique index: one owner per conversation where role = 'owner' and membership_state = 'active'
-- index (conversation_id) where membership_state = 'active'   -- fan-out and the read branch

-- direct_messages: a group message has no recipient and no deleted-partner key
alter table direct_messages add column is_group boolean not null default false;  -- set by trigger, no client grant
alter table direct_messages drop constraint direct_messages_deleted_partner_key_check;
alter table direct_messages add constraint direct_messages_audience_check check (
  (is_group and recipient_id is null and deleted_partner_key is null and read_at is null and seen_at is null)
  or (not is_group and (recipient_id is null) = (deleted_partner_key is not null))
) not valid;
alter table direct_messages add column moderated_at timestamptz;   -- club channel hide
-- private.club_channel_actions (admin-only log: who hid what, when), the § 2441 pattern
```

New CHECK columns (`conversations.kind`, `posting_mode`, `membership_state`, `role`) are registered in `apps/web/scripts/check_constraint_unions.mjs` with their client rails in the same change. Both type generators run (`npm run gen:types`, `dart run scripts/gen_dart_models.dart`).

New RPCs, all SECURITY DEFINER with a pinned `search_path`, P0002 for anything the caller is not in: `create_group_conversation(title, invitees[])`, `invite_to_group`, `accept_group_invite`, `decline_group_invite`, `leave_conversation`, `remove_group_member`, `set_group_member_role`, `transfer_group_ownership`, `rename_group`, `mark_conversation_read`, `set_club_channel(club, enabled, posting_mode)`, `moderate_club_channel_message`. `dm_threads()` gains `kind`, `title` and `member_count` and the group unread count; a group row's `partner_id` is null.

## 9. Slices

Web first, then mobile ([decisions § 24](../architecture/decisions.md)); each slice follows [conventions.md § Test hygiene](../architecture/conventions.md#test-hygiene--review-then-unit-then-e2e) and ships behind the `group_messages` row of `private.feature_flags`, closed in prod until the pre-deploy item in deployment.md is ticked.

| Slice | What | Tests | Size | Blocked by |
|---|---|---|---|---|
| 0 | This spec, the security memo, the owner's sign-off on #1097 | — | done when signed | — |
| 1 (built, § 2461) | Backend groups: the migrations above, the read and send branches, `private.can_read_message` threaded through every message RPC, the group RPCs, the purge and export extensions, retention.md, both audit command lists | pgtap: a membership matrix (non-member, invitee, member, ex-member, removed member, member before `joined_at`) against every read path and every message RPC; the send-versus-remove race; the block filter (own block only); invites and the cap; ownership transfer; account deletion of a member and of the owner; the extended purge; both export rails (Deno `backup_spec.test.ts`, Go `supabase_dataexport_test.go`) | L, about 2 weeks | D1, D2, D3, D5 |
| 2 (built, § 2463) | Web groups: create, invite, the Requests list for invites, the group thread with sender names, the member sheet with roles, leave (confirmed), remove (confirmed), rename; i18n in every web locale; the group notifications, the rename system line and the blocked placeholder that slice 1 left over | web unit for any new pure helper (inbox ordering with groups, the `messages_inbox` parity pair); Playwright `tests-e2e/messages/group-*.spec.ts` for create, invite and accept, a removed member losing the thread, block filtering, leave; `group-member-management.spec.ts` drives promote, demote, transfer with its confirm, rename (an emoji title up to 60 code points is accepted; the inputs carry no `maxlength`, which counts UTF-16 units, and say why a title is refused), the invite panel and the people picker's search and 32-seat cap; pgTAP pins the `group_messages` flag off on every group RPC and read path (`group_messages_membership_test.sql` 78, `group_messages_read_matrix_test.sql` 96) | L, about 1.5 weeks | slice 1 |
| 3 (built, § 2468) | Mobile groups: the same surfaces in `messages_screen.dart` and a group thread, mirrored to `mobile_ios`, every ARB | Flutter widget tests (`pumpUntil`, no fixed delays), api_client tests; the parity pair's Dart side; `group_people_picker_test.dart` (search, the count, the seat cap counting invitations, members and invitees never listed) | M to L, about 1.5 weeks | slice 2 |
| 4 | Realtime signals: the trigger, the `realtime.messages` policy, the web subscription with the polling fallback and relaxed cadences, then mobile | pgtap: the trigger sends to active participants only, never to a left or removed member or an invitee, and the payload has no body; Playwright: a message appears without waiting for the poll, and the poll still delivers with Realtime blocked; `dm_thread.test.ts` pins the relaxed cadences on both sides | M, about 1 week | slice 2 (web), slice 3 (mobile), D7 |
| 5 | Club channels: `set_club_channel`, the derived audience, lazy muted state, posting modes, club-admin hide with its log, auto-hide wiring; web then mobile | pgtap: pending, rejected and removed members read nothing; a public club's channel unreadable by anon and non-members; announce mode; the hide log admin-only; auto-hide at 3 vetted members; Playwright and Flutter for the channel surfaces | L, about 2 weeks | slices 1 to 3, D4, D9 |

## 10. Owner decisions

Each has a recommended default; a slice is blocked only by the decisions in its row above.

| # | Decision | Recommended default | Blocks |
|---|---|---|---|
| D1 | Who may be invited | Anyone the inviter could message 1:1 (follow edge either way, coaching link, shared club or event), always as an invite the invitee accepts | 1 |
| D2 | Group size cap | 32 including pending invites | 1 |
| D3 | History for a new member | Not visible before they joined | 1 |
| D4 | History for a new club-channel member | Not visible before they joined | 5 |
| D5 | Other members' messages in the subject's export | Not exported; sent messages, memberships and own reactions and photos only | 1 |
| D6 | Read receipts in groups | None | not blocking (a later change) |
| D7 | Realtime on the Free tier, or after a move to Pro | Ship signals on Free with polling past 200 connections; move to Pro when the peak-connection metric passes 150 for a week | 4 |
| D8 | Typing indicators or presence | None | not blocking |
| D9 | Club channels at all, and the default posting mode | Opt-in per club, `open` | 5 |
| D10 | Auto-hide in groups | None in groups; 3 vetted active members in club channels | 1 (groups), 5 (channels) |
| D11 | Leaver can still unsend their own messages | Yes | 1 |
| D12 | The removed-member rule | No reads of others' messages after leaving or removal | 1 |

## 11. What this does not re-litigate

§ 1916 and § 2223 (polling, one refusal sentence, owner-read state) stand until the owner signs off this spec; slice 4 is the change that would supersede their polling half, recorded in its own decisions entry when it lands. § 2221's deletion rule is extended, not changed: the leaver's own words go, the others' stay.
