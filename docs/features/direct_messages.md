# Direct messages

1:1 messages between two runners. Web is the canonical surface (`/messages/[[id]]` under the `/messages` layout that holds the inbox); mobile has the same inbox and conversation (`messages_screen.dart`, `message_thread_screen.dart`, mirrored to `mobile_ios`). The parity row is [parity.md § Direct messages (1:1)](../product/parity.md); this page is the behaviour reference.

## The AI Coach in the inbox

Since [decisions § 2227](../architecture/decisions.md) (issue #1215, Phase 1) the AI Coach is one more row in the inbox, pinned at the top by default. The inbox is merged in the **list only**: the row is `dm_threads()` plus the newest non-archived `coach_messages` row, and the two tables keep their own RLS, retention and rendering. No AI text ever appears in a conversation with a person, and the Coach never takes part in one.

| | Web | Mobile |
|---|---|---|
| Row | `routes/messages/+layout.svelte`, state in `stores/messages_inbox.svelte.ts` | `messages_screen.dart` |
| Opens | `/messages/coach?plan=<plan of the previewed message>` (or `?plan=none`), the existing `CoachChat` in the conversation pane | `CoachScreen` on that plan |
| Shown when | `coachEnabled()` | `ProPerks.coach` from `/app-capabilities.json`, and a `TrainingService` is present |
| Placement | `messages_coach_row` universal setting (`pinned` default / `listed` / `hidden`; [settings.md](../backend/settings.md)); the row's pin button toggles pinned ↔ listed, Settings → Display offers all three | the row's pin button; Settings → Preferences → Messages |

Ordering and the preview text are the `messages_inbox` parity pair ([parity_pairs.md](../architecture/parity_pairs.md)): a listed row goes before the first conversation whose latest message is strictly older than its own, and after every conversation when it has no message; the preview drops the markdown and is always placed as text.

**Consent gate.** The row is shown to a runner who has not accepted the AI disclosure, but `coach_messages` is not read for them: the row says what the Coach is ("Ask about your training, your plan or a run.") and opening it shows the existing consent prompt. A failed consent read counts as no consent. Every Coach message, in the inbox row and in the chat, carries an avatar and an "AI" tag that a screen reader hears as "AI-generated" (EU AI Act Art. 50).

`/coach` redirects to `/messages/coach` with its query kept, and the sidebar has no Coach row any more. The mobile Home coach card stays and opens the same `CoachScreen`.

## Who can message whom

The `direct_messages` INSERT policy is the only gate, and it is the same for every client:

- a follow edge exists in **either** direction between sender and recipient, and
- `is_blocked_either_way(sender, recipient)` is false, so a block stops sends **both ways** — the blocked person cannot reach the blocker, and the blocker cannot reach the person they blocked (`direct_messages_test.sql` pins both directions).

A refusal is one 42501 for both reasons, and clients show it as one sentence ("You can only message people you follow or who follow you, and who haven't blocked you."). `user_blocks` is owner-read, so a client never learns that the *other* person blocked it ([decisions § 1916](../architecture/decisions.md)).

## Blocking from the conversation

The conversation header carries Block / Unblock for a live partner (web: a header button; mobile: the overflow menu). It calls the same `block_user` / `unblock_user` RPCs the profile does (`blockUser` / `unblockUser` in `data.ts`, `ApiClient.blockUser` / `unblockUser`), with the profile's rule from [conventions.md § Destructive actions](../architecture/conventions.md): Block is **confirmed**, because `block_user` drains the follow edge both ways and unblocking does not restore it; Unblock runs at once.

While the viewer's own block stands, the composer gives way to a notice ("You blocked {name}, so neither of you can message the other.") with an Unblock button. The block state is read with `isBlockedByViewer` when the conversation opens; a failed read leaves the composer up, and the server still refuses a blocked send. A deleted partner's thread has no Block. Unblocking brings the composer back, but with the follow edge gone a send is refused until one of the two follows the other again.

## Mute, archive and delete for me

Since migration `20271105000010` ([decisions § 2287](../architecture/decisions.md)) every message belongs to a `conversations` row, and each participant has their own `conversation_participants` row. Mute, archive and delete-for-me write only the viewer's row; the other person never learns of any of them (the rows are owner-read).

| Action | What it does | Guard | Web | Mobile |
|---|---|---|---|---|
| Mute | No `message` notification for new messages; the conversation's unread count leaves the nav badge. The row still shows its own count, greyed, with a muted mark. | None: Unmute is one tap away | header icon button `dm-mute-toggle` | overflow menu `message-thread-mute` |
| Archive | The conversation moves to the inbox's **Archived (n)** list until a newer message arrives (`dm_threads().archived` compares the archive stamp with the newest message, so a reply un-archives it without a write). Its unread count leaves the badge. | None: Unarchive is in the Archived list | header icon button `dm-archive-toggle` | overflow menu `message-thread-archive` |
| Mark as unread | The conversation closes and its inbox row counts one unread (more if unread messages also arrived), as does the nav badge unless it is muted or archived. Opening it again, from the inbox or anywhere else, clears the mark. The other person's `read_at` is never touched, so they learn nothing. Since migration `20271109000020` ([decisions § 2347](../architecture/decisions.md)): `conversation_participants.marked_unread_at`, written by `set_conversation_unread`; `dm_threads()` folds it into `unread` server-side and reports it as `marked_unread`; a delete clears it. | None: opening the conversation undoes it | header icon button `dm-mark-unread` | overflow menu `message-thread-mark-unread`; the thread pops with `true`, so the inbox keeps the count rather than zeroing the row it opened, and drops any list read already in flight |
| Delete conversation | Every message up to the newest one on screen when the viewer tapped Delete leaves their reads (the SELECT policy hides messages at or before `hidden_before`, which `hide_conversation(conversation, through message)` sets to that message's `created_at` and never moves back, migration `20271107000002`). A message that arrives during the undo window is not hidden, and a newer message brings the conversation back with only the messages after the delete. The other person keeps theirs, and a report's snapshot is untouched. Once no participant can see a message (both deleted past it, or the viewer deleted a deleted account's thread), the daily purge erases it, so the notice on a deleted account's thread says it will not come back and is erased within a day instead of "the other person keeps their copy". Delete is unavailable until a message is on screen. | **Undo bar, no confirm** ([conventions.md § Destructive actions](../architecture/conventions.md)): the server is told only when the window closes | header icon button `dm-delete-conversation`; the inbox hides the row while the window is open (`messagesInbox.hide`) | overflow menu `message-thread-delete`; the inbox hides the row while the window is open (`DmPendingHides`), and a commit that fails after the thread was left is reported over whatever screen is up, since the conversation comes back in the inbox |

A deleted partner's thread offers Archive and Delete but not Mute or Block. The inbox split and the badge rule are the `messages_inbox` parity pair (`partitionArchived`, `unreadDmBadgeCount`). A conversation whose delete is still inside its undo window is left out of the badge as well as the inbox on both platforms — web's sidebar badge (`dmPendingHides`, applied by `unreadDmBadgeCountExcept` to `fetchDmBadgeStates`' conversation ids) and mobile's You tab (`DmPendingHides` over `ApiClient.fetchDmBadgeStates`); the pending delete is applied to what each already holds, and only Undo or the commit re-reads the server. On web the inbox also records when each delete landed, on the monotonic clock (`performance.now()`) like every other marker its list reads are compared with, so a wall-clock step back cannot keep one alive (`#hiddenAt` in `messages_inbox.svelte.ts`, `withoutHiddenConversations` / `settledHides` in `social/dm_conversation_writes.ts`): a list read that started before the delete landed still lists the conversation, so that read leaves the row out even when it returns after the undo window has closed, and the marker is dropped once a read started after the delete is applied. A web list read is applied only to the account it was made for: one that lands after a sign-out or an account switch (another tab) is dropped rather than shown to the next account. Web's badge needs no marker: it applies only its newest read, and the commit starts a fresh one before it clears the pending flag. Each web badge read is tagged with the account it started under (`DmBadgeReader` in `social/dm_badge.ts`, bound by the root layout) and is dropped if the badge was cleared or bound to another account by the time it lands; signed out, the badge does not read at all. Without that, the read the sign-out's own undo commit starts would repaint the previous account's count after the sign-out cleared it. Undo (or a refused commit) puts the web row back at once as it was at the delete, then re-reads the list, so a message that arrived during the window reaches the row's preview and unread count as well as the badge. On mobile a read already in flight when the Undo or the commit comes is dropped, by the inbox list and the You badge alike. Mobile also keeps the landing marker, app-wide in `DmPendingHides` (`landed` records when the server answered, `hides(id, readStartedAt)` filters, `remove` is Undo or a refused commit), because its inbox and its You-tab badge each hold their last read while the one the commit asks for is in flight; each registers a `DmHideReader` and reports the start of every read it applies, and a landed marker is dropped once no open reader holds a read that started before it. Those read starts, the landing and the inbox's opened-here marker are stamped with `monotonicNow()` (`lib/monotonic_clock.dart`, an app-level `Stopwatch`), not the wall clock, and each list or badge read carries the user it was made for and is dropped if another account is signed in when it lands; the inbox also clears and re-reads on an account change (`AuthChangeAware`), and both it and the You badge then `reset()` their `DmHideReader`, so a landed marker the departed account's read was keeping goes with it rather than waiting for a read a signed-out screen never makes. A conversation delete still inside its undo window when the viewer signs out commits first, and one whose session ends some other way is undone; a commit that fails after the account is gone shows no banner (mobile says that failure on the root navigator, which outlives every screen) and does not put the conversation back (conventions.md § Destructive actions). Mobile threads opened from outside the inbox (a profile, a route) read the viewer's state with `ApiClient.fetchDmConversationState`.

## Read receipts

Since migration `20271113000001` ([decisions § 2371](../architecture/decisions.md)) a sender sees "Seen" and the time under their newest message the other person has read (web `dm-seen`, mobile `ValueKey('dm-seen')`; placed by the `dm_read_receipt` parity pair). A runner who turns read receipts off (web Settings → Privacy → Messages, `read-receipts-toggle`; mobile Settings → Preferences → Messages, `prefsReadReceipts`) neither sends nor sees them. The setting is `user_settings.dm_read_receipts` ([settings.md](../backend/settings.md)), default on.

The server enforces it, not the clients:

- `read_at` is the recipient's own fact (it drives their unread count) and is **not granted to any client**: SELECT on `direct_messages` is a column grant without it, so a sender cannot read it whatever the recipient chose. `dm_threads()` reads it as SECURITY DEFINER for the unread count; `unsend_direct_message` returns the row with it nulled; the Art 20 export of *sent* messages leaves it out (both the Edge Function and the Go worker).
- What the sender reads is `seen_at`, written by `mark_direct_messages_read(partner, through message)` beside `read_at` only when **both** participants have receipts on, with their settings rows locked so a concurrent opt-out cannot slip between the check and the write.
- Turning receipts off clears `seen_at` on every message the runner sent or received (a `user_settings` trigger), so an opt-out also withdraws receipts already shown, both ways. Turning them back on does not restore those.

Marking read is that RPC on both platforms; the old client `UPDATE ... WHERE read_at IS NULL` needed SELECT on `read_at`. A client therefore cannot tell which messages it has read, so it remembers the partner message it last marked through and marks again only when a newer one is on screen (`dmMarkReadThrough`): once on open, and on a poll that brings in a partner message.

## Unsend, report and deleted accounts

Sender-only soft unsend, a recipient-only `direct_message` report with a server-side snapshot, and keep-on-delete threads shown as "Deleted account" — see [decisions § 2221](../architecture/decisions.md) and [retention.md](../compliance/retention.md).

## Live updates: polling, not Realtime

No client subscribes to `direct_messages` over Realtime; doing so needs a publication change and its own RLS review of the channel, and stays deferred. Both platforms poll on the same two cadences:

| What | Cadence | Web constant | Mobile constant |
|---|---|---|---|
| Open conversation | 10 s | `DM_THREAD_POLL_MS` (`apps/web/src/lib/social/dm_thread.ts`) | `kMessageThreadPollInterval` (`message_thread_screen.dart`) |
| Inbox | 30 s | `DM_INBOX_POLL_MS` (same file) | `kMessagesInboxPollInterval` (`messages_screen.dart`) |

Change a cadence on both sides together; `dm_thread.test.ts` pins the web values to mobile's.

A poll runs only while the page is in front: web clears its interval when the tab goes hidden and polls at once when it comes back (`core/visible_poll.ts`); mobile skips a tick while the app is backgrounded or another route covers the screen and polls on resume. The poll's teardown runs when the conversation changes or the page is left.

A conversation poll re-reads the **newest page** rather than asking for messages newer than the last one shown: a "newer than" read would miss an unsend of a message already on screen. The page is merged by id, so no row is drawn twice (`mergeDmPollPage`). If the page does not reach back to the newest message shown, more than a page arrived since the last read; the page then replaces the list, Load earlier is offered again, and a Load earlier already in flight is dropped. A reader scrolled up stays where they are; one at the bottom follows the new message. A poll that brings in an unread message from the partner marks the conversation read. A failed poll keeps what is shown and logs; the next tick is the retry.

## Tests

- pgtap: `dm_read_receipts_test.sql` (no client reads `read_at`, receipts opted in and opted out both ways, withdrawal and no restore, the mark-read bound, `dm_threads()` still honouring `hidden_before`), `direct_messages_test.sql`, `dm_unsend_report_keep_on_delete_test.sql`, `direct_message_route_attachment_test.sql`, `dm_conversations_test.sql`, `dm_mark_unread_test.sql`, `dm_purge_hidden_test.sql` (the seen-message bound, the erase of what nobody can see, and a conversation whose only messages were the leaver's)
- web unit: `social/dm_read_receipt.test.ts`, `core/data.test.ts` (the `DM_COLUMNS` read matches the grant, no `read_at`), `social/dm_thread.test.ts`, `core/visible_poll.test.ts`, `social/messages_inbox.test.ts`
- Playwright: `tests-e2e/messages/` — `dm-thread-block.spec.ts` (block from the conversation), `dm-conversation-actions.spec.ts` (mute, archive, delete with undo, a message arriving during the undo window, the deleted-account notice), `dm-mark-unread.spec.ts` (mark as unread, the row and nav badge counting it, reopening clearing it), `dm-read-receipts.spec.ts` (Seen under the newest read message, an opt-out by either side hiding it), `dm-live-poll.spec.ts` (thread and inbox polls, driven by Playwright's clock), `coach-inbox-row.spec.ts` (the Coach row: no-consent, preview, AI label, unpin and hide persisting, the `/coach` redirect), plus the send, paging, permission, unsend/report and route-attachment specs
- mobile: `direct_messages_screen_test.dart`, `dm_read_receipt_test.dart`, `settings_read_receipts_test.dart`, `messages_coach_row_test.dart`, `messages_inbox_test.dart`, api_client `direct_messages_test.dart`

## Not built yet (issue #1216)

Edit, Realtime delivery, a message-requests inbox for non-followers, and group conversations. The `conversations` model takes a group or club chat without another migration of the participant state; only `kind = 'direct'` exists, and the send path still addresses a single recipient.
