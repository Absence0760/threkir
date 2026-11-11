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

## Suggested plan changes in the conversation

Since [decisions § 2382](../architecture/decisions.md) (issue #1215, Phase 2) a conversation between an athlete and the coach who assigned their plan shows that plan's suggested changes as **system cards** above the messages: `PlanChangeRequests.svelte` on web (scoped to the partner), `PlanChangeRequestsSection` in `message_thread_screen.dart` on mobile. Like the Coach row, they are merged in the UI only. A request is a `plan_change_requests` row, not a `direct_messages` row, so the follow gate, the two-year purge, unsend and report do not apply to it, and the two people need not follow each other for the card to show. It carries a structured change set and no AI text (§ 110). The coach approves (all lines or the ticked ones) or declines with an optional note; the athlete withdraws or applies it themselves. Pending requests come first, then the three most recent decided ones. The same cards sit on the plan's detail page, where the `plan_change_request` / `plan_change_decision` notifications link.

## Who can message whom

The `direct_messages` INSERT policy is the only gate, and it is the same for every client. Since migration `20271115002384` ([decisions § 2384](../architecture/decisions.md)) its audience rule is `private.dm_send_admitted(recipient)`:

- `is_blocked_either_way(sender, recipient)` is false, so a block stops sends **both ways** — the blocked person cannot reach the blocker, and the blocker cannot reach the person they blocked (`direct_messages_test.sql` pins both directions); and
- the recipient has not **declined** a request from the sender; and
- one of: the recipient **accepted** a request in this conversation (or replied to one, or sent one); a follow edge exists in **either** direction; or the pair shares a context, which makes the send a **message request** (next section).

A refusal is one 42501 for every reason, and clients show it as one sentence ("You can message people you follow or who follow you, or someone you share a club or an event with, unless either of you has blocked the other."). `user_blocks` and `conversation_participants` are owner-read, so a client never learns that the *other* person blocked it or declined its request ([decisions § 1916](../architecture/decisions.md)).

Since migration `20271210001215` an **active coaching link** counts as a follow edge for this rule (`private.dm_follow_edge`), so a coach and the athlete they coach can write to each other without a request: a plan-change card ([§ 2382](../architecture/decisions.md)) and a shared AI answer both live in that thread. Ending the link removes the edge on the next send.

## Typed messages: shared AI answers and AI-assisted messages (issue #1215)

`direct_messages.kind` is `text`, `coach_share` or `ai_assisted` (CHECK, registered in `check_constraint_unions.mjs`; `DmKind` / `kDmKinds` in the `coach_share` parity pair).

- **`coach_share`** — paragraphs of the sender's own AI Coach answer, sent to their active coach by `share_coach_message` only (migration `20271210001215`). The INSERT policy admits no client-written `coach_share` and no `coach_message_id`; `edit_direct_message` refuses one (55000), and unsend clears the text and the link back. Both clients draw it as an AI-labelled card (`CoachShareCard`, `coach_share_card.dart`) from typed blocks, never HTML, and the inbox preview carries the AI tag (`dm_threads().last_kind`). Gate: the `coach_share` row of `private.feature_flags`, closed in prod until the CISO confirms the labelling ([deployment.md](../ops/deployment.md#share-with-coach--after-the-ciso--security-analyst-confirms-the-ai-labelling)).
- **`ai_assisted`** — a coach's own message drafted with the coach assistant (migration `20271210001217`). The client sets it; the INSERT policy admits it only from an active coach to their athlete. Both sides show an "AI-assisted" marker. See [coach_roster.md § Coach assistant](coach_roster.md#coach-assistant-issue-1215-phase-4).

## Message requests

Someone who does not follow you, and whom you do not follow, can message you first only when you share one of:

- an **active membership of the same club** (`club_members.status = 'active'` on both sides; a pending or rejected member is not one), or
- an **event they host** (`events.host_user_id`) that you have a live RSVP for (`going`, `maybe` or `waitlisted`). Host to attendee only: an attendee messaging a host is covered by the club rule, since every event belongs to a club.

A stranger with neither is refused as before. The message lands in your **Requests** list instead of the inbox, and `conversation_participants.request_state` records where it stands, per participant and readable only by its owner:

| State | Meaning |
|---|---|
| null | not a request: the conversation came through the follow graph |
| `pending` | someone without a follow edge wrote to you and you have not answered |
| `accepted` | you accepted, replied, or you sent the request yourself |
| `declined` | you declined; the requester cannot send again until you write to them |

The AFTER INSERT trigger `direct_messages_request_state` moves the state; `accept_message_request(conversation)` and `decline_message_request(conversation, through message, block)` are the only other writers.

**Nothing leaks before you accept.** A pending (or declined) request raises no `message` notification, and `mark_direct_messages_read` writes no `seen_at` while your row is pending, so opening a request does not show the requester "Seen". The requester's own row says `accepted` whatever you do, so they cannot tell pending from declined. Reads made while it was pending are not turned into receipts afterwards.

**Limits.** A pending request holds at most **three** messages from the requester; the fourth is refused with 54000, shown as "You can send up to 3 messages until they accept your request." (this says nothing about the recipient). Opening a new request spends the `open_message_request` rate-limit bucket, 20 a day, on top of the send buckets every message spends. Both numbers are conservative defaults recorded in decisions § 2384.

| | Web | Mobile |
|---|---|---|
| Requests list | `Requests (n)` under the inbox (`inbox-show-requests`), back with `inbox-back-to-inbox`; `partitionArchived` in the `messages_inbox` parity pair files a request there even when archived, and `unreadDmBadgeCount` leaves it out of the nav badge | the same row (`inbox-show-requests`) and the same pair |
| Request bar | replaces the composer: notice, Accept (`dm-request-accept`), Decline (`dm-request-decline`), Block (`dm-request-block`) | `message-request-bar` with `message-request-accept` / `-decline` / `-block`; a thread opened outside the inbox reads the state with `fetchDmConversationState` |
| Accept | at once; the conversation joins the inbox and the composer comes back | the same |
| Decline | **confirmed** (`dm-request-decline-confirm`): it cannot be undone from the app, because the conversation leaves every list ([conventions.md § Destructive actions](../architecture/conventions.md)); the decline stops at the newest request message on screen, and the pane returns to the inbox | **confirmed** (`message-request-decline-confirm`); the thread closes |
| Block | the profile's confirm; declines and blocks in one transaction (`p_block`) | the same |

**Blocking resets consent.** A block between the pair resets an `accepted` state on both sides to null (the `user_blocks_reset_dm_acceptance` trigger), so unblocking does not quietly reopen a request-based conversation; like the follow edges `block_user` drains, consent has to be given again.

**Retention, export and deletion.** No new table: the two columns live on `conversation_participants`, which cascades with the participant's account and with its conversation and is swept with it by the conversation purge. Both exports' `conversation_settings.json` carry `request_state` and `requested_at`. A requester who deletes their account takes their messages with them (`sender_id` cascade), so the request disappears from your list.

### Turning requests off

Since migration `20271213121601` ([decisions § 2451](../architecture/decisions.md)) a runner can turn message requests off: web Settings → Privacy → Messages (`message-requests-toggle`), mobile Settings → Preferences → Messages. The setting is `user_settings.dm_requests` ([settings.md](../backend/settings.md)), default on, owner-read.

It is enforced in the send path, not by hiding a button: with it off, `private.dm_send_admitted` no longer admits the shared-context branch, so nobody without a follow edge (or an active coaching link) can message the runner first, and a request still pending takes no more messages from the requester. A follow edge and a conversation the runner already accepted are unaffected; a pending request already in their Requests list can still be accepted or declined. The refusal is the same 42501 every other refusal is, so a sender cannot tell the switch from a block, a decline or a missing follow (§ 1916), and they cannot read the setting.

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

## Editing a sent message

Since migration `20271114000210` ([decisions § 2373](../architecture/decisions.md)) the sender may edit the text of their own message for **15 minutes** after sending it. Both sides then see the new text and an "Edited" mark (web `dm-edited`, mobile `ValueKey('dm-edited')`). The route attachment cannot be edited, and an unsent message cannot be edited.

| | Web | Mobile |
|---|---|---|
| Offered | an Edit action on the bubble (`dm-edit`) while `canEditDm` holds; the page re-checks every 15 s so it disappears when the window closes | Edit in the long-press options (`message-action-edit`), checked when the sheet opens |
| Editing | inline: the bubble becomes a text field (`dm-edit-input`), Enter or Save saves, Escape or Cancel cancels | a dialog (`message-edit-field`, `message-edit-save`) |
| Refused | the reason under the field (`dm-edit-error`); the field and the typed text stay | the reason as the field's error text; the dialog and the typed text stay |

The server decides, not the clients: `edit_direct_message(message, body)` is SECURITY DEFINER and is the only write path (clients have no UPDATE grant on `direct_messages`). It allows the edit only for the caller's own live message, inside the window, not hidden from the caller by a delete-for-me, and with no block either way. Every refusal but "not yours" is one 55000, shown as "This message can no longer be edited.", so an edit refused by a block does not reveal the block; a message the caller did not send answers P0002, shown the same. A body the same as the current one is a no-op. Edits have their own rate-limit bucket (`edit_direct_message`, 60 an hour). The window is defined once, as `c_window` in the RPC; the clients' `DM_EDIT_WINDOW_MS` / `kDmEditWindow` (the `dm_edit` parity pair) only decide whether to offer Edit, and a unit test on each side reads the migration to keep them equal. A client clock behind the server's can offer Edit the server then refuses; the refusal is shown.

**Moderation.** The first edit keeps the text as first sent in `original_body`, which no client can select. A report filed after an edit snapshots both texts (`reports.snapshot_body` and `snapshot_original_body`), and `/admin/reports` shows the original under the reported text, so an edit cannot launder a message before it is reported. Unsend clears `original_body` with the body. The Art 20 export carries `edited_at` and `original_body` on the sender's messages, and the received side (`select *`) carries them too.

## Reactions

Since migration `20271213121602` ([decisions § 2451](../architecture/decisions.md)) a participant can put one reaction on a message from a fixed set of six keys (`thumbs_up`, `heart`, `laugh`, `surprised`, `sad`, `fire`; CHECK on `direct_message_reactions.reaction`, registered in `check_constraint_unions.mjs`), change it, or take it off. Both sides see one chip per key with its count under the message.

**No emoji in the source.** The table stores the key, never the glyph, and each client draws the glyph from its Unicode codepoints (`DM_REACTION_CODEPOINTS` / `kDmReactionCodepoints`, the `dm_reactions` parity pair), so the no-emoji rule holds for code, docs and data while the reader still sees the emoji. Each glyph has a localized accessible name (`messages.reaction.<key>`).

**The server decides.** `set_direct_message_reaction(message, reaction | null)` is the only writer (clients hold no write grant). It refuses with one 55000 an unsent message, a message hidden from the caller by a delete-for-me, a deleted partner, a block either way, and any conversation where a request is pending or declined (on either side), so a refusal does not reveal which; a non-participant gets P0002. Each call spends `dm_reaction` (120 an hour). A reaction raises no notification. The SELECT policy admits a reaction only when the reader can read its live message under `direct_messages`' own policy; unsending a message deletes its reactions.

| | Web | Mobile |
|---|---|---|
| Add | React under the bubble (`dm-react`) opens a six-option picker (`dm-reaction-picker`) | the long-press options |
| Chips | `dm-reaction-chip`, pressed when it is the viewer's; tapping their own takes it off | the same |
| Offered | a live partner, not blocked by the viewer, not a pending request; the server still decides | the same |

A fixed set carries no free text, so a reaction has no report path, no snapshot and no moderation of its own. It is in both exports (`direct_message_reactions.json`, the subject's own) and goes with the message (cascade: purge, unsend, the sender's deletion) or with the reactor's account.

## Search

Since migration `20271213121603` the inbox has a search box (web `inbox-search`, mobile the field over the inbox). `search_direct_messages(query, limit)` is **SECURITY INVOKER**: it reads `direct_messages` under the caller's own SELECT policy and column grants, so it can return nothing the caller could not already select, and it leaves out unsent messages, the Requests list, declined conversations, and conversations with someone the caller blocked (only the caller's own block is read, so being blocked by someone changes nothing and reveals nothing). A definer search was rejected: it would have had to restate the participant and `hidden_before` rules, and one missed clause would turn it into a read of anyone's messages. The query is 2 to 100 characters, matched as a literal substring (`%`, `_` and `\` escaped), newest first, at most 50 rows; the `dm_search` parity pair bounds the query and centres the snippet. The trigram index `direct_messages_body_trgm` is built online by a pg_cron job (CREATE INDEX CONCURRENTLY cannot run in the apply transaction; [migration_locks.md](../backend/migration_locks.md)); search is correct without it, only slower.

