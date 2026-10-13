# In-app help guides

> **Status:** Framework shipped web (2026-10-13): `/help`, `/help/[id]`, `/help/search`, the per-page **How this works** link and the InfoTip guide link. Mobile renders the same guides from generated per-locale JSON assets. Every guide is **translated into all six non-English locales** (de, fr, es, ja, pt-PT, pt-BR); a guide with no translation falls back to English with a note, and a translation made from older English fails CI. ADRs: [decisions.md § 1846](../architecture/decisions.md), § R7I18N-1, § R7I18N-2.

In-app help is a **signed-in reference** to the app itself: what a feature does, who it is for, where it lives and what it needs first. It is a different surface from the public [Learn guides](learn.md) (`/learn`), and the two stay separate:

| | `/learn` | `/help` |
|---|---|---|
| Reader | anyone, signed out, arriving from search | a signed-in user inside the app |
| Purpose | evergreen running topics that funnel to sign-up | how *this app* works, screen by screen |
| Source | mdsvex `.md` under `lib/learn/guides/` | typed TypeScript under `lib/help/guides/` |
| Rendering | prerendered static HTML, indexed, JSON-LD | app shell, not prerendered, `noindex` + `Disallow: /help` |
| Mobile | none (web-only) | the same guides, via `guides.<locale>.json` |

Don't cross-link them as if they were one corpus, and don't move a guide between them: a Learn article is marketing copy written for crawlers, a help guide names on-screen labels and route ids that change with the app.

## Architecture

```
apps/web/src/lib/help/
  types.ts          the contract (Guide, GuideSection, Block, the enums) — type-only
  guides/<id>.ts    one guide per file: `export const guide: Guide = {...}` (English)
  translations/<locale>/<id>.ts
                    `export const translation: GuideTranslation = {...}`: the
                    guide's words in one locale, plus the `source` hash
  translate.ts      translatableText / structureProblems / localizeGuide /
                    mergeFetchedGuides — pure, no run-time imports
  markup.ts         parseMarkup / plainText / markupProblems / routeHref / sectionId
  catalogue.ts      createHelpIndex(guides, lang) — pure; the enum value lists
  index.ts          import.meta.glob over guides/ → the English index
  localized.svelte.ts
                    helpIndex() — the index in the app locale; loadHelpGuides
                    fetches a translated locale's JSON once
  labels.ts         enum value → catalogue key (category, kind, audience, …)
apps/web/src/lib/components/help/
  HelpRichText.svelte    renders one marked-up string from tokens (no {@html})
  HelpLink.svelte        "How this works" for a route id
  HelpSearchForm.svelte  GET form to /help/search
apps/web/src/routes/help/
  +layout.ts             loads the app locale's guides before a help page renders
  +page.svelte           contents: categories, audience chips, search
  [id]/+page.svelte      one guide: badges, On this page, sections, related
  search/+page.svelte    ranked results for ?q=
scripts/gen_help_guides.mjs        → apps/mobile_{android,ios}/assets/help/guides.<locale>.json
                                     apps/web/static/help-guides/guides.<locale>.json (not en)
scripts/check_help_translations.mjs  the staleness guard (§ Translation)
```

`index.ts` only binds the Vite glob to `catalogue.ts`; everything testable lives in the pure module, so the unit suite (raw `tsx`, no Vite) builds the same index from the files on disk.

### The contract

`types.ts` is shared with the mobile renderer, so a shape change there is a change to the Flutter reader too. A guide carries `id` (kebab-case, equal to the file name), `title` (≤ 70 chars), `summary` (≤ 160 chars, one sentence), `kind` (`start` / `how-to` / `explainer`), `category`, `audience[]`, optional `requires[]` (`pro`, `club-admin`, `race-director`, `stripe-connected`, `paid-rail-live`), `platforms[]` (where the flow exists **today**), optional `routes[]` (SvelteKit route ids it describes), `sections[]` of blocks (`p`, `steps`, `list`, `note` with tone `tip` / `caution`) and optional `related[]` guide ids.

### Markup

Every block string may carry exactly four forms, and nothing else — no HTML, no markdown headings, no emoji:

| Markup | Renders as |
|---|---|
| `**Save**` | the on-screen label, bold — the exact label in the guide's language (in a translation, that locale's catalogue string) |
| `*only once*` | emphasis (asterisks must stand apart from a word, so `5*3` stays text) |
| `[[guide:<id>\|label]]` | a link to `/help/<id>` |
| `[[route:<route id>\|label]]` | a link to the screen; a route id with params (`/clubs/[slug]`) has no single address and renders as plain text |

Titles, summaries and section headings take no markup at all. Section anchors are `sectionId(heading)`; the guide page and "On this page" both use it. Letters of any script survive into the anchor, so a Japanese heading has one too (kana lose their voicing marks, the same folding search uses).

### Search and ranking

`searchGuides(q)` folds case and accents (`cafe` finds `Café`), requires **every** word to appear somewhere, and ranks a word in the title (100) over the summary (10) over the body (1, headings and block text with markup stripped). Ties keep contents order. The query lives in the URL (`/help/search?q=`), so a search can be bookmarked and gone back to.

### Entry points

