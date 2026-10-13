---
description: Open one draft PR for an ad hoc testing session, dispatch a background agent to fix each issue the operator sends into it, and mark it ready when they say so. `/draft [topic]` opens, `/draft resume <pr>` picks one up again, `/draft ready` finishes.
argument-hint: "[topic] | resume <pr> | ready"
---

The operator is testing the app by hand (web, the phones, a watch) and will
send issues one at a time. Every fix lands in **one** draft PR; it stays a
draft until the operator says it's ready. Mode is `$ARGUMENTS`:

- empty or a topic → **Open**
- `resume <pr>` → **Resume**
- `ready` → **Ready**

## Open

1. Branch in a worktree off a fresh `origin/main`, never local `main`
   ([CLAUDE.md § Branches & PRs](../../CLAUDE.md), § Working alongside other
   Claude sessions). Worktrees here are siblings named `threkir-<slug>`:
   ```
   git fetch origin main
   git worktree add ../threkir-adhoc-<slug> -b fix/adhoc-<slug> origin/main
   ```
   `<slug>` is the topic, or today's date (`YYYY-MM-DD`) when there is none.
2. GitHub won't open a PR without a commit, so start with an empty one (the
   scope guard allows `--allow-empty`), then push, naming the branch:
   ```
   git -C ../threkir-adhoc-<slug> commit --allow-empty -m "chore: open the ad hoc testing fixes branch"
   git -C ../threkir-adhoc-<slug> push -u origin fix/adhoc-<slug>
   ```
3. Open the draft: `gh pr create --draft --base main --title "fix: ad hoc
   testing fixes (<topic or date>)"` with `.github/pull_request_template.md`
   as the body: the Summary says it collects fixes from ad hoc testing,
   Changes starts as `_(none yet)_`, and no Platforms touched box is ticked
   yet.
4. Reply with the PR link and the worktree path, then wait for the first
   issue.

## Resume

`gh pr view <pr> --json headRefName,isDraft,body`. Find its worktree with
`git worktree list` (or add one for the branch), merge `origin/main` into it
if it fell behind (merge, never rebase or force-push), and carry on from
**Each issue**. A PR with conflicts runs no `ci.yml` at all and still shows
green checks, so resolve a conflict first (CLAUDE.md § Branches & PRs).

## Each issue

The main session stays free to talk: it triages each issue and hands the fix
to a **background subagent** (the Agent tool, `run_in_background`), one per
issue, then goes back to the operator. It never fixes an issue inline, except
a one-line change it has already diagnosed.

For every issue the operator sends, until they say ready:

1. **Triage (main session).** Restate it in one line, naming the surface
   (web, Android, iOS, Wear OS, Apple Watch, backend). Ask only if two
   readings would build different things; otherwise pick the reasonable one
   and say which. Dig only as far as you need to brief the agent: the screen,
   the likely files, what you've ruled out, and whether the same defect
   likely exists on the other platform.
