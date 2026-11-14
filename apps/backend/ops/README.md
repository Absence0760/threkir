# Production config as code

`prod_config.json` is the reviewed, committed state of the production switches
that used to be flipped by hand in the SQL Editor (issue #1350, decisions
§ 2430). Every `backend@*` release applies it in its last step, "Sync
production state" (`scripts/prod_sync/run.mjs`, after the park catalogue), and
writes what each entry did to the job's step summary. A `workflow_dispatch` of
Release Backend applies it on its own, with `dry_run` defaulting to true; a
committing dispatch runs only from `main`. Both wait on the `production`
environment's approval.

**An entry absent from the file is left untouched.** The file was committed
empty, so its first release changed nothing; production's values stay what
they were until someone declares one here.

## Turning something on (or off)

Open a PR that edits `prod_config.json`, with the sign-off link in the entry.
When it merges, the next backend release (or a dispatch from `main`) applies it
and reports `created` / `updated` / `unchanged`. Turning a switch off is the
same edit with `"enabled": false`. Deleting an entry does **not** turn it off;
it stops the release managing it.

`signoff` is required whenever `enabled` is `true`. It is the URL of the GitHub
issue, PR or comment that records the approval (for example the #1097
checkpoint comment), or a `reviews/` or `docs/` `.md` path. A `docs/` path must
exist; `reviews/` is gitignored, so prefer a link.

```json
{
  "feature_flags": {
    "live_overlay": { "enabled": true, "signoff": "https://github.com/Absence0760/threkir/issues/1097#issuecomment-…" }
  },
  "function_env": {
    "EXAMPLE_TOGGLE_ENABLED": { "enabled": true, "signoff": "https://github.com/Absence0760/threkir/issues/<n>#issuecomment-…" }
  },
  "web_env": {
    "PUBLIC_COURSE_DRIVE_ENABLED": { "enabled": false }
  },
  "cron_urls": ["race_listings_sweep", "club_verification_recheck"],
  "retired_functions": ["parkrun-import"],
  "retired_function_env": ["PARKRUN_EVENTS_ENABLED", "PARKRUN_USER_AGENT", "ULTRASIGNUP_RESULTS_ENABLED"]
}
```

## The sections

| Section | What it sets | Applied by |
|---|---|---|
| `feature_flags` | A `private.feature_flags` row. The name must be one a migration reads or seeds. | The backend release, through `private.apply_feature_flag`. |
| `function_env` | An Edge Function secret, only from the allow-list of boolean toggles in `scripts/prod_sync/lib/prod_config.mjs` (empty today: its only entry, `PARKRUN_EVENTS_ENABLED`, went with the parkrun events leg, decisions § 2467; `EXAMPLE_TOGGLE_ENABLED` above is a placeholder), written as `true` / `false`. | The backend release, with `supabase secrets set`. It reads the current value only as the CLI's digest and never prints one. |
| `web_env` | A `PUBLIC_*` gate a `*_flag.ts` module reads. It replaces that flag's repo secret in the web build. | The next **web** release (`release-web.yml` runs `scripts/prod_sync/web_env.mjs`). The backend release only validates it. |
| `cron_urls` | The `<fn>_url` Vault entry `public.invoke_<fn>()` reads, built from the project ref as `https://<ref>.supabase.co/functions/v1/<fn-with-dashes>`. | The backend release, through `private.arm_cron_url`. It requires the `cron_secret` entry (checked by name, never read). For an entry it created or changed it invokes the function once and fails the step unless the response is 2xx. |
| `retired_functions` | Edge Functions that must no longer be deployed (`parkrun-import` today). `supabase functions deploy` never deletes one, so a function whose directory was removed keeps serving until it is named here. | The backend release's *Retired Edge Functions and secrets* stage, after Deploy Edge Functions: `supabase functions delete` for each one still deployed. The guard refuses a name that still has a directory under `supabase/functions/`. |
| `retired_function_env` | Edge Function secrets to unset (`PARKRUN_EVENTS_ENABLED`, `PARKRUN_USER_AGENT`, `ULTRASIGNUP_RESULTS_ENABLED` today). | The same stage: `supabase secrets unset` for each one still set. The guard refuses a name an Edge Function still reads with `Deno.env.get`, or one `function_env` also sets. |

The retired stage reports one row per name: `deleted` / `unset`, `absent` when it is already gone (idempotent, so the names can stay listed), or `would delete` / `would unset` on a dry run. A `failed` row fails the step; the manual fallback is in [deployment.md § Retired scraper functions and secrets](../../../docs/ops/deployment.md#retired-scraper-functions-and-secrets).

**Removing an Edge Function = delete its directory and add its name to `retired_functions` in the same PR**, plus any secret only it read to `retired_function_env`. Without the entry, production keeps serving the deleted code.

Not here, because a backend release cannot reach them:

- the coach Lambda's `AI_PLAN_ENABLED`, `AI_PLAN_EDIT_ENABLED`, `PLATE_PHOTO_ENABLED` and `COACH_FUEL_ENABLED` (the sops file's `coach_config_keys`, applied by Terraform). The guard refuses them under `function_env` and names where they go, and notes the other half when you declare their `PUBLIC_*` twin.
- the mobile dotenv toggles (`ADAPTIVE_FITNESS_GATE`, `WEIGHT_FLUID_ENABLED`, `--dart-define`s), which ship in a store build.
- any credential. `cron_secret` and every key stay operator-held secrets.

## One-off tasks

`tasks/<14-digit timestamp>_<snake_name>.sql` runs once, in its own
transaction, and is recorded in `private.ops_task_runs` with its sha256 and
result. See [tasks/README.md](tasks/README.md).

## Checks

`node scripts/prod_sync/check_prod_config.mjs` (in CI beside the parks checks,
and again by the release before any stage runs) checks the shape, the
sign-offs, that every name exists where it is read, the `function_env`
allow-list, paired web flags, cron invokers and task file names. Its tests are
`scripts/prod_sync/lib/prod_config.test.mjs` and
`scripts/prod_sync/lib/config_stages.test.mjs`; the database half is
`apps/backend/supabase/tests/prod_config_sync_test.sql`.

The sync also checks, read-only, that production's PostgREST `max_rows` (the
Data API "Max rows" setting, read from the Management API by
`scripts/prod_sync/postgrest_max_rows.mjs`, which prints only that integer)
is at least the `[api] max_rows` that `apps/backend/supabase/config.toml`
pins. The clients' keyset walk ends on a page shorter than that pin without a
confirming read, so a lower production cap would cut every walk short while it
reported itself complete; the stage fails the release instead and names the
value to raise. Its tests are `scripts/prod_sync/lib/postgrest_cap.test.mjs`.

## Emergency fallback

If a release cannot run, the SQL each stage calls works by hand in the SQL
Editor as the service role, for example
`select private.apply_feature_flag('live_overlay', false);`. Commit the same
change to `prod_config.json` straight after, or the next release puts the
committed value back.
