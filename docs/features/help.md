# In-app help guides

> **Status:** Framework shipped web (2026-10-13): `/help`, `/help/[id]`, `/help/search`, the per-page **How this works** link and the InfoTip guide link. Mobile renders the same guides from generated per-locale JSON assets. Every guide is **translated into all six non-English locales** (de, fr, es, ja, pt-PT, pt-BR); a guide with no translation falls back to English with a note, and a translated string made from older English fails CI, naming that string. Seven guides carry a **text-free, theme-painted SVG illustration** (2026-10-14), on web and both phone twins. ADRs: [decisions.md § 1846](../architecture/decisions.md), § 1871, § 1872, § 1873, § 1898.

In-app help is a **reference to the app itself**, written for someone using it: what a feature does, who it is for, where it lives and what it needs first. It is a different surface from the public [Learn guides](learn.md) (`/learn`), and the two stay separate:

| | `/learn` | `/help` |
|---|---|---|
| Reader | anyone, signed out, arriving from search | someone using the app; readable signed out (§ 1866), because the public live-event page links spectators to it |
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
                    guide's words in one locale, plus a `sources` hash per string
  illustration.ts   ILLUSTRATION_PALETTE, illustrationProblems (the SVG
                    allow-list), themeIllustration — pure, no run-time imports
  illustrations/<id>.svg
                    one text-free diagram per file (§ Illustrations)
  translate.ts      translatableStrings / structureProblems / localizeGuide /
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
  HelpIllustration.svelte  inlines one build-time illustration, themed
  HelpLink.svelte        "How this works" for a route id
  HelpSearchForm.svelte  GET form to /help/search
apps/web/src/routes/help/
  +layout.ts             loads the app locale's guides before a help page renders
  +page.svelte           contents: categories, audience chips, search
  [id]/+page.svelte      one guide: badges, On this page, sections, related
  search/+page.svelte    ranked results for ?q=
scripts/gen_help_guides.mjs        → apps/mobile_{android,ios}/assets/help/guides.<locale>.json
                                     apps/web/static/help-guides/guides.<locale>.json (not en)
                                     apps/mobile_{android,ios}/assets/help/illustrations/<id>.svg (byte copies)
scripts/check_help_translations.mjs  the staleness guard (§ Translation)
scripts/check_help_illustrations.mjs the illustration guard (§ Illustrations)
```

`index.ts` only binds the Vite glob to `catalogue.ts`; everything testable lives in the pure module, so the unit suite (raw `tsx`, no Vite) builds the same index from the files on disk.

### The contract

`types.ts` is shared with the mobile renderer, so a shape change there is a change to the Flutter reader too. A guide carries `id` (kebab-case, equal to the file name), `title` (≤ 70 chars), `summary` (≤ 160 chars, one sentence), `kind` (`start` / `how-to` / `explainer`), `category`, `audience[]`, optional `requires[]` (`pro`, `club-admin`, `race-director`, `stripe-connected`, `paid-rail-live`), `platforms[]` (where the flow exists **today**), optional `routes[]` (SvelteKit route ids it describes), `sections[]` of blocks (`p`, `steps`, `list`, `note` with tone `tip` / `caution`, `illustration` with a file `id` and `alt` text) and optional `related[]` guide ids.

### Markup

Every block string may carry exactly four forms, and nothing else — no HTML, no markdown headings, no emoji:

| Markup | Renders as |
|---|---|
| `**Save**` | the on-screen label, bold — the exact label in the guide's language (in a translation, that locale's catalogue string) |
| `*only once*` | emphasis (asterisks must stand apart from a word, so `5*3` stays text) |
| `[[guide:<id>\|label]]` | a link to `/help/<id>` |
| `[[route:<route id>\|label]]` | a link to the screen; a route id with params (`/clubs/[slug]`) has no single address and renders as plain text |

Titles, summaries, section headings and illustration alt text take no markup at all. Section anchors are `sectionId(heading)`; the guide page and "On this page" both use it. Letters of any script survive into the anchor, so a Japanese heading has one too (kana lose their voicing marks, the same folding search uses).

### Search and ranking

`searchGuides(q)` folds case and accents (`cafe` finds `Café`), requires **every** word to appear somewhere, and ranks a word in the title (100) over the summary (10) over the body (1, headings and block text with markup stripped). Ties keep contents order. The query lives in the URL (`/help/search?q=`), so a search can be bookmarked and gone back to.

### Entry points

- **Account menu → Help.** The sidebar's account popover lists the secondary destinations; it serves the desktop sidebar and the narrow-viewport rail alike.
- **`<HelpLink route="/the/route/[id]" />`** — "How this works" near a page title: one guide links straight to it, several open a short disclosure list, none renders nothing (and fails the guard). Mount it with a literal route id.
- **`<InfoTip guide="<id>" …>`** — adds "Read the guide" after the tip's own text.

### Mobile

`node scripts/gen_help_guides.mjs` (`pnpm gen:help-guides`) imports every guide and translation file with Node's built-in type stripping — they import nothing at run time, so no `tsx` and no install — and writes one JSON array per app locale (sorted by category then id, keys in contract order, each guide carrying `lang`) to both twins' `assets/help/guides.<locale>.json`, registered under `flutter: assets:` (the `assets/help/` directory) in both `pubspec.yaml`s. Every file holds every guide: translated where a translation exists, else English with `"lang": "en"`. `help_loader.dart` reads the app locale's file (`helpLocaleTag`, so a bare `pt` reads `pt-PT`) and falls back to `guides.en.json` when that file is missing, unreadable or empty; the guide screen shows `helpGuideInEnglish` under the summary when a guide's `lang` is not the app's. The mobile lane owns the route-id → screen map; an unmapped `[[route:]]` renders as plain text there too. Illustration files ship as `assets/help/illustrations/<id>.svg` (a second `flutter: assets:` entry, since an asset directory is not recursive) and render through `flutter_svg` (§ Illustrations).

## Illustrations

A guide may carry `{ type: 'illustration', id: '<id>', alt: '<what the picture shows>' }`, drawn from `apps/web/src/lib/help/illustrations/<id>.svg`. They are diagrams, not screenshots (§ 1898): a screenshot carries English UI text into six other locales, needs a copy per theme, and rots on every UI change; a text-free drawing is one file for every locale and both themes, and only its `alt` is translated.

**Colour is theme-driven through placeholders.** A file paints with `currentColor` (the ink), `none`, and exactly seven placeholder colours, one per token. flutter_svg reads no CSS variables, so the file cannot hold `var(...)`; instead each renderer swaps the placeholders for its own theme:

| Token | Placeholder | Web (`HelpIllustration.svelte`) | Mobile (`help_illustration.dart`) |
|---|---|---|---|
| ink | `currentColor` | `--color-text` | `onSurface` (via `SvgTheme`) |
| `accent` | `#ff00a1` | `--color-primary` | `primary` |
| `accent-soft` | `#ff00a2` | `--color-primary-light` | `primaryContainer` |
| `muted` | `#ff00a3` | `--color-text-tertiary` | `outline` |
| `surface` | `#ff00a4` | `--color-surface` | `surface` |
| `tint` | `#ff00a5` | `--color-bg-tertiary` | `surfaceContainerHighest` |
| `positive` | `#ff00a6` | `--color-success` | `AppSemanticColors.success` |
| `caution` | `#ff00a7` | `--color-warning` | `AppSemanticColors.warning` |

