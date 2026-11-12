# share-entity Lambda

Per-request SSR for the eight public **entity** share surfaces, so an
entity created/edited after the last static build still unfurls with the
right per-entity `<head>` (crawlers + chat-app link-unfurlers do not run
the SPA's JS), plus the one per-entity card among them (`/og/challenge`).
One Lambda behind a Function URL, fronted by CloudFront.

## Paths owned (routed here in `infra/modules/web-stack/main.tf`)

| Path | Entity | JSON-LD |
|---|---|---|
| `/share/event/<id>` | public club event | `SportsEvent` / `Event` |
| `/share/profile/<id>` | public runner profile | `ProfilePage` + `Person` |
| `/share/club/<slug>` | public club | `SportsOrganization` |
| `/share/race/<id>` | race-calendar listing | `SportsEvent` |
| `/share/session/<id>` | public session plan | `WebPage` + breadcrumb |
| `/share/workout/<id>` | public gym workout | `WebPage` + breadcrumb |
| `/share/plan/<id>` | public-library training plan | `WebPage` + breadcrumb |
| `/share/challenge/<id>` | public challenge | `Event` |
| `/og/challenge/<id>.png` | that challenge's 1200x630 card | — |

The matching SvelteKit routes
(`src/routes/share/{event,profile,club,race,session,workout,plan,challenge}/[…]`, `src/routes/og/challenge/[id].png`) carry
`prerender = false` and run the same lookup + meta builders under `vite dev`,
so every path works locally without standing up the Lambda.

Session plans + workouts read the **redacted** projections only — the
`public_gym_workouts` / `public_gym_sets` views (no `notes`, no per-set `rpe`)
for a workout, and for a plan the authored fields without the per-item `cue` /
`tempo` teaching notes. An og:description is handed to every unfurler that
touches the link, so the meta says how many sets / movements and how long,
never what the owner wrote in them. A training plan reads the
`public_plan_share` RPC, the one surface here that is not a table read: its
tables are signed-in only, so the RPC is a redacted projection (goal, weeks,
workouts by day offset; no physiology, paces, notes, dates or user id) behind
the default-off `public_plan_share` gate (decisions § 2262).

## Why one Lambda (not eight)

These surfaces share an identical shape — anon public lookup → pure
`build*Head` → `render*HeadTags` → `injectEntityHead` into the SPA shell —
and all but one use the branded card (or the avatar URL for
profiles/clubs) as the `og:image`. The challenge card is the exception
(decisions § 2261): it rasterises with the `@resvg` addon share-badge
already ships, so this bundle carries it too and runs at 512 MB. One
dispatcher still beats cloning the share-badge stack (Function URL + OAC +
cache/origin-request policy + release/OIDC wiring) per surface. See `../share-badge/README.md` for the
one-per-type pattern this deliberately diverges from.

## Build

Run from `apps/web/` **after** `npm run build` (the bundler embeds
`build/200.html` as the SPA shell):

```
node lambda/share-entity/build.mjs
```

Output: `lambda/share-entity/dist/share-entity.zip` (esbuild-bundled
`index.mjs` + `package.json`; supabase-js inlined; `@resvg/resvg-js` and its
arm64 binary copied into `node_modules`, so the arm64 package must be
installed first, as for share-badge). CI's
`release-web.yml` rebuilds + deploys it on every `web@*` tag.

## Share visits are not counted here

Share-link attribution (decisions § 2268) counts a visit to a
`/share/<kind>/<id>` page, but this Lambda does not do the counting.
CloudFront caches its HTML for five minutes and strips the query string
(the `share_entity` cache and origin-request policies), so the Lambda sees
one request per edge per five minutes and never sees the `?ref=` a
creator's link carries. The page itself calls the `record_share_visit` RPC
once per view in the visitor's browser, which also leaves out unfurl bots,
since they do not run its script. `share_entity_handler.test.ts` pins that
the handler makes no counter call and serves the same answer with or
without a `ref`.

## Fail-open posture

A private / missing / deleted entity returns a **404 HTML** with a
`noindex` robots tag (a clean crawler signal), never a 5xx. A path whose
segment carries a malformed percent-escape (`/share/club/%zz`) takes the
same 404 — it is an entity we cannot find, and a 503 there would tell a
crawler to retry a link that can never resolve. Only an unhandled error
returns 503. There is no image endpoint to fall back on.