- **Account menu → Help.** The sidebar's account popover lists the secondary destinations; it serves the desktop sidebar and the narrow-viewport rail alike.
- **`<HelpLink route="/the/route/[id]" />`** — "How this works" near a page title: one guide links straight to it, several open a short disclosure list, none renders nothing (and fails the guard). Mount it with a literal route id.
- **`<InfoTip guide="<id>" …>`** — adds "Read the guide" after the tip's own text.

### Mobile

`node scripts/gen_help_guides.mjs` (`pnpm gen:help-guides`) imports every guide and translation file with Node's built-in type stripping — they import nothing at run time, so no `tsx` and no install — and writes one JSON array per app locale (sorted by category then id, keys in contract order, each guide carrying `lang`) to both twins' `assets/help/guides.<locale>.json`, registered under `flutter: assets:` (the `assets/help/` directory) in both `pubspec.yaml`s. Every file holds every guide: translated where a translation exists, else English with `"lang": "en"`. `help_loader.dart` reads the app locale's file (`helpLocaleTag`, so a bare `pt` reads `pt-PT`) and falls back to `guides.en.json` when that file is missing, unreadable or empty; the guide screen shows `helpGuideInEnglish` under the summary when a guide's `lang` is not the app's. The mobile lane owns the route-id → screen map; an unmapped `[[route:]]` renders as plain text there too.

## Adding a guide

1. Create `apps/web/src/lib/help/guides/<id>.ts`:
   ```ts
   import type { Guide } from '../types';

   export const guide: Guide = { id: '<id>', /* … */ };
   ```
   That import is the only one allowed.
2. Write it from the app as it is: exact English labels in `**…**`, honest `platforms`, and a `caution` note for anything gated or not yet live (a Stripe account that must be connected, a rail switched off until enabled, a web-only import).
3. List the `routes` it describes, and mount `<HelpLink route="…" />` on those pages if they don't have one.
4. Translate it into every non-English locale (§ Translation) — until then it shows in English, with a note, in those locales.
5. Run `pnpm gen:help-guides` and commit every JSON file it writes with the guide.
6. Run `npx tsx --test src/lib/help/help_guides_guard.test.ts` from `apps/web` and `node scripts/check_help_translations.mjs`.

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
- a translation's title is over 80 characters, its summary over 200 or more than one sentence, a title / summary / heading carries markup, two headings share an anchor, or a string has bad markup, an emoji, different links (by target, in order) or a different number of `**labels**` from the English it translates;
- `scripts/check_help_translations.mjs` fails (below);
- any per-locale JSON is stale.

`apps/web/src/lib/i18n/locale_reach.test.ts` scans the pt-PT and pt-BR translations for the other variant's words and for `tu`, as it does the catalogues and the Learn guides.

CI also runs `node scripts/gen_help_guides.mjs --check`, `node scripts/check_help_translations.mjs` and both scripts' unit suites in `build-web`, before the install. `markup.test.ts` and `catalogue.test.ts` pin the parser and the index; `tests-e2e/help/help-centre.spec.ts` pins the pages, search, anchors, the account-menu path and the event page's HelpLink.

## Translation

Guide text is translated per guide and per locale, at `apps/web/src/lib/help/translations/<locale>/<id>.ts`:

```ts
import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: '<id>',
	source: '<16 hex digits>',
	title: '…',
	summary: '…',
	sections: [/* the guide's sections, block for block, words translated */],
};
```

A translation carries **only words**. Kind, category, audience, requirements, platforms, routes and related guides are always the English guide's; the sections must line up with the guide's (same count, same block types and note tones, same number of items). Inside the text, `[[guide:…|` and `[[route:…|` stay byte-for-byte (only the label after `|` is translated) and a `**label**` holds the label the app shows in that locale — the matching key in `lib/i18n/locales/<locale>.ts` or the locale's ARB.

**Fallback is per guide.** `localizeGuide` returns the English guide, marked `lang: 'en'`, when there is no translation or it does not line up. Web bundles English and, for any other locale, fetches the generated `/help-guides/guides.<locale>.json` once (the help layout's load waits for it, so a help page opens in the reader's language); a failed fetch leaves English. A guide shown in English in another locale carries `help.guideInEnglish` (web) / `helpGuideInEnglish` (mobile) under its summary, and its text is marked with its own `lang`.

**Staleness fails CI** (§ R7I18N-1). `source` is `node scripts/check_help_translations.mjs --hash <id>`: the first 16 hex digits of the SHA-256 of the English guide's title, summary and section text, so editing any of those words, and nothing else, makes the six translations stale. The guard then fails, naming each file and the new hash. Re-translate the changed strings and set the new `source`; or, for a fix that cannot wait, delete the stale files, which puts the guide back to English (with the note) in those locales until it is translated again. Nothing checks hashes at run time: a stale translation cannot reach `main`.

**Translating.** Run the `i18n-translator` agent per locale with a JSON batch of the guide strings, then the `i18n-checker` agent over its output, and apply the checker's corrections; the agents keep the catalogues' terminology. Write each file with `source` set to the hash above, run `pnpm gen:help-guides`, and commit the translation files with the regenerated JSON.