## Photos

Since migration `20271213121604` ([decisions § 2451](../architecture/decisions.md)) a message can carry one photo, with or without a caption.

1. The client re-encodes the picked file to a JPEG at most 2048 px on the long edge (web `dm_image_encode.ts` through a canvas, mobile in an isolate), which drops the camera's EXIF / XMP, GPS position included, and bakes the orientation into the pixels.
2. `create_dm_image_upload()` makes a pending `direct_message_images` row and returns `{owner}/{image}/upload`; the client uploads there. The private `dm-images` bucket takes `image/jpeg` only, at most 5 MB, and its INSERT policy admits an object only at the upload path of the caller's own pending, unsent image. There is no UPDATE or DELETE policy, so an upload cannot be swapped after it is sent.
3. The message is sent with `image_id`. The INSERT policy admits it only through `private.dm_image_send_admitted`: the `dm_images` gate is open, the image is the sender's, pending, unsent and uploaded, and the conversation is **not a request**: a follow edge either way (or a coaching link), or a request the recipient accepted. A pending request carries text only, from either side (the stricter default). A trigger links the image to that one message (unique) and queues a `dm_image_process` job.
4. The Go worker decodes the upload (JPEG or PNG, at most 40 megapixels, checked from the header before decoding), draws it onto a fresh canvas and writes a new JPEG to `{owner}/{image}.jpg`, then marks the row `ready` with its size, or `rejected`. Re-encoding keeps nothing but pixels, whatever segment or chunk a file hid metadata in.
5. Nobody, the sender included, can read image bytes until the row is ready: the bucket's SELECT policy admits only the re-encoded object of a ready image whose message the reader can read and that is not unsent. Clients read it through a 10-minute signed URL (`DM_IMAGE_SIGNED_URL_SECONDS` / `kDmImageSignedUrlSeconds`), never a public one, and keep it only in memory.

