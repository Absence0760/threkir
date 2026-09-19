---
description: Mirror a Dependabot mobile-deps PR's pubspec changes from apps/mobile_android into apps/mobile_ios so the byte-identical-twin invariant survives the merge.
argument-hint: <PR-number-or-branch>
---

Mirror a Dependabot `chore(mobile/deps)` PR's `apps/mobile_android/pubspec.yaml` change into `apps/mobile_ios/pubspec.yaml`, re-resolve the workspace, commit on top, and re-verify the twin invariant.

**There is exactly one Dart lockfile in this repo, and it is at the root.** The Flutter side is a pub workspace — root `pubspec.yaml` declares `workspace:` over `apps/mobile_android`, `apps/mobile_ios` and the five `packages/`, and each member declares `resolution: workspace`. Pub resolves the whole workspace once and writes one `pubspec.lock` at the repo root; a per-app lockfile under `apps/mobile_android` or `apps/mobile_ios` does not exist and is not supposed to. The `.gitignore` comment saying the lockfile is committed is correct and honoured — by the root file.

## Why this exists

Dependabot only tracks `apps/mobile_android/pubspec.yaml` (`.github/dependabot.yml` opens one entry there, not on iOS). `apps/mobile_ios/pubspec.yaml` is a manual mirror per [decisions.md §39](../../docs/architecture/decisions.md#39-mobile_android-and-mobile_ios-share-a-byte-for-byte-dart-codebase) — only `name` and `description` may differ. If a Dependabot PR lands without the iOS mirror, the next `twin-parity` CI job fails on `main`.

This command does the mirror in one step so the user doesn't context-switch between the GitHub PR view and the iOS pubspec.

## When to use

**Right fit:**
- A Dependabot PR exists on the branch (e.g. `dependabot/pub/apps/mobile_android/...`) or just merged.
- The diff is limited to `apps/mobile_android/pubspec.yaml` and the root `pubspec.lock`.

**Wrong fit — refuse:**
- The PR touches more than the two files above. Tell the user to invoke `/safe-edit` or apply manually — non-trivial review needed.
- The branch is `main` and there is no Dependabot PR pending. Tell the user there's nothing to mirror.

## Procedure

### 1. Find the PR / branch

If the user passed `$ARGUMENTS`:
- Numeric → `gh pr view $ARGUMENTS --json headRefName,files,title` to fetch the branch + file list.
- Otherwise → treat as a branch name. `git fetch origin <branch>` then `git checkout <branch>`.

If `$ARGUMENTS` is empty:
- Look for the most recent open Dependabot PR with the `chore(mobile/deps)` prefix:
  `gh pr list --state open --search "in:title chore(mobile/deps)" --json number,title,headRefName --limit 5`
- If multiple, ask the user to pick one. If zero, abort.

### 2. Confirm the diff scope

Run `git diff main...HEAD --name-only` (or `gh pr diff <num> --name-only`). Required: the only changed paths are `apps/mobile_android/pubspec.yaml` and (optionally) the root `pubspec.lock`. Anything else and you abort — the PR isn't a pure dep bump.

### 3. Mirror the pubspec.yaml

Read both `apps/mobile_android/pubspec.yaml` and `apps/mobile_ios/pubspec.yaml`. For every line that differs **except** `name:` and `description:`, copy the android version into ios. The expected diff is purely version pins like `flutter_reactive_ble: ^5.4.2` → `^5.5.0`.

After the edit, re-verify with the same filter the CI uses:

```
diff <(grep -vE '^(name|description):' apps/mobile_android/pubspec.yaml) \
     <(grep -vE '^(name|description):' apps/mobile_ios/pubspec.yaml)
```

Must be empty. If it isn't, the YAML structure has drifted — stop and ask the user.

### 4. Re-resolve the workspace

```
melos bootstrap
```

Run it from the repo root, which is what CI does. One resolve covers every workspace member and rewrites the single root `pubspec.lock`. Do not `cd apps/mobile_ios && flutter pub get` expecting a lockfile there — a workspace member has no lockfile of its own, so the only thing to review after this step is the root `pubspec.lock` diff.

### 5. Re-run the twin invariant

```
diff -rq apps/mobile_android/lib apps/mobile_ios/lib
diff -rq apps/mobile_android/test apps/mobile_ios/test
```

Both must be empty. (They should already be — Dependabot doesn't touch `lib/` or `test/` — but check anyway.)

### 6. Optional: sanity-build iOS

If the user wants extra confidence, suggest they `flutter build ios --no-codesign` from `apps/mobile_ios`. Do not auto-run; an iOS build is a meaningful local cost. Mention it, let the user decide.

### 7. Commit on top of the Dependabot branch

Stage `apps/mobile_ios/pubspec.yaml` and, if the re-resolve moved it, the root `pubspec.lock`. Commit message format:

```
chore(mobile/deps): mirror <package> bump into mobile_ios

Dependabot's pub ecosystem only tracks apps/mobile_android. Mirror
the same constraint (and re-resolve the workspace) so the
byte-identical-twin invariant (decisions.md §39) survives the merge.
```

Use the package + version range from the Dependabot PR title (e.g. `flutter_reactive_ble from 5.4.2 to 5.5.0`).

**Do not push without asking.** The user may want to review on the PR before pushing — and Dependabot branches are sometimes auto-merged on green CI, so a fresh push restarts the run.

## Notes

- This command is read-write. It edits `apps/mobile_ios/pubspec.yaml` and runs `melos bootstrap`.
- If the bump is for an Android-only plugin (e.g. anything that exists only on the JVM side), the iOS mirror still needs the version line in lockstep — the dep just won't compile in for iOS. That's by design; don't try to be clever and skip the mirror.
- If the re-resolve in step 4 fails (e.g. the new constraint is unsatisfiable across the workspace), report the error and stop. Do not loosen the constraint to make iOS compile — push back on the upstream Dependabot PR instead.