The placeholders are deliberately loud magenta, so a renderer that forgot one shows it at once. The palette lives in `ILLUSTRATION_PALETTE` (`illustration.ts`); `helpIllustrationPalette` in Dart is pinned to it by `help_illustration_test.dart`. Web imports every file at build time (`import.meta.glob(..., '?raw')`), rewrites each placeholder to `var(--illus-<token>)` and inlines it with `{@html}` — the only `{@html}` in help, and safe because the string is a committed, guard-checked file chosen by id, never guide or fetched text. The drawing is `aria-hidden`; the wrapping `role="img"` carries the alt. Mobile wraps `SvgPicture.asset` in a `Semantics(image: true, label: alt)` and renders nothing if the file is missing. Opacity attributes are kept, so a `fill-opacity` tint stays a tint in both themes.

**Adding an illustration.**

1. Draw `illustrations/<id>.svg` by hand (or with a script you commit): `viewBox="0 0 320 200"`, no width / height, rounded strokes, generous whitespace, under 4 KB, only the shape elements and painting attributes `illustrationProblems` allows. Keep words out of it; what the reader needs to read goes in the guide text.
2. Look at it in both themes before committing: substitute the placeholders for the light and dark token values and export a PNG with Inkscape (`inkscape --export-type=png --export-width=480 --export-filename=out.png in.svg`).
3. Add the block to the guide, usually as the last block of the section it explains (appending keeps every existing translation path where it was), and add the same block, with `alt` translated and its `sources` hash, to every translation.
4. Run `pnpm gen:help-guides` (it copies the file into both twins' `assets/help/illustrations/`), `node scripts/check_help_illustrations.mjs` and `node scripts/check_help_translations.mjs`.

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
- a translation's title is over 80 characters, its summary over 200 or more than one sentence, a title / summary / heading carries markup, or a string has bad markup, an emoji, different links (by target, in order) or a different number of `**labels**` from the English it translates;
- in any shipped locale (`SUPPORTED_LOCALES`), the guide as shown — `localizeGuide`'s merge, English where no translation lines up — renders two equal section headings (the page keys its sections on them, so a duplicate throws `each_key_duplicate`) or two headings sharing an anchor, or a locale's translations directory loads nothing;
- `scripts/check_help_translations.mjs` fails (below);
- an illustration's alt text (English or translated) is empty, over 240 characters or carries markup;
- `scripts/check_help_illustrations.mjs` fails: an illustration holds anything outside the allow-list (so a `<text>`, `<script>`, `<foreignObject>`, `<image>`, `<style>`, an `href`, an event handler or a `url(...)`), paints a colour outside the token set, has the wrong view box or a fixed size, is over 4 KB, or is not `<kebab-case-id>.svg`; a block names no file or has no alt; or a file is referenced by no guide;
- any per-locale JSON is stale.

`apps/web/src/lib/i18n/locale_reach.test.ts` scans the pt-PT and pt-BR translations for the other variant's words and for `tu`, as it does the catalogues and the Learn guides.

CI also runs `node scripts/gen_help_guides.mjs --check`, `node scripts/check_help_translations.mjs`, `node scripts/check_help_illustrations.mjs` and the three scripts' unit suites in `build-web`, before the install. On mobile, `help_illustration_test.dart` pins the palette to the web contract, compiles every shipped file under flutter_svg and pins the guide screen's labelled render. `markup.test.ts` and `catalogue.test.ts` pin the parser and the index; `tests-e2e/help/help-centre.spec.ts` pins the pages, search, anchors, the account-menu path and the event page's HelpLink.

## Translation

Guide text is translated per guide and per locale, at `apps/web/src/lib/help/translations/<locale>/<id>.ts`:

```ts
import type { GuideTranslation } from '../../types';

export const translation: GuideTranslation = {
	id: '<id>',
	title: '…',
	summary: '…',
	sections: [/* the guide's sections, block for block, words translated */],
	sources: {
		title: '<16 hex digits>',
		summary: '<16 hex digits>',
		's0.heading': '<16 hex digits>',
		's0.b0': '<16 hex digits>',     // a paragraph or note
		's0.b1.i0': '<16 hex digits>',  // a step or list item
		// … one entry per translated string
	},
};
```

A translation carries **only words**. Kind, category, audience, requirements, platforms, routes and related guides are always the English guide's; the sections must line up with the guide's (same count, same block types, note tones and illustration ids, same number of items). Inside the text, `[[guide:…|` and `[[route:…|` stay byte-for-byte (only the label after `|` is translated) and a `**label**` holds the label the app shows in that locale — the matching key in `lib/i18n/locales/<locale>.ts` or the locale's ARB.

**Fallback is per guide.** `localizeGuide` returns the English guide, marked `lang: 'en'`, when there is no translation or it does not line up. Web bundles English and, for any other locale, fetches the generated `/help-guides/guides.<locale>.json` once (the help layout's load waits for it, so a help page opens in the reader's language); a failed fetch leaves English. A guide shown in English in another locale carries `help.guideInEnglish` (web) / `helpGuideInEnglish` (mobile) under its summary, and its text is marked with its own `lang`.

**Staleness fails CI, string by string** (§ 1871, § 1873). Every translated string has a path — `title`, `summary`, `s<n>.heading`, `s<n>.b<m>` for a paragraph, a note or an illustration's alt, `s<n>.b<m>.i<k>` for a step or list item, all counted from 0 (`translatableStrings` in `translate.ts`) — and `sources` records, per path, the first 16 hex digits of the SHA-256 of the English string it was translated from. Editing one English string stales exactly that string in every locale. `node scripts/check_help_translations.mjs` then fails with one line per stale string, naming the file, the path, where it sits ("section 3 block 1 item 2"), what the English now reads and the new hash. It also fails a `sources` map that misses a string or names one the guide does not have, and a translation whose sections or blocks no longer line up (an English edit that adds or removes a block or item is a structure change, reported as such rather than hash by hash). Nothing checks hashes at run time: a stale translation cannot reach `main`.

**Re-translating a stale string.** Take the paths the guard names, send the new English for those strings alone to the `i18n-translator` agent (keyed `web:help.<id>.<path>`, the same keys the batches use), check its output with the `i18n-checker`, put each corrected string at its path in the translation file and set that path's `sources` entry to the "now" hash the guard printed (`node scripts/check_help_translations.mjs --hash <id> <path>` prints one hash, `--hash <id>` the whole map). After a structure change, rewrite the affected section to line up and re-hash it. For a fix that cannot wait, deleting the locale's file instead puts the whole guide back to English (with the note) in that locale until it is translated again; there is no per-string English fallback, so a reader never gets a guide in two languages.

**Translating.** Run the `i18n-translator` agent per locale with a JSON batch of the guide strings, then the `i18n-checker` agent over its output, and apply the checker's corrections; the agents keep the catalogues' terminology. Write each file with `sources` set to `--hash <id>`'s map, run `pnpm gen:help-guides`, and commit the translation files with the regenerated JSON.