2. **Dispatch.** Start a background `general-purpose` subagent with a
   self-contained brief: the issue in the operator's words (screenshots
   described, since the agent can't see them), what you've learned, the
   worktree path and branch, its own scratchpad subdirectory
   (`<scratchpad>/adhoc-<n>/`, CLAUDE.md § Working alongside other Claude
   sessions), and these rules:
   - Work only in the PR's worktree; never touch `main` or the main
     checkout. Never `git stash`; put a file back with
     `git checkout HEAD -- <path>`, never a `.bak` copy.
   - **Reproduce, then fix the root cause, web-first** (CLAUDE.md § Always
     recommend the long-term solution): no widened timeouts, retries, skips
     or swallowed errors. A failing test first where one fits.
   - **Route by what it touches**, through the commands and agents this repo
     has: `/safe-migration` (the `migration-coordinator` agent) for anything
     under `apps/backend/supabase/migrations/`, which also regenerates both
     type files (`npm run gen:types` + `dart run scripts/gen_dart_models.dart`);
     `/safe-edit` for security-sensitive, schema or recording-stack changes;
     the `metrics-reviewer` agent for derived numbers (pace, training load,
     zones, the caches); the `metadata-key-keeper` agent for any
     `runs.metadata` key; `/polish-ui` for a screen's composition, `/ux-hunt`
     or `/a11y-hunt` rules for an anti-pattern or WCAG defect.
   - **Keep the twins and pairs in lockstep.** A Dart edit under
     `apps/mobile_android/lib/` or `apps/mobile_android/test/` is mirrored
     byte for byte into `apps/mobile_ios/` (the `mobile-twin-mirror` agent);
     a TS↔Dart parity helper (`docs/architecture/parity_pairs.md`) gets the
     `shared-library-syncer` agent. A new user-facing string goes into every
     web locale under `apps/web/src/lib/i18n/locales/` and every mobile ARB
     under `apps/mobile_android/lib/l10n/` (the `i18n-translator` and
     `i18n-checker` agents for the translations).
   - **Tests and docs in the same commit**
     ([conventions.md § Test hygiene](../../docs/architecture/conventions.md),
     CLAUDE.md § Docs hygiene): a regression test that fails before the fix,
     and `docs/product/parity.md`, `docs/product/features.md` or the app's
     own `CLAUDE.md` when behaviour changed. Run only what it touched, never a
     full suite ([docs/testing/testing.md](../../docs/testing/testing.md)):
     - Web: `npx tsx --test <file>` from `apps/web`, `pnpm check:web`, and
       the Playwright specs for the screen
       (`pnpm -C apps/web exec playwright test --config=tests-e2e/playwright.config.ts <spec>`,
       needs the local Supabase stack, `pnpm dev:db:up`).
     - Android / iOS (Flutter): `flutter test test/<file>` from
       `apps/mobile_android` (the twin's tests are the same files), plus
       `dart analyze` on the package. Native bridges: `./gradlew
       :app:testDebugUnitTest` from `apps/mobile_android/android`, or the
       `xcodebuild test … -only-testing:RunnerTests` recipe in testing.md for
       `apps/mobile_ios/ios/RunnerTests/`.
     - Apple Watch: the `xcodebuild test` recipe in
       `apps/watch_ios/CLAUDE.md` § Building and testing (a simulator by
       UDID); a new Swift file is added to both Xcode projects there.
     - Wear OS: `./gradlew testDebugUnitTest` from
       `apps/watch_wear/android`.
     - Backend: the pgTAP files under `apps/backend/supabase/tests/`
       (`supabase test db --local` from `apps/backend`) or the Deno test
       beside the Edge Function; `pnpm test:worker` for `apps/job_worker`.
     - A test count claim moved: `pnpm check:test-inventory`.
     Mobile and watch have no per-change e2e requirement; say what the
     operator should walk through on a device or simulator instead.
   - **One path-scoped commit**:
     `git commit -m "fix(<scope>): <what>" -- <paths>`, then
     `git push -u origin <branch>` (name the branch). No `Co-Authored-By`,
     generated-by footer or any other AI attribution. If git reports
     `index.lock` or the push is rejected because another agent pushed first,
     wait, `git pull --no-rebase origin <branch>`, and try again; never
     force-push.
   - Don't edit the PR body; report back the cause, the fix, the commit
     hash, the files, the platforms touched and the commands run, or why it
     stopped.
   - If the fix needs a product decision, a compliance sign-off, a
     credential, real hardware or an operator action (a Terraform apply, a
     store submission), stop and report rather than guess.
3. **Run agents in parallel when their issues touch different areas**; when
   two would edit the same files (a twin pair, a shared locale file, an
   append-heavy doc such as `docs/architecture/decisions.md`), queue the
   second until the first reports. Tell the operator in one line what was
   dispatched, then take the next issue.
4. **When an agent reports (main session):** check its commit is on the
   branch (`git log origin/<branch>`) and its diff is what was asked, with
   the twin and tests in it. Add one bullet under the PR body's Changes
   (`gh pr edit <pr> --body-file …`; only the main session edits the body,
   so updates don't race) and tick the Platforms touched boxes. Then tell
   the operator in two or three lines: the cause, the fix, the commit. Relay
   a stop or a question as it is.

If an issue turns out too large or risky for this PR (a migration with a
backfill, a feature that needs a product call), say so and offer a separate
issue or PR rather than folding it in. Don't let it drop (CLAUDE.md § Always
recommend the long-term solution).

Don't watch CI after every push. Glance at `gh pr checks <pr>` between issues
and dispatch a fix for a red job this PR caused (`/fix-ci` has the method).

## Ready

Only when the operator says so:

1. Wait for every dispatched agent to report, then merge `origin/main` if the
   branch fell behind. Append-heavy docs (`decisions.md`, `followups.md`,
   `parity.md`, `test_inventory.md`) conflict routinely: keep both sides and
   recompute counted claims with `pnpm check:test-inventory`.
2. Run the checks for everything the PR touched: `pnpm check:web` and
   `pnpm test:web:unit` when web changed, `pnpm check:flutter` and the
   touched Flutter test files when Dart changed, plus the targeted e2e specs,
   pgTAP files and native suites from **Each issue**. The full suite is CI's.
3. `/check` over the whole branch (`git diff origin/main...HEAD`). Apply the
   findings you agree with; say why for the rest in the PR body.
4. Make the title name what the fixes are about, as a conventional commit:
   `fix(<scope>): <subject>`, the type from `feat fix chore docs refactor
   test perf ci build revert` (no `style`), lowercase subject, no period,
   ≤ ~70 chars (`.github/workflows/pr-title-lint.yml`). Use no scope when the
   fixes span areas.
5. `gh pr ready <pr>`, then drive it to green: the one required status is
   `CI gate`; confirm `ci.yml` actually started rather than reading a few
   green checks as CI, and fix any red job at its root (`/fix-ci`). Don't
   merge; that's the operator's call.
6. Report the link, the list of fixes, what the operator should check on a
   device, and anything they need to decide.
