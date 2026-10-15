# French (fr)

One French catalogue for every French-speaking reader: `app_fr.arb`
(mobile) and `locales/fr.ts` (web). `fr-CA`, `fr-BE`, `fr-CH` fall back
to it, so write standard metropolitan French.

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — `vous` (but the catalogues are split; read this)

**Use `vous`.** decisions.md § 1675 records that "the mobile ARB onboarding
copy decides the register (… `vous` on French …)", and the phone is
majority `vous` (409 strings against 163 with `tu`/`te`/`toi`/`ton`/`ta`/
`tes`/`t'`; re-measured 2026-10-15 at `58a09dd0c`, the same marker set for
both registers and both catalogues).

- `discardChangesBody` (mobile) and `common.unsavedBody` (web): "Vous avez des modifications non enregistrées. Quitter sans enregistrer ?"
- `clubInviteEnterCodeError` (mobile): "Saisissez le code d'invitation de votre lien."
- `rateLimit.generic` (web): "Vous faites cela trop rapidement — veuillez patienter {wait} et réessayer."

**Finding — the French catalogues still mix both registers.** A 2026-10-15
pass moved about 85 web strings (the AI-consent copy among them) and the
phone's weight-fluid and safety-share strings to `vous`, but it was not a
full migration: web now sits at **460 `vous` against 451 `tu`** (of 6,115
strings; one string carries both) and the phone at 409 against 163. `tu`
remains in, among others, `onboarding.step6Hint` "Les notifications push
t'informent …", `coachChat.errorSignInFirst` "Connecte-toi d'abord.",
`settingsAccount.passwordDesc` "Modifie le mot de passe qui te sert …", and
on the phone `settingsAccountSignOutFailed` "… vérifie ta connexion" and
`settingsAccountDeleteBody` "Cela supprime définitivement tes courses …".
On web `tu` still dominates `prefs`, `dash`, `settingsIntegrations`,
`planEditor`, `planDetail`, `onboarding`, `gym`, `coachChat`, `metric` and
`upgrade`; `vous` dominates notifications, `safety`, `deleteAccount`,
`login`, `clubEvent`, `coachPage`, `rateLimit`, `fuelPlan` and `audience`.
Write new strings in `vous`, flag any batch key whose neighbours are `tu`
(the residue is a migration, not a precedent), and never mix the two inside
one string.

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
- Apostrophe: straight `'` (602 / 939) is the norm; curly `’` appears in
  69 / 80. Use `'`.
- Ellipsis **…**; spaced em dash ` — ` as in English.
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals

`one` covers **0 and 1**, `other` the rest. Never write a literal `1` in a
`one` branch: 12 mobile strings already do (e.g. `importFailuresHeading`
"one{1 activité n'a pas été importée}"), which renders "1 activité" for a
count of 0. Use `{count}` (ARB) / `#` (web).

## Running glossary (what the catalogues already use)

| English | French | Evidence / note |
|---|---|---|
| run (noun) | course / courses; nav verb **Courir** | `nav.runs` "Courses", `navRun` "Courir"; one web "Sorties" |
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
| goal | Objectif / Objectifs | |
| coach | Coach; AI Coach = **Coach IA** | |
| auto-pause | — | no catalogue string yet; build from "pause" ("Course en pause", "Mettre en pause") → "Pause automatique", and flag it as a new term |
| kudos | kudos ("donner des kudos", "retirer les kudos") | web also "Donner un kudos" / "Retirer le kudos" — use the plural form |
| workout / session | Séance; training = entraînement | |
| warm-up / cool-down / recovery | Échauffement / **Retour au calme** / Récupération | cool-down is also "Récupération" in places, colliding with recovery — inconsistency 7 |
| save / settings / feed / followers | Enregistrer / **Réglages** (mobile) – **Paramètres** (web) / Fil / Abonnés | settings split — inconsistency 4 |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **run vs race are both "course".** Web `runSurface.tabRuns` and
   `runSurface.tabRaces` both render "Courses" side by side in
   `RunSurfaceTabs.svelte`; `nav.races` / `navRaces` (unused keys) too.
   "Course officielle" exists for one key.
2. **split**: web `prefs.cue.splits` "Fractionnés" (wrong sense) vs mobile
   `prefsCueSplits` "Intermédiaires"; web `landing.previewSplits` "Temps
   au km".
3. **tu / vous** — see Register.
4. **settings**: "Réglages" (mobile `navSettings`) vs "Paramètres" (web
   `shell.settings`).
5. **elevation gain**: Dénivelé positif / Montée / Dénivelé + / Dénivelé.
6. **DNF**: DNF / ABD / Abandon on web.
7. **cool-down**: Retour au calme vs Récupération.
8. **plural `one` with literal 1** in 12 mobile strings — see Plurals.

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Health Connect, Apple Watch,
Wear OS, HealthKit, GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF, and VO₂ max (written with a space, as `metric.vo2max.label` has it). Apple's app is named **Apple Santé** (its official French
name, as `importHealthSubtitleIos` already does). Identifiers, route
paths, ICU keywords, `{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
