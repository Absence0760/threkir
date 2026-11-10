# Official content: verified organisers

The spec for issue #1190, "Official content". This document covers the **verified organiser** model and the **verification request flow** that has shipped. The race-course slice (claiming a race listing, linking its course) is in [race_calendar.md](race_calendar.md) (#1297, decisions § 2381); heatmap and discovery ranking is in [api_database.md § Discovery RPCs](../backend/api_database.md); seeding and the onboarding import step are tracked on the issue.

## The trust model

- **The verified club is the unit of trust.** Threkir's own official account is an ordinary verified club with no special case in code.
- **"Official" is derived, never stored per row.** A route, plan, gym routine, challenge or session plan is official when its `club_id` names a verified, public, unhidden club and its author is an active owner or admin of that club (`private.is_official_publisher`, migration `20271021000030`, decisions § 2228). Revoking the club's badge removes it from everything at once.
- **Featured is separate.** `routes.is_featured` is a Threkir editorial pick from anyone; official is publication by the verified organiser.
- **Verification is free and can never be bought.** There is no member-count threshold, so a new official organiser can verify on day one.

## Verification requests (migration `20271120000004`, decisions § 2398)

### Who does what

| Actor | Can |
|---|---|
| Club owner | Submit a request, prove the domain (check DNS / file, send the email link), withdraw a pending request |
| Club admin | See the club's requests and status (read-only) |
| Site admin (`app_admins`) | See the queue, approve, reject with a reason, revoke a badge with a reason, read a club's history |
| Anyone with the mailed link | Confirm the email proof |

### The request

The owner opens the **Official verification** card on the club page (`ClubVerificationCard.svelte`, rendered for the owner and admins), names the organisation the club officially represents and optionally adds a note for the reviewer. The **claimed domain is the host of the club's website link** (`private.club_website_domain`: lower-cased, scheme, credentials, port, path and one leading `www.` removed; an IP literal is refused). A club with no website is asked to add one in Edit club first. One request can be live per club (a pending application or the approval in force), and each request gets its own random 128-bit token.

### Proof (any one)

| Method | What the owner publishes | Checked by |
|---|---|---|
| DNS TXT | `threkir-verification=<token>` at `_threkir-verification.<domain>` (or the apex) | `club-verification` Edge Function, "Check now" |
| `.well-known` file | `https://<domain>/.well-known/threkir-verification` with `threkir-verification=<token>` (or the bare token) on a line of its own | `club-verification` Edge Function |
| Email | Nothing: the owner names the part before the @ (`hostmaster`, `info`, …) and a one-time link goes to that address at the domain | the `club_verification_email` job; confirmed at `/club-verification/confirm` |
| Manual review | Anything a reviewer can check by hand (a link to the club from the official site or socials) | the reviewer, who must write a note |

The Edge Function reads DNS over HTTPS and fences the file fetch against SSRF (https and port 443 only, the claimed domain or its `www.` only, every hop's addresses screened, no automatic redirects, one deadline, a 4 KiB cap). The fence and its one accepted residual are decisions § 2399.

The email link carries a 192-bit token in the URL fragment, single use, valid 24 hours; the database keeps only its SHA-256. The landing page confirms on a click, never on load. Three emails a request a day at most.

A found proof is recorded on the request (`proof_method`, `proof_verified_at`, `proof_detail`). It does not verify the club.

### Review

`/admin/club-verification` lists **Pending**, **Verified** (every verified club, including ones verified before requests existed) and **Closed** (rejected, revoked, lapsed, withdrawn in the last 180 days). Each row shows the organisation, the domain, the club website, the owner, the proof found, the club's note and a reminder to check for lookalike domains. Every action is behind a dialog:

- **Approve**: needs the club's website still on the requested domain; a note is required when no automated proof was found (recorded as `manual`). Sets `clubs.is_verified`.
- **Reject**: a reason the owner reads on the card.
- **Remove badge** (revoke): a reason the owner reads; works by club, so it also removes a badge granted before requests existed.
- **History**: the club's audit log.

Each status change notifies the club's owner and active admins (`club_verification`, in-app, push and email), with no reviewer named.

### Keeping the badge honest

- **Lock.** Renaming a verified club, changing its slug, or moving its website to another domain drops the badge until it is reviewed again (`clubs_verification_lock`). The owner is warned in Edit club.
- **Re-check.** Hourly, `club-verification-recheck` re-runs the DNS and file checks for clubs approved on them, each about once a day. Three failures in a row drop the badge and mark the request lapsed (`proof_missing`), which notifies the club; the owner can request again. Clubs proven by email or manual review are not re-checked. Arming the schedule is one line in [`apps/backend/ops/prod_config.json`](../../apps/backend/ops/README.md) (`"club_verification_recheck"` under `cron_urls`), which the next backend release applies and verifies; see [deployment.md](../ops/deployment.md).

### Audit and data

`club_verification_audit` records submit, withdraw, email sent, proof found, re-check failed, approve, reject, revoke and lapse, with the actor (null for the system) and a snapshot of the club name. It is append-only. The requests a user submitted and the actions they took are in both data exports. Schema, RLS and RPCs: [api_database.md § Club verification RPCs](../backend/api_database.md).

### Platforms

Web is the whole flow. Mobile (Android and the iOS twin) shows the owner and admins a read-only status card on the club screen and points to the web; the request and review are web-only by decisions § 24. The notification opens the club on every platform.

## What the badge lends

The provenance labels (official / verified source / traced / community) on content, race listings and their courses, and organiser course alerts, are specified in [provenance.md](provenance.md) (decisions § 2406 / § 2407).

## Not built yet

- Name dispute / takedown path tied to the report flow.
- Trusted verifiers (a federation verifying its member races) — later, not v1.
