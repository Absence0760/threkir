# Data Protection Impact Assessment (DPIA)

GDPR Art 35 requires a DPIA whenever a processing activity is "likely to result in a high risk to the rights and freedoms of natural persons". The EDPB's WP248 guidance flags live-location tracking and biometric/health processing as automatic DPIA triggers — this project does both.

**Status**: scaffold. Counsel must sign off before publishing the live build.

## Scope of this DPIA

| Processing activity | Why a DPIA is mandatory |
|---|---|
| **Live GPS recording** (`run_recorder` package → `runs.track_url`) | Continuous high-precision location data. WP248 explicit trigger. |
| **Heart rate from BLE chest strap** (`ble_heart_rate.dart`) | Biometric / health data; Art 9 special category. |
| **HealthKit / Health Connect import** | Inbound aggregation of health data from third-party fitness apps. |
| **AI Coach** (`apps/web/src/lib/coach/handler.ts`) | Automated processing of health data sent to a US sub-processor for response generation. |
| **Live spectator tracking** (`live_run_pings` → web `/live/[id]` + Go live-hub) | Real-time location data shared with public viewers. |
| **Public route + run sharing** (`is_public = true` rows) | Voluntary publication of historical location data. |
| **Share-link attribution** (`private.share_link_daily`, `signup_share` sign-up metadata, decisions § 2268) | Not a WP248 trigger on its face: aggregate per-link counters with no visitor identifier, and a sign-up's source link recorded on the person's own sign-up. Listed so the CISO / Security Analyst can confirm whether sign-up attribution is a new purpose before the `share_attribution` gate opens ([deployment.md](../ops/deployment.md)). |
| **First-touch sign-up source** (`private.signup_sources`, `signup_source` sign-up metadata, decisions § 2350) | Not a WP248 trigger on its face: the campaign tags or referring site of the person's own sign-up, kept with their account and read only in aggregate by the operator. The capture is a first-party sessionStorage entry sent only with a sign-up. Listed so the CISO / Security Analyst can confirm the purpose and the storage before the `signup_source` gate opens ([deployment.md](../ops/deployment.md)). |
| **Coach assistant** (`apps/web/src/lib/coach/assist/`, issue #1215 Phase 4) | A third party's data sent to a US sub-processor at someone else's request: a coach asks for a draft, and the ATHLETE's messages with that coach, plan and recent runs go to Anthropic under the coach's account. Default-off (`COACH_ASSIST_ENABLED` / `PUBLIC_COACH_ASSIST_ENABLED`) until this section is signed off. See [Coach assistant](#coach-assistant-issue-1215-phase-4) below. |
| **Shared AI Coach answer** (`share_coach_message`, issue #1215 Phase 3) | Not a WP248 trigger: the athlete copies paragraphs of their own AI answer to their coach; nothing new goes to Anthropic. Listed so the CISO can confirm the AI labelling before the `coach_share` gate opens. |
| **Group conversations, club channels and Realtime delivery** (`direct_messages` rows with no recipient, `conversation_participants` membership, issue #1365, decisions § 2456 / § 2461) | Not a WP248 trigger on its face, but the audience of a message grows from one recipient to up to 32 group members (later, a whole club), and free text can carry incidental health data. Default-off (`group_messages` flag) until this section is signed off. See [Group conversations](#group-conversations-club-channels-and-realtime-issue-1365) below. |

## Coach assistant (issue #1215 Phase 4)

**Status: draft for the CISO + counsel. The feature ships with both halves of its flag off, and this section's sign-off is the pre-deploy gate ([deployment.md](../ops/deployment.md#coach-assistant--after-the-ciso--counsel-sign-off-and-the-dpia-update)).**

- **What is processed, and whose.** The athlete's last 20 messages with that one coach since the coaching link began (text and time; answers the athlete shared from their own AI Coach are left out), the plan they are on (name, goal race and target time, dates) with the next 14 days of workouts (date, type, distance or time, pace, done or skipped), and their 10 most recent activities (date, distance, time, activity type). No heart rate, no run metadata or notes, no route or location, no nutrition, no date of birth: no Art. 9 field is read. The coach's own request text (up to 500 characters). The authoritative list is `COACH_ASSIST_REGISTRY` in `apps/web/src/lib/coach/assist/context.ts`, which throws on any field it does not register.
- **Lawful basis.** The athlete's consent, Art. 6(1)(a), given per coaching link (`coach_athletes.ai_assist_consent_version`, written only by the athlete through `set_coach_ai_assist_consent`, off by default, withdrawn with one tap, cleared when the link ends). The coach's own consent to the purpose is AI disclosure v7. A coach cannot grant the athlete's consent: the invite INSERT policy refuses a consented row and there is no client UPDATE path.
- **Necessity and proportionality.** A draft is requested by the coach for one athlete at a time, is never stored by Threkir, and is shown only to that coach, who edits and sends it as themselves. The sent message is marked AI-assisted on both sides. The lanes are bounded (20 messages of at most 1,000 characters, 14 days, 10 runs) and cover what a reply about training needs.
- **Risks and mitigations.**

| Risk | Severity | Likelihood | Mitigation | Residual |
|---|---|---|---|---|
| An athlete's messages mention health or injury, which then reaches Anthropic | Medium | Medium | The athlete's consent copy names "your recent messages with this coach"; the athlete chooses what they write and can withdraw; no structured health field is read | Medium: free text can carry Art. 9 data. Counsel to decide whether the per-link consent must also meet Art. 9(2)(a) |
| A coach uses the assistant without the athlete knowing | High | Low | Off unless the athlete turned it on for that link; enforced server-side on every call; every assisted message is marked | Low |
| Prompt injection through the athlete's messages | Low | Medium | The context is passed as JSON and the system prompt treats it as data; the draft is text only the coach sees and edits before anything is sent | Low |
| The draft is mistaken for the coach's own judgement | Medium | Medium | "AI-assisted" marker on both sides; the coach must send it themselves | Low |
| Retention at the sub-processor | Medium | High | Anthropic's 30-day API retention, no training (see sub-processors.md); Threkir stores no draft | Medium, as for the Coach |

## Group conversations, club channels and Realtime (issue #1365)

**Status: draft for the owner as controller (condition C12 of the security review, `reviews/security-group-messages-realtime.md`). Slice 1 (the backend, migrations `20271216000001`–`…10`) is built behind the default-off `group_messages` flag; club channels (slice 5) and Realtime (slice 4) are not built, and are assessed here as specced so the section does not need rewriting when they land. The owner's sign-off on #1097 is the pre-deploy gate ([deployment.md](../ops/deployment.md)).**

- **Purpose.** Let runners talk in a shared space: a group of up to 32 people (pending invites included) that a runner creates and invites others to, and, later, one opt-in members-only channel per club. Realtime would only tell an open thread that something changed, so it re-reads; it is a delivery signal, not a new copy of the data.
- **Lawful basis.** Art. 6(1)(b), performance of the service the member asked for, as for 1:1 messages. Joining is always an invite the invitee accepts (D1); nobody is put in a group without acting. No new purpose, no profiling, no AI processing: group content is outside the coach-assist and coach-share lanes (§ 2447), which read only the coaching pair's own thread. Health data a member volunteers in free text (an injury) is incidental, as in 1:1; no structured health field is read or written.
- **Data categories.** Message content in a shared space (text, photos re-encoded without location or camera details, reactions, edit and unsend state); membership (`conversation_participants`: state, role, who invited whom and when, joined and left times, who removed whom, read position, mute / archive / hide stamps); the group's title and creator; pending invites (invitee, inviter, time). Club channels would add the club link, the posting mode and a club-admin hide log. Realtime would add no stored data: payloads carry no body, photo path or sender name (C8).
- **Recipients.** The group's active members, and only for messages sent from the moment they joined (D3, the server stamps `joined_at`); a re-join does not restore an earlier window (C3). An invitee sees only the title, the inviter and the member count (C5). A member who leaves or is removed reads no one else's messages from then on (D12). Site admins read a message only through a report's snapshot. No new sub-processor: data stays in Supabase (see [sub-processors.md](sub-processors.md)). A club channel would be readable only by the club's active members, never by anon or through `/share/club`, whatever the club's `is_public` (C7).
- **Retention, as built.** The 2-year window on `direct_messages.created_at` applies to group messages unchanged. The daily `purge-stale-direct-messages` run also erases a group message once its sender has hidden it and no active member whose window contains it can still see it, drops a group with no active member together with its messages, and retires an invite unanswered for 14 days (deleted, or marked left if the invitee had written there). A report snapshot follows the reports windows (6 months closed with no action, 12 months after action). Rows in [retention.md](retention.md) (direct messages, conversations, conversation state, the purge job).
- **Data-subject rights in a shared space.** *Erasure (Art 17):* deleting an account erases every message the member sent, in every group, and their membership rows; their reactions go with them; group ownership passes to the longest-standing admin, else member. Leaving or being removed erases nothing, because the member wrote to that audience; they can still unsend their own messages after leaving (D11). *Access and portability (Art 15 / 20):* the export carries the member's own sent group messages, their memberships (role, joined, left, invited by) and their own reactions and photos, and **not other members' messages** (D5). Art 20(1) covers data the subject provided, and Art 20(4) and Art 15(4) protect the other members. This differs from the 1:1 export, which includes messages addressed to the subject; the privacy notice says so.
- **Risks and mitigations.**

| Risk | Severity | Likelihood | Mitigation | Residual |
|---|---|---|---|---|
| A non-member, an invitee, or a left or removed member reads a group message through one path the membership rule missed | High | Medium | One read rule, `private.can_read_message`, behind the SELECT policy, reactions, photos and the `dm-images` Storage policy; no RPC restates it (C1); the pgtap matrix covers every role against every read path and RPC (C2) | Low |
| A message sent in the instant a member is removed reaches them | Medium | Low | Per-member transaction advisory lock between send and remove / leave / accept, pinned by `group_messages_race_test.sql` (C3) | Low |
| A newcomer reads what was said before they joined | Medium | Medium | Window starts at the server-stamped `joined_at` (D3); a re-join does not restore it (C3) | Low |
| Members gang up to hide a fourth member's messages | Medium | Low | No auto-hide in groups (D10); reports go to the site admin queue only, gated on the read rule (C4) | Low |
| Probing membership or group existence through RPC errors | Medium | Low | Uniform P0002 from every group RPC; invitee view limited to title, inviter and count; rate-limit buckets on create and invite (C5) | Low |
| Being added to a group by a stranger | Medium | Medium | Invite only from someone who could already message you 1:1 (D1), and nothing is visible until you accept; unanswered invites expire after 14 days | Low |
| A club channel exposed beyond the club, or club admins learning who reported whom (slice 5) | High | Low | Active members only regardless of `is_public`, tested against anon and non-members (C7); admin hides logged admin-only and visible to the sender, reporter identity never shown to club admins (C6) | Low, once built and tested |
| A Realtime broadcast leaks content or reaches the wrong subscriber (slice 4) | High | Low | Content-free payloads (C8); per-user private topics, SELECT-only `realtime.messages` policy, tested against the project's actual public-access setting (C9); fan-out only to active participants (C10); polling keeps working without the socket (C11) | Low, once built and tested |
| Export or deletion misses a new column | Medium | Low | Both export rails and the deletion path extended in slice 1; the new columns are in both audit command lists (`data-export-completeness`, `account-deletion-completeness`) | Low |
| Incidental health data in a larger audience | Medium | Medium | User-volunteered free text, as in 1:1; the composer names the audience; no AI processing and no structured read | Medium, as for 1:1 messages |

- **Sign-off.** Owner as controller, recorded on #1097 at flag-open. Pending.

## Necessity + proportionality

For each activity, the standard test:

1. Is the personal data **necessary** for the stated purpose? — yes (location is the product).
2. Is it **proportionate**? — yes. Location capture is bounded to an explicitly-initiated recording session. **Verified (2026-06-14):** `ACCESS_BACKGROUND_LOCATION` is requested at runtime with an in-app rationale and only *after* foreground location is granted (`lib/background_location_nudge.dart` + `run_screen._maybeNudgeBackgroundLocation`), never at first launch; the only promoted foreground service is geolocator's `GeolocatorLocationService` (`foregroundServiceType="location"`), and no WorkManager job runs as a location foreground service (`AndroidManifest.xml` comments confirm `FOREGROUND_SERVICE_DATA_SYNC` is unused). There is no background-location capture outside an active recording.
3. Is there a **less-intrusive alternative**? — for indoor / treadmill runs the app already supports a no-GPS mode; surface it more prominently.

## Risks identified

| Risk | Severity | Likelihood | Existing mitigation | Residual |
|---|---|---|---|---|
| Home / work address inferred from recurring run start points | **High** | High | Privacy zones (decisions §33) — non-owner viewers see clipped tracks via `clip_track_for_user` | Medium — user must enable + configure |
| Live spectator URL guessing reveals real-time location | High | Low | Anon JWT enforced server-side by `apps/job_worker/internal/livehub/auth.go` for non-public runs | Low |
| Coach prompts sent to Anthropic include HR + dob + gender | Medium | High | Anthropic DPA + no-training-on-customer-data commitment; data retained 30 days | Medium — disclose to user before use |
| Sentry breadcrumbs leak signed-URL tokens | Medium | Low | `apps/web/src/lib/sentry/redact.ts` strips signed URLs server- and client-side | Low |
| Apple Watch / Wear OS run continues recording when paired phone is locked | Medium | Medium | Foreground service notification + wakelock — user is aware via lock-screen UI | Low |
| Background-location permission granted on Android leaks beyond recording | High | Low | `ACCESS_BACKGROUND_LOCATION` requested at runtime with rationale (only after foreground grant) + Play Console justification; capture verified recording-only (see Necessity §2, 2026-06-14) — no background-location use outside an active recording session | Low |
| Public route's `waypoints` reveal home start point | High | Medium | Privacy zones clip the path in public render | Medium — depends on user opt-in |
| Coach chat history (`coach_messages`) accumulates without auto-purge | Medium | High | 18-month purge via `purge-stale-coach-messages` cron (migration `20260922_001_data_retention_purge_jobs.sql`) | Low |
| Strava token leaked after account deletion | High | Low | Strava `/oauth/deauthorize` called from `delete-account/index.ts`; outcome recorded in `deletion_audit_log.third_party_outcomes.strava_deauth` (Art 17(2) evidence) | Low — call site confirmed + per-call outcome auditable |

## Mitigations to implement

Items the DPIA itself flags for action:

1. ~~**Coach-message retention**: add a `pg_cron` purge job; expose retention period in Privacy Policy + Settings.~~ **Done** — migration `20260922_001_data_retention_purge_jobs.sql` + privacy-policy entry, 2026-05-26.
2. ~~**Sentry user-opt-out toggle** in Settings → Privacy.~~ **Done** — web `/settings/privacy` has a "Privacy & telemetry" card bound to `consent.set()` (the existing cookie-banner consent primitive). Mobile twin mirrors via `Settings → Privacy → Send error reports`. The hooks (`hooks.server.ts` + `hooks.client.ts`) already gate Sentry on this state; the toggle adds the post-acceptance withdrawal path required by Art 7(3) / Art 21.
3. ~~**Live-ping retention**: confirm Postgres purge + Redis TTL both deliver the documented window.~~ **Done** — `cleanup_stale_live_run_pings()` cron runs every 15 min and purges pings older than **48 h** (window widened from 4h in `20270119_001_live_run_pings_retention.sql`; schedule in `20260602_001_pg_cron_schedules.sql`); the Go live-hub Redis TTL is **24 h** (`RedisHub.ttl()`'s default), i.e. shorter than the Postgres window rather than equal to it — this line claimed they matched, which the code has never done. See [retention.md](retention.md).
4. ~~**Strava deauthorize on delete**: verify the call site in `delete-account/index.ts`.~~ **Done** — confirmed; outcome now recorded in `deletion_audit_log.third_party_outcomes` (Art 17(2) evidence), migration `20260928_001_gdpr_dsar_closeouts.sql`.
5. **Privacy-zone first-run prompt**: on the first run that records within (e.g.) 200 m of the registered home location, prompt the user to configure a privacy zone.

## Sign-off

| Role | Name | Date |
|---|---|---|
| Controller | TODO | TODO |
| DPO (if appointed) | TODO | TODO |
| Counsel | TODO | TODO |

A DPIA is a living document. Trigger re-review on:
- New personal-data column (use `/audit/data-export-completeness` to find).
- New sub-processor with health-data scope.
- A material change to recording behaviour (e.g. always-on background tracking).
