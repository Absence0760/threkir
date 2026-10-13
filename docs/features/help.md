# In-app help guides

> **Status:** Framework shipped web (2026-10-13): `/help`, `/help/[id]`, `/help/search`, the per-page **How this works** link and the InfoTip guide link. Mobile renders the same guides from a generated JSON asset (Flutter renderer built in a sibling lane). Guide **text is English-only** this round; the help chrome is translated into every web locale. ADR: [decisions.md § 1846](../architecture/decisions.md).

In-app help is a **signed-in reference** to the app itself: what a feature does, who it is for, where it lives and what it needs first. It is a different surface from the public [Learn guides](learn.md) (`/learn`), and the two stay separate:

| | `/learn` | `/help` |
|---|---|---|
| Reader | anyone, signed out, arriving from search | a signed-in user inside the app |
| Purpose | evergreen running topics that funnel to sign-up | how *this app* works, screen by screen |
| Source | mdsvex `.md` under `lib/learn/guides/` | typed TypeScript under `lib/help/guides/` |
| Rendering | prerendered static HTML, indexed, JSON-LD | app shell, not prerendered, `noindex` + `Disallow: /help` |
| Mobile | none (web-only) | the same guides, via `guides.en.json` |

Don't cross-link them as if they were one corpus, and don't move a guide between them: a Learn article is marketing copy written for crawlers, a help guide names on-screen labels and route ids that change with the app.

## Architecture

```
apps/web/src/lib/help/
  types.ts          the contract (Guide, GuideSection, Block, the enums) — type-only
  guides/<id>.ts    one guide per file: `export const guide: Guide = {...}`
  markup.ts         parseMarkup / plainText / markupProblems / routeHref / sectionId
  catalogue.ts      createHelpIndex(guides) — pure; the enum value lists
  index.ts          import.meta.glob over guides/ → allGuides, guideFor,
                    guidesByCategory, guidesForRoute, searchGuides
  labels.ts         enum value → catalogue key (category, kind, audience, …)
apps/web/src/lib/components/help/
  HelpRichText.svelte    renders one marked-up string from tokens (no {@html})
  HelpLink.svelte        "How this works" for a route id
  HelpSearchForm.svelte  GET form to /help/search
apps/web/src/routes/help/
  +page.svelte           contents: categories, audience chips, search
  [id]/+page.svelte      one guide: badges, On this page, sections, related
  search/+page.svelte    ranked results for ?q=
scripts/gen_help_guides.mjs  → apps/mobile_{android,ios}/assets/help/guides.en.json
```

`index.ts` only binds the Vite glob to `catalogue.ts`; everything testable lives in the pure module, so the unit suite (raw `tsx`, no Vite) builds the same index from the files on disk.

### The contract

`types.ts` is shared with the mobile renderer, so a shape change there is a change to the Flutter reader too. A guide carries `id` (kebab-case, equal to the file name), `title` (≤ 70 chars), `summary` (≤ 160 chars, one sentence), `kind` (`start` / `how-to` / `explainer`), `category`, `audience[]`, optional `requires[]` (`pro`, `club-admin`, `race-director`, `stripe-connected`, `paid-rail-live`), `platforms[]` (where the flow exists **today**), optional `routes[]` (SvelteKit route ids it describes), `sections[]` of blocks (`p`, `steps`, `list`, `note` with tone `tip` / `caution`) and optional `related[]` guide ids.

### Markup

Every block string may carry exactly four forms, and nothing else — no HTML, no markdown headings, no emoji:

| Markup | Renders as |
|---|---|
| `**Save**` | the on-screen label, bold — use the exact English label |
| `*only once*` | emphasis (asterisks must stand apart from a word, so `5*3` stays text) |
| `[[guide:<id>\|label]]` | a link to `/help/<id>` |
| `[[route:<route id>\|label]]` | a link to the screen; a route id with params (`/clubs/[slug]`) has no single address and renders as plain text |

Titles, summaries and section headings take no markup at all. Section anchors are `sectionId(heading)`; the guide page and "On this page" both use it.

### Search and ranking

`searchGuides(q)` folds case and accents (`cafe` finds `Café`), requires **every** word to appear somewhere, and ranks a word in the title (100) over the summary (10) over the body (1, headings and block text with markup stripped). Ties keep contents order. The query lives in the URL (`/help/search?q=`), so a search can be bookmarked and gone back to.

### Entry points

- **Account menu → Help.** The sidebar's account popover lists the secondary destinations; it serves the desktop sidebar and the narrow-viewport rail alike.
- **`<HelpLink route="/the/route/[id]" />`** — "How this works" near a page title: one guide links straight to it, several open a short disclosure list, none renders nothing (and fails the guard). Mount it with a literal route id.
- **`<InfoTip guide="<id>" …>`** — adds "Read the guide" after the tip's own text.

### Mobile

`node scripts/gen_help_guides.mjs` (`pnpm gen:help-guides`) imports every guide file with Node's built-in type stripping — a guide imports nothing at run time, so no `tsx` and no install — and writes the same JSON array (sorted by category then id, keys in contract order) to both twins' `assets/help/guides.en.json`, registered under `flutter: assets:` in both `pubspec.yaml`s. The mobile lane owns the route-id → screen map; an unmapped `[[route:]]` renders as plain text there too.

## Adding a guide

1. Create `apps/web/src/lib/help/guides/<id>.ts`:
   ```ts
   import type { Guide } from '../types';

   export const guide: Guide = { id: '<id>', /* … */ };
   ```
   That import is the only one allowed.
2. Write it from the app as it is: exact English labels in `**…**`, honest `platforms`, and a `caution` note for anything gated or not yet live (a Stripe account that must be connected, a rail switched off until enabled, a web-only import).
3. List the `routes` it describes, and mount `<HelpLink route="…" />` on those pages if they don't have one.
4. Run `pnpm gen:help-guides` and commit the two JSON files with the guide.
5. Run `npx tsx --test src/lib/help/help_guides_guard.test.ts` from `apps/web`.

## Guards

`apps/web/src/lib/help/help_guides_guard.test.ts` (unit job) fails when:

- a guide's `id` is not its file name, or a file in `guides/` is not a guide;
- a guide file imports anything but `type { Guide }`;
- a title or summary is too long, a summary is more than one sentence, or a title / summary / heading carries markup;
- a kind, category, audience, requirement or platform is not a known value, or is repeated;
- a guide has no sections, a section no blocks, or two headings share an anchor;
- any string has stray `*`, an unclosed or unknown `[[…]]`, a raw `<`, or an emoji;
- a `[[guide:]]` or `related` id names no guide (or the guide itself);
- a `[[route:]]` or `routes` entry is not a directory under `apps/web/src/routes` holding `+page.svelte`;
- a `<HelpLink>` has a non-literal route, or a route no guide lists;
- an `<InfoTip guide=…>` names no guide;
- `guides.en.json` is stale.

CI also runs `node scripts/gen_help_guides.mjs --check` in `build-web`, before the install. `markup.test.ts` and `catalogue.test.ts` pin the parser and the index; `tests-e2e/help/help-centre.spec.ts` pins the pages, search, anchors, the account-menu path and the event page's HelpLink.

## Translation

Only English guide files exist (`guides.en.json` is named for the day there are more). `/help` says so, and the guide page marks guide text `lang="en"` while its chrome follows the app locale. Translation is the next step: per-locale guide files with English fallback, and a per-locale JSON for mobile.
