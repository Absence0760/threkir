# .claude/ — Claude Code tooling

Project-specific agents and slash commands wired into Claude Code sessions for this monorepo (Flutter mobile + native watch + SvelteKit web + Supabase + Go worker). Each agent and command targets concrete files, conventions, and invariants of *this* codebase — `apps/mobile_{android,ios}/`'s byte-identical twin, `runs.metadata` jsonb registry, the L0–L4 layered-resilience contract, the CHECK ↔ TS-union pairs, etc.

Browse [`agents/`](agents/) and [`commands/`](commands/) for the full list; the index below is a quick map.

## Agents (`agents/`)

Multi-step, read-only or edit-capable specialists. Most are invoked by a slash command in `commands/`, but a few are used directly (e.g. `mobile-twin-mirror`, `shared-library-syncer`).

Agents are grouped into subfolders by team. Claude Code discovers them recursively and keys them by the frontmatter `name:`, so the folder is purely organisational and two files may never declare one name (`ci_workflow_guards.test.ts` fails the PR if they do).

### `engineering/` — the gate agents for a diff

| Agent | What it does |
|---|---|
| [`code-reviewer`](agents/engineering/code-reviewer.md) | Reviews the working diff against `decisions.md` ADRs, the layering contract, twin invariant, paywall gates, fail-closed defaults, comment/abstraction discipline. Invoked by `/safe-edit` and `/check`. |
| [`test-gap-checker`](agents/engineering/test-gap-checker.md) | Reads the working diff and reports missing unit / e2e coverage per `docs/architecture/conventions.md § Test hygiene`. |
| [`doc-hygiene-checker`](agents/engineering/doc-hygiene-checker.md) | Surveys the doc set listed in `CLAUDE.md § Docs hygiene` against the diff and reports which need updating. |
| [`metrics-reviewer`](agents/engineering/metrics-reviewer.md) | Judges changes to derived numbers (pace, GAP, VDOT, training load, HR zones, calories, age grade, nutrition targets, the trigger caches) by the published method, units, day boundaries and the TS / Dart / Rust parity rails. `/check` runs it as a fourth lane when the diff touches one. |
| [`migration-coordinator`](agents/engineering/migration-coordinator.md) | Applies a new Supabase migration locally, runs both type generators, runs the CHECK ↔ TS-union guard. Invoked by `/safe-migration`. |
| [`mobile-twin-mirror`](agents/engineering/mobile-twin-mirror.md) | Mirrors `apps/mobile_android/lib/`+`test/` edits into `apps/mobile_ios/` and verifies the byte-identical invariant (decisions §39). Run after every Dart edit. |
| [`shared-library-syncer`](agents/engineering/shared-library-syncer.md) | Detects divergence on the registered TS↔Dart parity pairs. |
| [`metadata-key-keeper`](agents/engineering/metadata-key-keeper.md) | Verifies every `runs.metadata.<key>` access in a diff is documented in `docs/backend/metadata.md`. |

### `design/` — UI quality

| Agent | What it does |
|---|---|
| [`ui-polisher`](agents/design/ui-polisher.md) | Redesigns a page / screen / component across web (SvelteKit), mobile (Flutter twin), Wear OS, watchOS. Invoked by `/polish-ui`. |
| [`ux-critic`](agents/design/ux-critic.md) | Read-only verdict on whether a whole surface is something someone will enjoy using. Invoked by `/ux-critique`. |

### `audit/` — read-only sweeps behind `/audit/*`

| Agent | What it does |
|---|---|
| [`repo-security-auditor`](agents/audit/repo-security-auditor.md) | RLS / SECURITY DEFINER / Edge Function / Storage / XSS / paywall sweep. Backend for most security audits. |
| [`compliance-auditor`](agents/audit/compliance-auditor.md) | GDPR / CCPA / DSAR / cookie-consent / regional-availability / accessibility posture. |
| [`app-store-privacy-auditor`](agents/audit/app-store-privacy-auditor.md) | iOS Privacy Nutrition Labels + Play Data Safety + Wear OS + watchOS disclosures against what the binaries do. |
| [`data-architecture-auditor`](agents/audit/data-architecture-auditor.md) | Every persistence layer (Postgres, mobile file-stores, watch stores) against data-architecture standards. Invoked by `/audit/db-design`. |

