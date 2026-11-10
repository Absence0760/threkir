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
