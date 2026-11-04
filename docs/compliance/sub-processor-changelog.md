# Sub-processor changelog

The list of processors that handle personal data on behalf of Threkir
evolves as we add features. Per GDPR Art 28(2), the data subject has
the right to object to a new sub-processor before it goes live. This
public changelog is the disclosure mechanism — every addition,
replacement, or material region change to a sub-processor must land
here at least **30 days before activation** in production.

If you object to a planned change you can:

1. Email `privacy@threkir.com` ([live](mailto:privacy@threkir.com))
   before the activation date listed below — we will pause the rollout
   while we discuss your case.
2. Delete your account via Settings → Account → Delete account before
   the activation date if no acceptable accommodation can be reached.

The current canonical sub-processor list lives at
[`sub-processors.md`](sub-processors.md). This file is the **history**;
the other file is the **snapshot**.

---

## 2026-05-26 — Initial publication

Baseline list as of 2026-05-26 — this is the snapshot any user who
created an account before today has tacitly accepted. Future entries
will diff against this baseline.

- **Supabase** — Postgres + Auth + Storage. Hosting region documented
  in [`sub-processors.md`](sub-processors.md). DPA:
  <https://supabase.com/legal/dpa>.
- **AWS** — S3 + CloudFront + Lambda + Route 53 (web hosting) +
  CloudWatch (logs). DPA: <https://aws.amazon.com/agreement/>.
- **Fly.io** — Go job worker + OSRM map-matching. Map-match jobs see
  GPS tracks transit. DPA: <https://fly.io/legal/dpa/>.
- **Anthropic** — primary AI Coach provider. DPA:
  <https://www.anthropic.com/legal/dpa>.
- **OpenAI** — fallback AI Coach provider when `COACH_PROVIDER=openai`.
  DPA: <https://openai.com/policies/data-processing-addendum>.
- **MapTiler** — base-map tiles + place search. IP + viewport per tile
  fetch. DPA: <https://www.maptiler.com/data-protection/>.
- **Open-Meteo** — elevation API for route building. Swiss controller
  (EU adequacy). Terms: <https://open-meteo.com/en/terms>.
- **Sentry** — error monitoring (US default). Consent-gated on the
  web; opt-out toggle in Settings (see roadmap). DPA:
  <https://sentry.io/legal/dpa/>.
- **RevenueCat** — subscription receipt validation. Forwards Stripe /
  App Store / Play receipts. DPA:
  <https://www.revenuecat.com/dpa/>.
- **Stripe / Apple IAP / Google Play Billing** — payment processors
  (downstream of RevenueCat). Stripe DPA:
  <https://stripe.com/legal/dpa>.
- **Strava / parkrun / Garmin Connect** — third-party integrations
  invoked only when the user explicitly connects them. OAuth scope is
  read-only for activity history.
- **Health Connect (Android) / HealthKit (iOS)** — on-device system
  services. Data lives on the device; we read only when the user opts
  in to the importer surface.
- **Google / Apple Sign-In** — federated identity providers (OAuth
  callback only; no data is shared with Google / Apple beyond what
  their respective sign-in flows require).
- **Supabase Auth email provider** — transactional emails (sign-up
  confirmations, password resets). Provider identity + region pinned
  in [`sub-processors.md`](sub-processors.md).

---

## 2026-06-09 — GraphHopper (self-hosted routing engine) — added (no new sub-processor)