### `i18n/` — translation

| Agent | What it does |
|---|---|
| [`i18n-translator`](agents/i18n/i18n-translator.md) | Translates a JSON batch of ARB / web-catalogue keys into one locale, reusing the terms that locale already uses. Never edits catalogues. |
| [`i18n-checker`](agents/i18n/i18n-checker.md) | Reviews a translator batch for meaning, placeholders, plurals, register and term consistency; names the guards that will fail the PR. |
| [`languages/`](agents/i18n/languages/) | One guide per locale (de, fr, es, ja, pt-PT, pt-BR): register, style authority, running glossary, what not to translate. Both agents read it first. |
| [`i18n-readiness-auditor`](agents/i18n/i18n-readiness-auditor.md) | Hard-coded English, en-US formatting, missing RTL, missing Accept-Language across web + mobile + watch. Invoked by `/audit/i18n-readiness`. |

### `legal/` — pre-counsel work (not legal advice)

| Agent | What it does |
|---|---|
| [`intl-legal-doc-reviewer`](agents/legal/intl-legal-doc-reviewer.md) | Sweeps the legal pages (ToS, Privacy, Cookie Notice, Refund) against GDPR / UK GDPR / LGPD / PIPEDA / Quebec Law 25 / Australian Privacy Act / PIPA / DPDPA + EU / UK / AU consumer law. |
| [`legal-researcher`](agents/legal/legal-researcher.md) | Goes deep on one law question about threkir in the jurisdictions it turns on, from primary sources, and writes a memo to `reviews/`. |

### `personas/` — bug hunters

Read-only persona agents (runners, coaches, organisers, race-specific crews, watch and Connect IQ users) that walk the app as one kind of person and report a ranked triage list. Grouped further by race (`races/`), the custom watch (`custom_watch/`) and Connect IQ (`garmin_ciq/`).

## Commands (`commands/`)

User-invocable slash commands. Most chain one or more agents.

| Command | What it does |
|---|---|
| [`/check`](commands/check.md) | Pre-commit gate: runs `code-reviewer` + `test-gap-checker` + `doc-hygiene-checker` in parallel against the working diff. Advisory output. |
| [`/safe-edit`](commands/safe-edit.md) | Coder ↔ reviewer loop for non-trivial changes: implement → review → fix → review → ready-to-commit. Hard cap of two review cycles. |
| [`/safe-migration`](commands/safe-migration.md) | Schema work with `migration-coordinator` in the loop — apply locally, regen both type files, run the CHECK ↔ TS-union guard, propose doc updates. |
| [`/polish-ui`](commands/polish-ui.md) | Polish a page / screen / component to the running app's quality bar via the `ui-polisher` agent. |
| [`/release-readiness`](commands/release-readiness.md) | Pre-tag gate for the chosen app (web / android / ios / watch / worker). Checks CI green on main, twin parity, schema drift, untracked files, last-tag delta. Read-only. |
| [`/dep-bump-twin`](commands/dep-bump-twin.md) | Mirrors a Dependabot mobile-deps PR's pubspec changes from `apps/mobile_android` to `apps/mobile_ios` so the byte-identical twin survives the merge. |
| [`/audit/*`](commands/audit/README.md) | Focused security / privacy / invariant / compliance audits. `/audit/all` runs the full sweep in parallel. See [`commands/audit/README.md`](commands/audit/README.md) for the full index. |

## Modifying these

When you add a new convention, ADR, or invariant, look here too — most agents read a specific section of `CLAUDE.md`, `docs/architecture/decisions.md`, or `docs/architecture/conventions.md`. If you add a new rule there, the relevant agent's prompt usually needs a corresponding update. Same goes for the agent list in the project's root `CLAUDE.md` and the agent description shown to the user.
