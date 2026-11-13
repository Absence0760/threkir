# French (fr)

One French catalogue for every French-speaking reader: `app_fr.arb`
(mobile) and `locales/fr.ts` (web). `fr-CA`, `fr-BE`, `fr-CH` fall back
to it, so write standard metropolitan French.

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — `vous`, throughout

**Use `vous`.** decisions.md § 1675 records that "the mobile ARB onboarding
copy decides the register (… `vous` on French …)", and both French
catalogues are now `vous` throughout: the last informal strings (about 590 on
web, 220 on the phone, plus the help-guide labels that quote them) moved on
2026-10-15. Re-measured then at `1fa9b9a2e`: web 912 strings carry `vous` /
`votre` / `vos` and none carry `tu`; the phone 573 and none (the one web
marker hit, `prefsHub.trainingSummary`, is "le ton du coach" — *tone*).

Informal strings crept back in with the season planner, the streamer overlay,
the plan-recovery hints and a few dashboard, club and workout lines; the
last 41 mobile / 49 web strings and one help guide moved to `vous` on
2026-11-12. When you check a batch, grep for `tu`/`ton`/`ta`/`tes`/`-toi`
*and* for bare `-e`/`-s` imperatives ("Réessaie", "Choisis", "Suis",
"Passe à Pro"): most of these slipped in without a pronoun.

- `discardChangesBody` (mobile) and `common.unsavedBody` (web): "Vous avez des modifications non enregistrées. Quitter sans enregistrer ?"
- `clubInviteEnterCodeError` (mobile): "Saisissez le code d'invitation de votre lien."
- `rateLimit.generic` (web): "Vous faites cela trop rapidement — veuillez patienter {wait} et réessayer."

