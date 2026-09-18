# Coach Lambda

Production handler for `/api/coach/*`. Reaches the same `$lib/coach/handler` core that the SvelteKit dev route uses (see [`apps/web/CLAUDE.md`](../../CLAUDE.md) and [decisions.md § 53](../../../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages)).

## Layout

```
src/index.ts      Lambda Function URL handler (response-streaming).
                  Adapts API Gateway events to the shared core.
build.mjs         esbuild bundler — produces dist/index.mjs + coach.zip.
dist/             generated (gitignored)
```

## Build locally

```bash
cd apps/web
node lambda/coach/build.mjs
# → apps/web/lambda/coach/dist/coach.zip
```

The CI workflow (`.github/workflows/release-web.yml`) runs the same script.

## Runtime env (set by Terraform)

- `PUBLIC_SUPABASE_URL`, `PUBLIC_SUPABASE_ANON_KEY` — non-secret, written by Terraform from variables.
- `SECRETS_CIPHERTEXT` + `SECRETS_CONTEXT` — the credentials. `ANTHROPIC_API_KEY`,
  `SUPABASE_SECRET_KEY` and `OPENAI_API_KEY` are **not** environment variables:
  Terraform encrypts them from the sops file into one KMS blob at apply time
  (`aws_kms_ciphertext.coach`) and `src/lib/core/lambda_secrets.ts` decrypts it
  once per cold start under the execution role. A Lambda environment is returned
  by every API that returns a `FunctionConfiguration`, including
  `lambda:UpdateFunctionCode`, so a plaintext key there is readable by anything
  that can deploy — decisions § 1659. No bag, or a bag that will not decrypt, is
  a 503; there is deliberately no plaintext fallback.
- `COACH_PROVIDER`, `OPENAI_BASE_URL`, `OPENAI_MODEL` — optional, and plain env
  vars on purpose: a provider name, an endpoint and a model authorise nothing,
  and the provider gate reads them before there is a bag to read.
- `SENTRY_DSN` — optional, and it is what makes a failure visible anywhere
  but CloudWatch. Terraform feeds it from `local.sentry_env`; unset means the
  reporter in `src/lib/core/lambda_sentry.ts` never initialises, which is the
  dev/CI default.
- `APP_RELEASE` is **not** a runtime env here. `build.mjs` bakes it into the
  bundle from the tag `release-web.yml` passes on the bundle step, because the
  release identifies the artifact rather than the environment. A locally built
  zip carries `dev`.

`BYPASS_PAYWALL` is intentionally ignored in this handler — it's a dev-only escape hatch.

## Updating the deployed Lambda

The CDK / Terraform stack creates the Lambda with a placeholder zip and a `live` alias. CI replaces the code on every `web@*` tag via `aws lambda update-function-code` and retargets the alias. Rollback is `aws lambda update-alias --function-name web-coach-prod --name live --function-version <previous>` — see [`apps/web/deployment.md` § Rollback](../../deployment.md#rollback).
