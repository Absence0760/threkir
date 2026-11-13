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

**Register slips:** none left. The last ones (mobile `discardChangesBody`,
`privacyZonesDiscardBody`, the TTS cues `ttsSlightLeft` / `ttsSlightRight` /
`ttsUturn`, web `checkpoint.boardNoCheckpoints` and
`settingsAccount.exportReasonSignedOut`) moved to `du` on 2026-11-13 (#1374
round 3.6).
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

- Quotes: German low-high **„…“**, always, e.g.
  `routePickerEmptyNoMatch` "Keine Routen passen zu „{query}“";
  a straight `"` in a message fails CI (`messages_parity.test.ts` on web, `architecture_guards_test.dart` on mobile — ARBs and the `gen/` getters). The last 8 web and 16 mobile straight-quoted strings moved to „…“
  2026-10-14.
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
| average HR (stat label) | **Ø HF** (`runDetailStatAvgHr`, `runDetail.avgHr`, the share card `shareCardStatHeartRate` / `runShare.statHeartRate`) | settled 2026-11-13; never "Ø Puls" |
| heart rate zone | Herzfrequenzzone(n) | |
| max HR / resting HR | **Maximalpuls** / **Ruhepuls** in every string — field labels ("Maximalpuls (bpm)"), buttons ("Maximalpuls festlegen"), prose and errors ("Gib einen Maximalpuls zwischen …"); coordinated "Ruhe- und Maximalpuls". Both masculine (*einen gemessenen Maximalpuls*, *trag ihn ein*) | settled 2026-11-12; never "maximale Herzfrequenz" / "Max. HF" / "Max. Puls" / "Ruheherzfrequenz" / "Ruhe-HF". *Herzfrequenz* stays for heart rate in general |
| cadence (steps/min) | Schrittfrequenz | `runStatCadence`. "Rhythmus" in `discover.cadenceLabel` means *recurrence* — a different sense |
| training plan | Trainingsplan / Trainingspläne; short Plan / Pläne | |
| race | Rennen (nav, tabs, calendar `Rennkalender`); Wettkampf (workout kind, run source) | |
| mapped run (personal heatmap) | **Lauf auf der Karte** — „Noch keine Läufe auf der Karte“ | settled 2026-11-13 (#1374 round 3.5), both surfaces; never „erfasst“, which is *logged* |
| club (every surface, including plan templates and race claims) | **Club** / Clubs; compounds hyphenated as the catalogue already writes them (Club-Vorlage, Club-Admins) or closed where already closed (Clubmitglieder, Clubkopie, Clubbeitrag) | settled 2026-11-13 (#1374 round 3.5), both surfaces; never Verein — this closes inconsistency 5 |
| finish | Ziel (finish line); Beendet (status); Beenden (action) | "Ziel" also means *goal* — disambiguate by context |
| DNF | DNF | kept as-is on both surfaces |
| route (a saved route: one you build, generate, save, attach to an event, back up or find in route discovery) | **Route** / Routen; compounds Routenpräferenz, Routenseite, Routenliste, Routensuche, Routenansicht; "die Linie der Route" for its line | settled 2026-11-13 (#1374 round 3.7), web and mobile; this closes inconsistency 4. **Strecke** stays for a *course* (English "course": a race, event or park course, Parkstrecke, Rennstrecke, Streckenhinweis, Streckenmarker) and for the path a run or course follows ("entlang der Strecke", "Streckenverlauf", "% der Strecke") |
| segment | Segment / Segmente | |
| event (a club event: run, class, social; the entity, its page and its editor) | **das Event** / die Events; genitive *des Events* / *dieses Events* ("Neues Event", "Dieses Event wurde abgesagt", "Ein Event, zu dem du gehst", "nach dem Event", pronoun *es*). Compounds hyphenated as the catalogue already writes them: **Event-Seite**, **Event-Typ**, Event-Foto, Event-Termin, Event-Editor, Club-Event, Kurs-Event; closed only where already closed (Eventorganisator) | settled 2026-11-13 (#1374 round 3.6), web, mobile and help: 61 strings moved off "Veranstaltung" / "Veranstaltungstyp" / "Veranstaltungsseite"; never "Veranstaltung", never "Eventseite". "Veranstalter" (the organiser, "GO durch Veranstalter") is a person and stays |
| gym | Gym | `nav.gym`, `gymTitle` |
| nutrition | Ernährung | |
| log (verb) | Erfassen | `navLog` |
| streak | Serie | "Beste Serie" |
| goal | Ziel / Ziele | |
| coach | Coach; AI Coach = **KI-Coach**. Inflected per Duden: genitive **des Coachs** ("die Antwort des Coachs", "Antwort des KI-Coachs"), plural **die Coachs** ("Meine Coachs") | `nav.coach`; settled 2026-11-13 (#1374 round 3.8), never "des Coaches" / "Coaches" |
| AI disclosure | **KI-Hinweise** (plural: "die aktualisierten KI-Hinweise", "KI-Hinweise ansehen", "akzeptiere sie") | settled 2026-11-13; never the singular "KI-Hinweis" or "KI-Information" (the plan assistant's consent error moved off it in round 3.6). Consent wording: CISO/counsel review |
| auto-pause | — | no catalogue string yet; build from "Pause" / "pausieren" ("Lauf pausiert") → "Auto-Pause", and flag it as a new term |
| kudos | Kudos ("Kudos geben", "Kudos zurücknehmen") | |
| workout | Training (dominant) / Workout | |
| warm-up / cool-down / recovery | Aufwärmen / Auslaufen / Erholung | cool-down also "Abwärmen", "Abkühlen" — inconsistency 6 |
| save / settings / feed | Speichern / Einstellungen / Feed | |
| chat message | **Chatnachricht** (closed compound, Duden) | settled 2026-10-21; never "Chat-Nachricht" |
| social | Sozial (mobile `navSocial`) / Community (web `nav.social`) | inconsistency 7 |
| arm / armed (race control) | **scharf schalten** (closed: "Rennen scharf schalten", "Schalte das Rennen scharf", "scharf geschaltet", noun "Scharfschalten", "Trotzdem scharf schalten", "Früher scharf schalten"); state label **Bereit** / "Rennen bereit", "Nicht scharf geschaltet" | owner decision 2026-11-10, replacing "scharfstellen"; never "scharfstellen" / "scharfgestellt" / "aktivieren"; the Wear watch shows "RENNEN BEREIT" |
| GO (the start signal) | **GO** in every string and guide: "GO durch Veranstalter", "Geplanter GO", "nach GO", "bei GO"; the button is **GO** on the web and in the phone app (English renamed the phone's *Fire Go* to *GO*); the action in prose is "GO geben" ("Sobald du GO gegeben hast"), the signal is masculine, *der GO* ("einen GO", "derselbe GO-Zeitpunkt") | settled 2026-11-10; never "LOS" / "Los" / "START" / "Startschuss" / "GO geben" as the button label. The Wear pause screen's "Los" (resume) is a different control |
| self-timed (race) | **selbstgestoppt** ("selbstgestopptes Rennen", "Selbstgestoppter Zeitraum") | settled 2026-11-10; never "selbst gezeitet" / "selbst gestoppt" |
| gun time / chip time | **Bruttozeit** / **Nettozeit** (closed compounds); coordinated "Brutto- und Nettozeit"; short split "Brutto {gun} · Netto {chip}" | settled 2026-11-10; never "Brutto-Zeit" / "Netto-Zeit" |
| set up (a race created automatically before its start) | **angelegt** ("Das Rennen wird einen Tag vor dem Start angelegt") | keeps it apart from *arm* |
| undo | **Rückgängig** (button), "Rückgängig machen" (verb), setting "Zeitfenster für Rückgängig" | settled 2026-11-12; never "Widerrufen" / "Widerruf", which is the legal *revoke* (consent withdrawal, coach-invite revoke) |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **pace vs tempo run.** "Tempo" names both *pace* (dominant) and the
   *tempo run* workout kind; and mobile mixes "Pace" for pace in
   `workoutReviewColPace`, `shareCardStatPace`, `ttsPaceKm`, `ttsPaceMi`.
   New pace strings: "Tempo"; flag any string where both senses meet.
2. **Sie slips** — resolved 2026-11-13 (see Register).
3. **elevation gain**: Höhenmeter / Anstieg / Aufstieg / Höhengewinn.
4. **route**: Route vs Strecke — resolved 2026-11-13: Route for a saved route, Strecke for a course (see the glossary row).
5. **club**: Club vs Verein — resolved 2026-11-13: always Club (see the glossary row).
6. **cool-down**: Auslaufen / Abwärmen / Abkühlen.
7. **social destination**: Sozial (mobile) vs Community (web).

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Health Connect (Google keeps it in
German too), Apple Health (kept in English — Apple's German app is "Health"), Apple Watch, Wear OS,
HealthKit, GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP, DNF.
VO₂ max is written **VO₂max** (`metric.vo2max.label`); `watchMetricVo2Max`
"VO2max" is the ASCII form for the watch font. Identifiers, route paths,
ICU keywords, `{placeholders}`.

## Provenance

The German strings were machine-extracted and model-translated; no native
speaker has reviewed them yet (`docs/product/followups.md` › "Native
review of machine-extracted translations"). Flag anything you're unsure
of rather than guessing.