* **What changes**: distance-targeted route-loop generation (`/api/routes/generate`, decisions §575) is served by a **self-hosted GraphHopper `round_trip` engine** running on our existing **Fly.io** infrastructure — the sibling of the self-hosted OSRM map-matcher. **No new third-party sub-processor is introduced**: the only processor in the chain is Fly.io, already disclosed since the 2026-05-26 baseline. Logged here for a complete audit trail, not as an Art 28(2) addition requiring the 30-day objection window.
* **Why**: the in-browser radius-bisect loop heuristic overshot the target distance on lopsided road networks; GraphHopper's `round_trip` hits the requested distance per engine call.
* **Activation date**: n/a — no new sub-processor, so no objection window applies. The feature ships on the normal release cadence.
* **Data categories affected**: route start lat/lng + target distance. **No data egress** — `GRAPHHOPPER_URL` is a server-only env (never `PUBLIC_`), so the browser never reaches the engine and the coordinates stay inside our infra (same posture as the self-hosted OSRM map-matcher).
* **Region**: `lhr` (London) — same Fly.io primary region as OSRM + the Go worker.
* **DPA**: Covered by the existing Fly.io DPA (<https://fly.io/legal/dpa/>); GraphHopper itself processes nothing on our behalf — we self-host it.
* **Opt-out path**: n/a — server-side route building, no personal-data egress; when the engine is unconfigured/down the client falls back to the in-browser OSRM heuristic.

---

## 2026-06-10 — graph_cycle map sidecar (self-hosted routing engine) — added (no new sub-processor)

* **What changes**: the v3 graph-cycle loop generator (`/api/routes/generate`, decisions §575) is served by a **self-hosted Go map sidecar** (`apps/graph_cycle`) running on our existing **Fly.io** infrastructure — a sibling of the self-hosted OSRM map-matcher + the GraphHopper engine. It parses the same regional OSM PBF into an in-memory foot graph and searches it for clean loops; `handleGenerate` tries it ahead of GraphHopper `round_trip`. **No new third-party sub-processor is introduced**: the only processor in the chain is Fly.io, disclosed since the 2026-05-26 baseline. Logged for a complete audit trail, not as an Art 28(2) addition requiring the 30-day objection window.
* **Why**: geometric generators (the retired v2 polygon path + `round_trip`) can't trace the neighbourhood loop on irregular street grids; the sidecar searches the real foot graph and finds it (decisions §575 amendment).
* **Activation date**: n/a — no new sub-processor, so no objection window applies. Ships on the normal release cadence once deployed.
* **Data categories affected**: route start lat/lng + target distance. **No data egress** — `GRAPH_CYCLE_URL` is a server-only env (never `PUBLIC_`), so the browser never reaches the sidecar and the coordinates stay inside our infra (same posture as the self-hosted OSRM + GraphHopper engines).
* **Region**: `lhr` (London) — same Fly.io primary region as OSRM, GraphHopper, + the Go worker.
* **DPA**: Covered by the existing Fly.io DPA (<https://fly.io/legal/dpa/>); the sidecar is our own code self-hosted — it processes nothing on our behalf as a third party.
* **Opt-out path**: n/a — server-side route building, no personal-data egress; when the sidecar is unconfigured/down the handler falls back to GraphHopper round_trip, then the in-browser OSRM heuristic.

---

## 2026-10-15 — Anthropic — new data category (no new sub-processor)

* **What changes**: Pro runners who use the plate-photo logger send one photo of a meal per request to Anthropic, which proposes food-diary entries.
* **Why**: photo-of-plate food logging (issue #1168 item 9, decisions § 1972).
* **Activation date**: not before the counsel / CISO sign-off on the v5 AI-disclosure copy; the feature ships default-off behind `PUBLIC_PLATE_PHOTO_ENABLED` / `PLATE_PHOTO_ENABLED`.
* **Data categories affected**: meal photographs (location and camera metadata stripped on the device and the server first; never stored by Threkir).
* **Region**: us-east-1 (unchanged).
* **DPA**: <https://www.anthropic.com/legal/data-processing-addendum> (unchanged).
* **Opt-out path**: don't use the plate-photo logger; consent is AI disclosure v5, withdrawable in Settings → Account.

---

## 2026-10-21 — Anthropic — new data categories disclosed (no new sub-processor)

* **What changes**: the AI Coach's context now names, in a new consent version, two data categories it had already been sending without any disclosure: a summary of the runner's recent gym sessions, and (only with health-data consent) a 7-day nutrition summary. Runners who accepted an earlier AI disclosure stop sending both until they accept v6; their Coach keeps working on the rest. The disclosure also names units, the weekly distance goal and the Coach personality, which the Coach already received and keeps receiving under earlier acceptances. Raw resting / max HR are withheld below v6 too, and the display name is no longer sent to the Coach at all (decisions § 2229).
* **Why**: the consent copy did not describe what the Coach sends (issue #1217, decisions § 2218).
* **Activation date**: the deploy that carries v6, after the owner's sign-off on 2026-10-22 (no counsel retained; the memo above is the review). Until this change deploys, prod keeps sending both categories under v1-v5 acceptances, as it has since the multi-modal work; the deploy itself stops that for every runner below v6, so the sign-off is worth doing promptly.
* **Data categories affected**: gym-session summaries (date, session name, exercise and set counts, total volume); 7-day nutrition summary (days logged, average calories, protein, carbs, fat), Art. 9 health data gated on health-data consent.
* **Region**: us-east-1 (unchanged).
* **DPA**: <https://www.anthropic.com/legal/data-processing-addendum> (unchanged).
* **Opt-out path**: don't accept AI disclosure v6 (the Coach still works without these categories); withdraw AI consent or health-data consent in Settings → Account.
* **Assessment (2026-10-22)**: the pre-v6 sending is assessed as a lawful-basis and transparency gap, not a personal data breach: it was an intended disclosure to a contracted processor, with no security failure, so Art 33/34 is not triggered. Gym summaries were sent from 2026-06-03, the nutrition summary (with health-data consent) from 2026-06-03, and units, goal, personality, display name and resting / max HR from 2026-05-03. Anthropic deletes API inputs within 30 days. Record: the 2026-10-22 entry in [`assessments.md`](assessments.md); memo `reviews/legal-ai-disclosure-v6.md`.

---

## Template for future entries

```
## YYYY-MM-DD — <Provider name> — <added | removed | replaced | region-change>

* **What changes**: <one-line description>
* **Why**: <product / cost / compliance reason>
* **Activation date**: <YYYY-MM-DD, at least 30 days after this entry>
* **Data categories affected**: <run tracks / chat history / push tokens / ...>
* **Region**: <provider region>
* **DPA**: <URL>
* **Opt-out path**: <feature toggle / account deletion / "no opt-out — strictly necessary">
```

---

Last updated 2026-05-26. The audit trail of edits to this file is the
git history of `docs/compliance/sub-processor-changelog.md`. If you
need a notarised log of changes prior to a specific date, email
`privacy@threkir.com`.

---

## 2026-11-02 — MapTiler — new data category; AWS Open Data Terrain Tiles — conditional fallback (no new sub-processor in threkir.com production)

* **What changes**: the 3D course preview on routes, races and runs loads elevation tiles along the course it shows. With a MapTiler key configured (production) they come from MapTiler's `terrain-rgb-v2` tileset — the same provider, the same IP + tile-coordinate data as the basemap. With no key (self-hosted / local / keyless builds; the release build refuses to ship without one) they come from the AWS Open Data Terrain Tiles bucket `elevation-tiles-prod.s3.amazonaws.com`.
* **Why**: a free 3D fly-over of a course (issue #1270, decisions § 2251).
* **Activation date**: the release that ships the preview. No objection window applies to the MapTiler change (an existing sub-processor, an existing data category). The AWS Open Data rung is not reachable from threkir.com production; if a deploy is ever configured keyless, list it here 30 days before that deploy and get the CISO / Security Analyst classification first.
* **Data categories affected**: requester IP and the tile coordinates of the course on screen (which locate the course, not the viewer). No account id, no track upload — tiles are requested by coordinate only.
* **Region**: MapTiler EU + global edge (unchanged); AWS us-east-1 for the keyless rung.
* **DPA**: MapTiler unchanged. The AWS Open Data bucket is a public request outside our AWS account, so no DPA applies; see [`sub-processors.md`](sub-processors.md).
* **Opt-out path**: don't accept the cookie banner and don't tap "Load map" in the preview — like every map, it loads nothing before one of the two.

---

## 2026-11-04 — MapTiler / AWS Open Data Terrain Tiles — the 3D course preview reaches logged-out visitors (no new sub-processor, no new data category)

* **What changes**: "Preview in 3D" is also offered on the public route share page `/share/route/[id]` (issue #1282), so a visitor without an account can now cause the elevation-tile requests the 2026-11-02 entry describes. Same providers, same data (requester IP + the tile coordinates of the course on screen).
* **Gate**: stricter than the signed-in surfaces. The dialog always shows its "Load preview" card on this page, even when the cookie banner was accepted; nothing is requested before that tap. *Corrected 2026-11-04 (decisions § 2337):* this entry first said the page's 2D map already worked this way. It didn't: with the banner accepted, the 2D map skipped its "Load map" card and rendered blank. Since PR #1289, the 2D map on both share pages (`/share/run/[id]`, `/share/route/[id]`) also waits for its own "Load map" tap on every view, banner or no banner, and nothing is requested before that tap. The course it draws is the privacy-clipped line the page already shows (`clip_route_for_viewer`), and the page offers no video export.
* **Activation date**: the release that ships it. No objection window applies (existing sub-processors, existing data category). **CISO / Security Analyst to confirm before release**, since it extends a third-party request to an unauthenticated audience.
* **Opt-out path**: don't tap "Load preview" (or "Load map" for the 2D map).

## 2026-11-04 — Anthropic — every single-shot AI prompt is now listed field by field (no new sub-processor, no new data category)

* **What changes**: the Anthropic row in [`sub-processors.md`](sub-processors.md) listed the AI Coach payload in full but the other prompts only in part, or not at all. It now lists, field by field, what route-describe, route-request, plan-request, season-request, plan-edit and plate-photo send, read from each prompt's own builder (`AI_PROMPT_DISCLOSURES`, decisions § 2338), so a prompt that gains a field fails CI until the row names it. Three corrections to what was sent or listed:
  * **route-describe** sends a route's name only when the viewer owns the route or it is public. Before this release it sent the name of any route the viewer could open, including a club-mate's or a route shared with them. It also sends the viewer's distance unit and the name of their language, so the paragraph comes back in both. It does not send the route's distance band, which the previous wording listed. The route's coordinates stay on the server; only the shape derived from them is sent.
  * **route-request** no longer sends a typed or map-picked start point. The builder labelled such a start with its coordinates to four decimals, and that label went to Anthropic as the "place label", although the consent copy says "never your precise coordinates".
  * **plate-photo** also sends the optional note the runner adds to a meal photo, which the row did not list.
* **Gate**: unchanged. Each request is refused without the AI disclosure version its prompt requires, and every prompt falls back to the non-AI path when the model is not called.
* **Activation date**: the release that ships PR #1289. No objection window applies (existing sub-processor, existing features, and each change sends less or is now listed). **Security Analyst / CISO to confirm before release** that the consent bullets cover each listed field (route-AI disclosure v2 does not name the unit or the language, the plan bullets do not name the current date, the plan-edit bullet names dates, types and distances but not durations, phases, weekly distance or completion state, and the plate-photo bullet does not name the note), and to decide whether the start coordinates route-request sent before this release need any further action.
* **Opt-out path**: don't use the AI route, plan and plate-photo features; withdraw AI consent in Settings → Account.
