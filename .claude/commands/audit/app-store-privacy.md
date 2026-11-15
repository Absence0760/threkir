---
description: Verify iOS Privacy Nutrition Labels + Play Data Safety + manifest disclosures match what the binaries actually do
---

Audit App Store + Play Store privacy-disclosure surfaces.

## Goal

Both stores reject submissions on privacy mismatches more often than any other category. The binary collects HR + precise location + photos; the App Store Connect / Play Console privacy form must say so, and the matching `Info.plist` / `AndroidManifest.xml` / `PrivacyInfo.xcprivacy` / `health_permissions.xml` must match.

## What to check

The inventory lives in the tree, not here: `docs/compliance/store_declarations.json` (one Play record, `com.threkir.app`, for phone + Wear OS; one App Store record for iPhone + Apple Watch) and its guard `node scripts/check_store_declarations.mjs`, plus `node scripts/check_ios_native_declarations.mjs`. The `app-store-privacy-auditor` agent runs both and judges what they cannot:

- Every `[FAIL]` from the guards, and every `[OWNER TO CONFIRM]` console state (`unknown` / `pending`) that blocks the next release
- Whether each registry entry names the right console form under current policy
- Privacy label / Data safety vs what the binaries do; no tracking; HealthKit never used for advertising (Guideline 5.1.3)
- Encryption export, target SDK, in-app + web account deletion, Sign in with Apple (Guideline 4.8)
- Subscription disclosure (price, period, renewal, cancel, restore purchases) and age rating

## Report

- **Critical** — known reject trigger.
- **High** — disclosure-mismatch with binary behaviour.
- **Medium** — out-of-date string / manifest entry.
- **Low** — sloppy phrasing.

End with **clean** list of disclosure surfaces that look correct.

## Delegate to

Use the `app-store-privacy-auditor` agent: `"Audit App Store + Play Store privacy disclosures across mobile_ios, mobile_android, watch_ios, watch_wear."`

Read-only. Findings only. Always end legal claims with "verify against the current App Review Guidelines / Developer Program Policies" — those evolve quarterly.

## Output → `reviews/`

Persist the findings to `reviews/audit-app-store-privacy.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
