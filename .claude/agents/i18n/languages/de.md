# German (de)

One German catalogue for every German-speaking reader: `app_de.arb`
(mobile) and `locales/de.ts` (web). Tags like `de-AT` / `de-CH` fall back
to it (`BASE_TO_LOCALE` in `apps/web/src/lib/i18n/locale.ts`,
`locale_support.dart` on the phone), so write standard German, not
Austrian or Swiss usage (`ß`, not Swiss `ss`).

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — `du`, everywhere

The app addresses the runner as **du** (lower case, as every shipped string
writes it): `du`-forms in 445 / 723 strings against a handful of
`Sie` slips. decisions.md § 1675 records the choice ("the mobile ARB
onboarding copy decides the register (`du` on German …)").

- `clubInviteEnterCodeError` (mobile): "Gib den Einladungscode aus deinem Link ein."
- `common.unsavedBody` (web): "Du hast ungespeicherte Änderungen. Ohne Speichern verlassen?"
- `rateLimit.generic` (web): "Du machst das zu schnell – bitte warte {wait} und versuche es erneut."

Buttons are infinitives ("Speichern", "Beitreten", "Lauf pausieren"),
not `du`-imperatives; sentences and hints use the `du`-imperative ("Gib …
ein", "Füge … ein", "prüfe deine Verbindung"). TTS cues are short
`du`-imperatives or nominal ("Halte ein gleichmäßiges Tempo.",
"Links abbiegen", "Tempo erhöhen").

**Register slips already shipping (findings, don't copy them):**
mobile `discardChangesBody` and `privacyZonesDiscardBody` ("Sie haben
nicht gespeicherte …", while web's twin `common.unsavedBody` says "Du
hast"); mobile TTS `ttsSlightLeft` / `ttsSlightRight` ("Halten Sie sich
links/rechts") and `ttsUturn` ("Wenden Sie") among `du`/neutral TTS cues;
web `checkpoint.boardNoCheckpoints` ("Fügen Sie zuerst …") and
`settingsAccount.exportReasonSignedOut` ("Ihre Sitzung ist abgelaufen").
Capitalised `Sie` that means *she/it/they* ("Sie hat kaum Höhenunterschied"
for a Route) is correct and not a slip.

## Spelling and style authority

**Duden** (current reformed spelling). Nouns capitalised; compounds
written closed or hyphenated, never open (`Health-Connect-Berechtigung`,
`Wear-OS-Watch-App`, `Trainingsplan`, not `Training Plan`). `E-Mail`
(32 / 39; the two `Email` occurrences are slips). Anglicisms the app has
naturalised are capitalised nouns: `Workout`, `Feed`, `Follower`,
`Challenge`, `Kudos`, `Club`, `Gym`, `Coach`, `Splits`.

## Typography

- Quotes: German low-high **„…“** (41 / 39 strings), e.g.
  `routePickerEmptyNoMatch` "Keine Routen passen zu „{query}“". Straight
  `"` is a slip (16 / 7 strings).
- Ellipsis: **…** (U+2026); `...` appears only where the English has it.
- Dashes: the English em dash is kept spaced ("— "), and many strings use
  the spaced en dash ` – ` (74 / 129) for the same job; either is
  accepted, follow the neighbouring keys.
- Numbers in literal samples use the decimal comma (`setupUnitKmSample`
  "5,0 km · 5:00 /km"); everything else arrives pre-formatted.
- No space before `:` `!` `?`.

## Plurals

`one` = exactly 1, `other` otherwise. ARB: `{count, plural, one{…}
other{{count} …}}`; web: `{n, plural, one {# …} other {# …}}`.

## Running glossary (what the catalogues already use)

| English | German | Evidence / note |
|---|---|---|
| run (noun) | Lauf / Läufe | `nav.runs` "Läufe"; activity type `activityType.run` "Laufen"; nav verb `navRun` "Lauf" |
| pace | **Tempo** | 4 mobile + 8 web stat labels (`runStatPace`, `runDetail.pace`). See inconsistency 1 |
| split | Splits | `runDetailSectionSplits`, `prefs.cue.splits` |
| lap | Runde / Runden | |
| personal record / PR | Persönlicher Rekord / Persönliche Rekorde; badge **PR** | `dash.personalRecordsTitle`; mobile `dashboardSectionPersonalBests` says "Persönliche Bestleistungen"; "Bestzeit" for a time-based best |
| tempo run | Tempo | `workoutKindTempo` — collides with *pace*, see inconsistency 1 |
| interval | Intervall (a step) / Intervalle (workout kind) | `planNewPaceInterval`, `workoutKind.interval` |
| long run | Langer Lauf | `workoutKind.long` |
| easy run | Locker | `workoutKind.easy` |
| elevation gain | Höhenmeter | `routeDetail.statElevationGain`, `runStatElevation`; mobile also "Anstieg", web `dash.elevationGain` "Höhengewinn" — inconsistency 3 |
| heart rate / HR | Herzfrequenz / HF | `HF` only in tight stat labels |
| heart rate zone | Herzfrequenzzone(n) | |
| cadence (steps/min) | Schrittfrequenz | `runStatCadence`. "Rhythmus" in `discover.cadenceLabel` means *recurrence* — a different sense |
| training plan | Trainingsplan / Trainingspläne; short Plan / Pläne | |
| race | Rennen (nav, tabs, calendar `Rennkalender`); Wettkampf (workout kind, run source) | |
| finish | Ziel (finish line); Beendet (status); Beenden (action) | "Ziel" also means *goal* — disambiguate by context |
| DNF | DNF | kept as-is on both surfaces |
| route | Route / Routen | dominant; web also "Strecke" (`eventEditor.route`, `routeHeatmap.*`) — inconsistency 4 |
| segment | Segment / Segmente | |
| club | Club / Clubs | 45 / 97 strings; "Verein" in plan-template copy — inconsistency 5 |
| event | Event / Events | |
| gym | Gym | `nav.gym`, `gymTitle` |
| nutrition | Ernährung | |
| log (verb) | Erfassen | `navLog` |
| streak | Serie | "Beste Serie" |
| goal | Ziel / Ziele | |
| coach | Coach; AI Coach = **KI-Coach** | `nav.coach` |
| auto-pause | — | no catalogue string yet; build from "Pause" / "pausieren" ("Lauf pausiert") → "Auto-Pause", and flag it as a new term |
| kudos | Kudos ("Kudos geben", "Kudos zurücknehmen") | |
| workout | Training (dominant) / Workout | |
| warm-up / cool-down / recovery | Aufwärmen / Auslaufen / Erholung | cool-down also "Abwärmen", "Abkühlen" — inconsistency 6 |
| save / settings / feed | Speichern / Einstellungen / Feed | |
| social | Sozial (mobile `navSocial`) / Community (web `nav.social`) | inconsistency 7 |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **pace vs tempo run.** "Tempo" names both *pace* (dominant) and the
   *tempo run* workout kind; and mobile mixes "Pace" for pace in
   `workoutReviewColPace`, `shareCardStatPace`, `ttsPaceKm`, `ttsPaceMi`.
   New pace strings: "Tempo"; flag any string where both senses meet.
2. **Sie slips** — listed under Register.
3. **elevation gain**: Höhenmeter / Anstieg / Aufstieg / Höhengewinn.
4. **route**: Route vs Strecke on web.
5. **club**: Club vs Verein (`planNewTemplate*`, `planDetailPublish*`).
6. **cool-down**: Auslaufen / Abwärmen / Abkühlen.
7. **social destination**: Sozial (mobile) vs Community (web).

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Health Connect, Apple Health (kept
in English — Apple's German app is "Health"), Apple Watch, Wear OS,
HealthKit, GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP, DNF.
VO₂ max is written **VO₂max** (`metric.vo2max.label`); `watchMetricVo2Max`
"VO2max" is the ASCII form for the watch font. Identifiers, route paths,
ICU keywords, `{placeholders}`.

## Provenance

The German strings were machine-extracted and model-translated; no native
speaker has reviewed them yet (`docs/product/followups.md` › "Native
review of machine-extracted translations"). Flag anything you're unsure
of rather than guessing.