| | Web | Mobile |
|---|---|---|
| Attach | `dm-attach-photo` beside the composer while `dm_images_enabled()`; a preview with Remove (`dm-photo-draft`) | the composer's attach button, same gate |
| Pending | "Preparing photo…" (`dm-photo-pending`), re-checked every 4 s | the same |
| Ready / rejected | the image (`dm-photo`) / "This photo couldn't be sent." | the same |
| Refused send | `messages.photoSendNotAllowed`, one sentence that does not reveal a block | the same |

**Unsend, deletion, retention and reports.** Unsend detaches the photo; the purges and the sender's account deletion delete its message; either way the image row is deleted unless a report holds it (`private.dm_image_release`), and an upload never sent is deleted after a day (`dm-images-housekeeping`). Deleting an image row queues a `dm_image_orphan_sweep` job that erases its bytes through the Storage API (a `storage.objects` row delete would leave them, § 1049); the nightly job also queues a backstop sweep of every object no row names. A report filed on a photo message snapshots it (`reports.snapshot_image_id`), which keeps the image past an unsend or the sender's deletion until the report itself is purged; an admin reads it through `admin_dm_report_image_path` and the bucket's report clause. `delete-account` does not prefix-drain `dm-images`, because a drain would destroy report-held evidence: the row-driven erase does it instead. Both exports carry the subject's own `direct_message_images.json` and re-encoded photos under `storage/dm-images/`.