That includes copy written in the user's own voice to someone else — coach
suggestion chips ("Créez-moi un plan…"), the AI plan-adjust example
(« déplacez ma sortie longue à samedi »), the live-share subject ("Suivez-moi
en direct") — and the spoken cues ("Accélérez de {sec} secondes"), so a
string never mixes the two. A batch string in `tu` is a regression, not a
neighbour to match.

Setting and field hints that describe what a control does stay in the third
person ("Ajoute Muscu à la barre latérale…", "Copie chaque nouvelle course…");
where the English is an instruction, use the `vous` imperative or an
infinitive, never a bare `-e` form that reads as `tu`.

Buttons are infinitives ("Enregistrer", "Mettre en pause", "Rejoindre");
instructions use the `vous` imperative ("Saisissez", "Collez").

## Spelling and style authority

**Académie française / Le Robert** usage with the 1990 rectifications
tolerated; Office québécois de la langue française (OQLF) for software
vocabulary is a good tiebreaker. `e-mail` (30 / 38; `courriel` is unused),
`app` (18 / 11) over `appli` / `application`. Accents on capitals
(`Événements`, `À`).

## Typography

- Quotes: **« … »** with a space inside (nearly all a plain space, one
  non-breaking — see the spacing note below), always; a straight `"` in a message fails CI (`messages_parity.test.ts` on web, `architecture_guards_test.dart` on mobile — ARBs and the `gen/` getters). The last 3 web
  and 4 mobile straight-quoted strings moved to « … » 2026-10-14.
- Space before `;` `:` `!` `?` and `»` — the catalogues use a **plain
  space** (333 / 413 strings) and a non-breaking one only in 10 / 4. Follow
  the majority; a narrow no-break space (U+202F) is better typography and
  is a recorded finding, not something to change piecemeal.
- Apostrophe: straight `'`, always. The last curly `’` (213 mobile, 225
  web, 26 in six help guides, the season planner's among them) moved to
  `'` on 2026-11-13.
- Ellipsis **…**; spaced em dash ` — ` as in English.
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals

`one` covers **0 and 1**, `other` the rest. Never write a literal `1` in a
`one` branch (it renders "1 …" for a count of 0; the last ones moved to
`{count}` in § 2497). Use `{count}` (ARB) / `#` (web). The same 0 arrives
without a digit when the plural is the **whole message** and its `one`
branch is the sentence for exactly one — "Invitation envoyée", "Cette
semaine est refaite…" read as true for 0. Name the count in that branch
("{count} invitation envoyée") or give 0 its own `=0{…}` branch. A plural
inside a longer sentence is agreement ("{n, plural, one {est en} other {sont
en}}") and the singular is right for 0 in French, so leave it. Both rules
are guards: `l10n_parity_test.dart` and `messages_parity.test.ts`.

## Running glossary (what the catalogues already use)

| English | French | Evidence / note |
|---|---|---|
| run (noun) | course / courses; nav verb **Courir**; group run **Course en groupe**; easy run **course facile** | `nav.runs` "Courses", `navRun` "Courir". **Never « sortie » for a run** — settled 2026-11-12, when 31 mobile / 58 web strings and 8 help guides moved from « sortie » to « course ». « Sortie » stays only in **sortie longue** (long run) and its non-run senses: exit / *Sortie* at a checkpoint, output, an app's release, off-route (« sortie d'itinéraire »), a bike ride (« sortie vélo »), a social outing. Where a string also names a race, keep the run as « course (enregistrée) » and call the race **épreuve** (or « compétition », « jour J ») rather than writing « course » twice — see inconsistency 1 |
| pace | Allure | all 6 / 8 stat labels |
| split | **Splits** (section); per-km cue "Intermédiaires" | `runDetailSectionSplits`, `prefsCueSplits`. Web `prefs.cue.splits` "Fractionnés" is a mistranslation (= interval training) — inconsistency 2 |
| lap | Tour / Tours | |
| personal record / PR | Record personnel / Records personnels; badge **PR** (web) / "Record" (mobile `gymPrBadge`) | |
| tempo run | Tempo | `workoutKindTempo` |
| interval | Intervalle (a step) / **Fractionné** (workout kind) | `workoutKind.interval` |
| long run | Sortie longue | |
| easy run | Facile | |
| elevation gain | **Dénivelé positif** | web `routeDetail.statElevationGain`; mobile "Montée", "Dénivelé +", "Dénivelé" — inconsistency 5 |
| heart rate / HR | Fréquence cardiaque / FC | `FC` only in tight stat labels |
| heart rate zone | Zones de fréquence cardiaque | |
| cadence (steps/min) | Cadence | `runStatCadence`; "Fréquence" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plan d'entraînement; short Plan(s) | |
| race | Course; "Course officielle" for a run's race source | collides with *run* — inconsistency 1 |
| race page (a race's public page, its photo gallery) | **page de l'épreuve** — « Afficher sur la page de l'épreuve » | settled 2026-11-13 (#1374 round 3.5), both surfaces; the run beside it is « course », so the race is « épreuve » (inconsistency 1) |
| finish | Arrivée (finish line); Terminé (status); Terminer (action) | |
| DNF | DNF | web also "ABD" (`liveEvent.statusDnf`) and "Abandon" (`checkpoint.statusDnf`) — inconsistency 6 |
| route | Itinéraire / Itinéraires | dominant; "Parcours" also used (41 / 48 strings), mostly for a race course |
| segment | Segment / Segments | |
| club | Club / Clubs | |
| event | Événement / Événements | |
| gym | **Muscu** | `nav.gym`, `gymTitle` |
| nutrition | Nutrition | |
| log (verb) | Ajouter (mobile `navLog`) / Enregistrer | "Enregistrer" also means *save* — prefer "Ajouter" where *log* sits beside *save* |
| streak | Série | |
| log a session (action) | **Enregistrer une séance** (de musculation) — the action label on both surfaces | 2026-11-12: never "Noter" |
| tap / press / long-press | **Touchez** (tap: "Touchez Réessayer", "Touchez la carte", "Touchez pour modifier" — *toucher* is transitive, no « sur ») · **Appuyez sur** only where the English says *press* (a button on the web, a key, a watch's physical button: "appuyez sur GO sur la ligne", "Appuyez sur Annuler pour le restaurer") · long-press **appuyez longuement** / « un appui long » | settled 2026-11-12: 25 mobile / 7 web strings and one help guide moved from « Appuyez sur » to « Touchez » where the English says *tap*; the help guides already said « touchez » (55) |
| RSVP "I'm in" | **Je participe** (`clubEvent.imIn`, `eventRsvpGoing`, every help guide); the going status is "Participe" | settled 2026-11-13, phone aligned to web; never "Je viens" |
| AI disclosure | **l'information sur l'IA** ("nécessite l'information sur l'IA mise à jour", "Consulter l'information sur l'IA", "Information sur l'IA acceptée.") | settled 2026-11-13; never "notice IA". Consent wording: CISO/counsel review the change |
| tapping as a noun ("the alternative to tapping the map") | **un toucher** ("à la place d'un toucher sur la carte") | settled 2026-11-13; never the anglicism "au tap" |
| goal | Objectif / Objectifs | |
| coach | Coach; AI Coach = **Coach IA** | |
| auto-pause | — | no catalogue string yet; build from "pause" ("Course en pause", "Mettre en pause") → "Pause automatique", and flag it as a new term |
| kudos | kudos ("donner des kudos", "retirer les kudos") | web also "Donner un kudos" / "Retirer le kudos" — use the plural form |
| workout / session | Séance; training = entraînement | |
| skip a workout / skipped | **Ignorer** / **ignorée** (séance) — un-skip **Ne plus ignorer** | settled 2026-10-21; never "sautée" for the status, never "l'ignorance". Skipping a step or setup is a different action: **Passer**. "Ne sautez pas" stays in coaching advice |
| warm-up / cool-down / recovery | Échauffement / **Retour au calme** / Récupération | cool-down is also "Récupération" in places, colliding with recovery — inconsistency 7 |
| save / settings / feed / followers | Enregistrer / **Réglages** (mobile) – **Paramètres** (web) / Fil / Abonnés | settings split — inconsistency 4 |
| arm / armed (race control) | **Armer** (vous: "Armez la course"), state **armé(e)** — "Armer la course", "Course armée", "Armer plus tôt", "Armer quand même" | settled 2026-11-10; never the tu-form "Arme" |
| self-timed (race) | **en chrono libre** ("course en chrono libre", "Fenêtre en chrono libre") | settled 2026-11-10; never "chronométrée en autonomie" / "chronométrée par chacun" |
| GO (the start signal) | **GO** — the button on the web and in the phone app, "GO par l'organisateur", "GO programmé"; prose "donner le GO", "le GO", "après le GO", "en attente du GO" | settled 2026-11-10; never "Lancer le Go" for the button. *Départ* stays for the start line and the time fields ("ligne de départ", "Heure de départ", "Départ à {when}"); the Wear armed banner is "COURSE ARMÉE" |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **run vs race are both "course".** Web `runSurface.tabRuns` and
   `runSurface.tabRaces` both render "Courses" side by side in
   `RunSurfaceTabs.svelte`; `nav.races` / `navRaces` (unused keys) too.
   "Course officielle" exists for one key. Since 2026-11-12 a run is always
   « course », so a string that names both says « épreuve » / « compétition »
   / « jour J » for the race (`raceRetime.loadFailed`, `raceRetime.undone`,
   `clubHome.emptyEventsNonAdmin`, `planRecapRaceNotRun`, the race help
   guides); the two tab labels are still both "Courses".
2. **split**: web `prefs.cue.splits` "Fractionnés" (wrong sense) vs mobile
   `prefsCueSplits` "Intermédiaires"; web `landing.previewSplits` "Temps
   au km".
3. *(resolved 2026-10-15)* tu / vous — both catalogues are `vous`; see Register.
4. **settings**: "Réglages" (mobile `navSettings`) vs "Paramètres" (web
   `shell.settings`).
5. **elevation gain**: Dénivelé positif / Montée / Dénivelé + / Dénivelé.
6. **DNF**: DNF / ABD / Abandon on web.
7. **cool-down**: Retour au calme vs Récupération.
8. **plural `one` with literal 1** in 12 mobile strings — see Plurals.

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Apple Watch,
Wear OS, HealthKit (the framework), GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF, and VO₂ max (written with a space, as `metric.vo2max.label` has it). Apple's app is named **Apple Santé** and Google's
**Santé Connect** (each vendor's official French name;
`healthPlatformNameIos` / `healthPlatformNameAndroid`). Identifiers, route
paths, ICU keywords, `{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
