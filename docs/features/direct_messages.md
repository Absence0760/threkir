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

- pgtap: `direct_messages_test.sql`, `dm_unsend_report_keep_on_delete_test.sql`, `direct_message_route_attachment_test.sql`
- web unit: `social/dm_thread.test.ts`, `core/visible_poll.test.ts`, `social/messages_inbox.test.ts`
- Playwright: `tests-e2e/messages/` — `dm-thread-block.spec.ts` (block from the conversation), `dm-live-poll.spec.ts` (thread and inbox polls, driven by Playwright's clock), `coach-inbox-row.spec.ts` (the Coach row: no-consent, preview, AI label, unpin and hide persisting, the `/coach` redirect), plus the send, paging, permission, unsend/report and route-attachment specs
- mobile: `direct_messages_screen_test.dart`, `messages_coach_row_test.dart`, `messages_inbox_test.dart`, api_client `direct_messages_test.dart`

## Not built yet (issue #1216)

Delete-for-me, mute and archive (a per-participant conversations model), read receipts, edit, Realtime delivery, a message-requests inbox for non-followers, and group conversations.