**Gate.** `private.feature_flags` `dm_images`, which no migration writes: prod refuses uploads and photo sends until the pre-deploy review in [deployment.md](../ops/deployment.md) opens it.

## Links

A URL in a message is drawn as its text plus a chip naming its domain, worked out on the client from the text alone (`dmTextSegments` / `dmLinkDomain`, the `dm_link` parity pair). **No preview is fetched**: there is no server-side request to aim at an internal address (no SSRF surface) and no request that tells a third party who opened the message. Only an `http(s)` URL with an ASCII host and no user-info becomes a link; a host in another script stays text (a look-alike domain is the phishing case the chip exists to expose), as does `user@host`. The anchor opens in a new tab with `rel="noopener noreferrer nofollow ugc"`; nothing is rendered as HTML. A fetched preview card was considered and not built ([decisions § 2451](../architecture/decisions.md)).

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

- pgtap: `dm_requests_setting_test.sql` (the switch refuses a first message and a pending request's next one, a follow edge and an accepted conversation still admitted, the setting unreadable by anyone else), `dm_reactions_test.sql` (RPC-only, one per participant, the key set, a non-participant P0002, a request and a block both ways answering one 55000, unsend and account deletion taking the reactions, delete-for-me hiding them), `dm_search_test.sql` (user C cannot find A and B's messages, literal `%` and `_`, unsent, blocked-by-me and deleted-for-me left out, invoker), `dm_images_test.sql` (the upload path, no read before ready, the send gate, a request carrying no photo either way, the link and the job, unsend and account deletion erasing, a report holding the image, the admin read, the orphan worklist, the gate), `dm_message_requests_test.sql` (a stranger, a pending member, a blocked member and an attendee with no club tie refused; a club request and an event-host request each pending for the recipient and accepted for the requester; no notification and no `seen_at` before acceptance, a notification after; the 3-message cap; accept and decline refusals; decline hiding the conversation and refusing the requester, a reply taking it back; decline-and-block; a block resetting accepted consent), `dm_edit_test.sql` (sender in the window, past the window, unsent, recipient, third party and a block all refused and read back unchanged; `original_body` withheld, snapshotted by a report, erased by unsend), `dm_read_receipts_test.sql` (no client reads `read_at`, receipts opted in and opted out both ways, withdrawal and no restore, the mark-read bound, `dm_threads()` still honouring `hidden_before`), `direct_messages_test.sql`, `dm_unsend_report_keep_on_delete_test.sql`, `direct_message_route_attachment_test.sql`, `dm_conversations_test.sql`, `dm_mark_unread_test.sql`, `dm_purge_hidden_test.sql` (the seen-message bound, the erase of what nobody can see, and a conversation whose only messages were the leaver's)
- web unit: `social/dm_reactions.test.ts`, `social/dm_link.test.ts`, `social/dm_image.test.ts`, `social/dm_search.test.ts` (each reads its key set or limits out of the migration), `social/dm_edit.test.ts` (the window, read from the migration), `social/dm_read_receipt.test.ts`, `core/data.test.ts` (the `DM_COLUMNS` read matches the grant, no `read_at`), `social/dm_thread.test.ts`, `core/visible_poll.test.ts`, `social/messages_inbox.test.ts`
- Playwright: `tests-e2e/messages/` — `dm-reactions.spec.ts` (pick, see from the other side, take off; none on a pending request), `dm-search.spec.ts` (own conversations only, opens the hit), `dm-photos-links.spec.ts` (the domain chip and its rel, markup kept as text, a photo sent pending and then shown from a signed URL, the requests switch persisting), `dm-requests.spec.ts` (a club member's first message, the cap, the Requests list and Accept; a confirmed Decline and the requester's refusal; Block from a request; a stranger refused), `dm-edit.spec.ts` (inline edit, the Edited mark on both sides, Edit offered only on the viewer's fresh messages, Escape cancelling, a refused save shown in place), `dm-thread-block.spec.ts` (block from the conversation), `dm-conversation-actions.spec.ts` (mute, archive, delete with undo, a message arriving during the undo window, the deleted-account notice), `dm-mark-unread.spec.ts` (mark as unread, the row and nav badge counting it, reopening clearing it), `dm-read-receipts.spec.ts` (Seen under the newest read message, an opt-out by either side hiding it), `dm-live-poll.spec.ts` (thread and inbox polls, driven by Playwright's clock), `coach-inbox-row.spec.ts` (the Coach row: no-consent, preview, AI label, unpin and hide persisting, the `/coach` redirect), plus the send, paging, permission, unsend/report and route-attachment specs
- Go: `exif/reencode_test.go` (no APP1, XMP, ICC or comment survives; the decode guard), `handler_dm_image_process_test.go`, `handler_dm_image_orphan_sweep_test.go`; Deno `export-data/backup_spec.test.ts`, `delete-account/wiring.test.ts`
- mobile: `dm_reactions_test.dart`, `dm_link_test.dart`, `dm_image_test.dart`, `dm_search_test.dart`, `direct_messages_screen_test.dart` (edit and message-requests groups), `dm_edit_test.dart`, `dm_read_receipt_test.dart`, `settings_read_receipts_test.dart`, `messages_coach_row_test.dart`, `messages_inbox_test.dart`, api_client `direct_messages_test.dart`

## Not built yet (issue #1216)

Realtime delivery and group conversations (split out to #1365, specced in [group_messages.md](group_messages.md), decisions § 2456). The group backend (slice 1, decisions § 2461) and the web surfaces (slice 2, decisions § 2463) are built behind the default-off `group_messages` flag; mobile (slice 3, decisions § 2468) mirrors them, and [group_messages.md](group_messages.md) describes both. Everything on this page is the 1:1 behaviour, which groups reuse: the bubble, reactions, photos, edit, unsend and report components, and the 10 s / 30 s polls. Two 1:1-visible changes came with slice 2 and reached the phone with slice 3: search hits in a group open the group, and a `message` notification naming a `conversation_id` opens the group (`/messages/group/<id>` on web, the group thread on mobile, including a push). The 1:1 bubble and edit dialog now live in `widgets/dm_bubble.dart` so the group thread draws the same ones. Since slice 1 every message read goes through `private.can_read_message`, so a reaction on, or a report of, a message the caller deleted for themselves answers not-found. Delete-for-me, mute, archive, mark as unread, unsend, report, read receipts, edit, message requests and the switch to turn them off, reactions, search, photos and link chips are built (the sections above). A fetched link preview card is deliberately not built (§ 2451). A group send names its conversation instead of a recipient (slice 1); club channels are slice 5.
