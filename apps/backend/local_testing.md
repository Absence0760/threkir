# Local testing — Backend (Supabase)

The backend must be running before any client app can authenticate or sync data. Start this first.

---

## Prerequisites

| Tool | Install |
|---|---|
| Docker Desktop | `docker.com/products/docker-desktop` |
| Supabase CLI | `brew install supabase/tap/supabase` |

---

## Starting the local stack

```bash
cd apps/backend

# Start Postgres, Auth, Storage, and REST API
supabase start --exclude vector
```

On first run this pulls Docker images — takes a few minutes. On success it prints URLs, database credentials, and API keys. You can retrieve them at any time with:

```bash
supabase status
```

Key values for client apps:

| Field | Example |
|---|---|
| Project URL | `http://127.0.0.1:24321` |
| Publishable key | `sb_publishable_...` |
| Database URL | `postgresql://postgres:postgres@127.0.0.1:24322/postgres` |

These are local defaults and are regenerated on each `supabase start` — no need to save them.

---

## Apply database migrations and seed data

```bash
supabase db reset
```

This drops and recreates the local database using the migration files in `supabase/migrations/`, then runs `seed.sql` which creates a test user and populates all tables with realistic mock data.

**Test user credentials:**
- Email: `runner@test.com`
- Password: `testtest`

The seed includes 12 runs (across app, Strava, parkrun, HealthKit sources), 5 routes, a user profile, and 2 connected integrations. This is enough to test the dashboard, run history, route library, and all other pages with real data.

### Regenerate client row types

After `supabase db reset` picks up a new migration, refresh the generated row classes both clients depend on:

```bash
# From repo root
npm run gen:types                       # writes apps/web/src/lib/database.types.ts
dart run scripts/gen_dart_models.dart   # writes packages/core_models/lib/src/generated/db_rows.dart
```

`npm run gen:types:check` is the exact command CI runs in the `parity-types` job — use it to verify your committed types match the schema before pushing. Full reference in [schema_codegen.md](../../docs/architecture/schema_codegen.md).

---

## Start Edge Functions

```bash
# Create .env.local from the example
cp .env.example .env.local
# Fill in STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET (optional for basic testing)

supabase functions serve --env-file .env.local
```

Functions are now available at `http://localhost:24321/functions/v1/{function-name}`.

You can test them with curl:

```bash
# Example: test parkrun import
curl -X POST http://localhost:24321/functions/v1/parkrun-import \
  -H "Authorization: Bearer <user-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"athleteNumber": "A123456"}'
```

---

## Supabase Studio

Open `http://localhost:24323` in your browser to:

- Browse and edit table data
- Run SQL queries
- Inspect auth users and sessions
- View storage buckets

---

## Environment variables

| Variable | Where to set | Value |
|---|---|---|
| `STRAVA_CLIENT_ID` | `apps/backend/.env.local` | From Strava developer portal (optional) |
| `STRAVA_CLIENT_SECRET` | `apps/backend/.env.local` | From Strava developer portal (optional) |
| `PARKRUN_USER_AGENT` | `apps/backend/.env.local` | Any user agent string |

---

## Stopping

```bash
cd apps/backend
supabase stop
```

To stop and remove all local data (full reset):

```bash
supabase stop --no-backup
```

---

## Troubleshooting

### "Port 24321 already in use"

A previous Supabase instance is still running:

```bash
supabase stop
supabase start
```

### Something still dials 54321 / 54322 / 54324

The stack used to publish the CLI's default 5432x ports. It now pins every host port below 32768 (API 24321, DB 24322, Studio 24323, Mailpit 24324 / SMTP 24325 / POP3 24326, analytics 24327), outside Linux's ephemeral source-port range, so an outbound connection can never take one before docker binds it (issue #963). A checkout from before the move needs two things: restart the stack (`supabase stop && supabase start`) so it republishes on the new ports, and regenerate any **uncommitted** env file copied from the old values — `apps/web/.env`, `apps/backend/.env.local`, a mobile `.env` — plus any `adb reverse tcp:54321` set by hand (`npm run dev:core` re-runs it on 24321 / 24322). The committed `.env.development` / `.env.example` files already carry the new ports.

### Docker not running

`supabase start` requires Docker Desktop to be running. Open Docker Desktop and wait for it to finish starting before retrying.

### Migrations fail

Check the SQL syntax in `supabase/migrations/`. Run `supabase db reset` to apply all migrations from scratch. Look at the error output — it usually points to the exact line number.

---

*Last updated: April 2026*
