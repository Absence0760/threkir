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
| race (a competition you find, enter, browse or are listed for: the race calendar, a race page, a listing; and a race in a training plan or season) | **épreuve** / épreuves — « Calendrier des épreuves », « Rechercher des épreuves par nom… », « Ajouter une épreuve », « Page de l'épreuve et inscription », « Nom de l'épreuve », « Épreuves de ce plan », « épreuve objectif », « épreuves A, B ou C », « date de l'épreuve », « semaine de l'épreuve »; race day is « jour J » (« Jour J », « Le jour J reste le {date} ») | settled 2026-11-13 (#1374 round 2026-11-13b), both surfaces: the race calendar page and the plan pages put a race beside runs (« Vos courses à cette épreuve », the plan countdown « Épreuve dans N jours »), so the race is never « course » there. Feminine like *course*, but elide: « l'épreuve », « d'épreuve », and « mon épreuve ». "Course officielle" stays for a run's race source |
| race (a club-hosted live race: arm, start, end, cancel, the live page, race director) | **course** — « Armer la course », « Course armée », « Terminer la course », « Course en direct », « directeur de course » | settled 2026-11-10 and kept 2026-11-13: the live race-control vocabulary is « course », as es keeps *carrera* for it; where such a string also names the run, the run is « course enregistrée » or « activité » |
| race page (a race's public page, its photo gallery) | **page de l'épreuve** — « Afficher sur la page de l'épreuve » | settled 2026-11-13 (#1374 round 3.5), both surfaces; the run beside it is « course », so the race is « épreuve » (inconsistency 1) |
| streaming app | « app de streaming » | settled 2026-11-13 (#1374 round 3.5), both surfaces; never « application de streaming » |
| cue (guided run) | **repère** / repères everywhere | settled 2026-11-13 (#1374 round 3.5), both surfaces; never « indication » for a cue |
| fluid (fuel plan, roadbook) | **liquides** — « Liquides au total », « Liquides selon le poids », « Liquides par heure (ml) » | settled 2026-11-13 (#1374 round 3.5), both surfaces; never « fluide » (a calque) |
| form (TSB) | **Fraîcheur**; fitness (CTL) « Forme », fatigue (ATL) « Fatigue » | settled 2026-11-13 (#1374 round 3.5), both surfaces; « État de forme » is Readiness only |
| readiness | **État de forme** (masculine: bands « faible / modéré / élevé »), hero « État de forme {score} » | settled 2026-11-13 (#1374 round 3.6), both surfaces; never « Forme » or « Forme du jour », which is CTL. The TSB label and tooltip, the training-load heading and chart label moved to « Fraîcheur » the same day |
| race countdown on the plan card | « Épreuve demain », « Épreuve dans N jours » | settled 2026-11-13 (#1374 round 3.5), both surfaces; a race beside the runs on that card is « épreuve » |
| finish | Arrivée (finish line); Terminé (status); Terminer (action) | |
| DNF | DNF | web also "ABD" (`liveEvent.statusDnf`) and "Abandon" (`checkpoint.statusDnf`) — inconsistency 6 |
| route | Itinéraire / Itinéraires | dominant; "Parcours" also used (41 / 48 strings), mostly for a race course |
| track / trace (a recorded run's GPS line, its file, a raw or matched track) vs route line (a planned route's or course's drawn line) | **trace** (fem.) for what a run recorded — « trace GPS », « Afficher la trace GPS brute », « fichiers de trace GPS », « traces publiques » (privacy zones), « Carte avec trace » (run share card) · **tracé** (masc.) for the line of a planned route or course — « tracé de l'itinéraire », « Tracé du parcours © contributeurs d'OpenStreetMap », « un tracé qui quitte le sentier » | settled 2026-11-13 (#1374), both surfaces; 15 mobile strings moved from « tracé » to « trace » the same day. The participle *tracé* (« Parcours tracé par {club} », provenance « Tracé ») is the verb *tracer* and stays |
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
| gender (the profile field, male / female / prefer not to say) | **genre** ("Genre", "votre genre", "classements de segments par genre et par tranche d'âge") | settled 2026-11-13 (health-consent gate, #1379), both surfaces; consent wording: CISO/counsel review; never "sexe" for the field. "sexe" stays only where the English says *sex* about age grading (`metric.ageGrade.definition`). The consent statement and every withdrawal list name the same items in the same order as the English (gender, height, weight history, cycle or pregnancy details, heart rate recorded with activities, heart-rate targets in plans, heart-rate medication setting, food log); `health_consent_scope.test.ts` pins the English |
| Review (health-data) consent (button that opens the consent screen) | **Consulter le consentement (aux données de santé)** | settled 2026-11-13 (health-consent gate, #1379), both surfaces; consent wording: CISO/counsel review; never "Donner mon consentement" (the tap does not consent) or "Vérifier le consentement". "health-data consent" itself is « consentement aux données de santé » everywhere; the heart-rate medication item is « votre réglage relatif aux médicaments qui modifient votre fréquence cardiaque », a setting, not a statement that a drug does |
| GDPR citation | **art. 9, par. 2, point a, du RGPD**, "art. 7, par. 3, du RGPD", "art. 20 du RGPD" | settled 2026-11-13 (health-consent gate, #1379), both surfaces; consent wording: CISO/counsel review; never "RGPD art. 9" |
| tapping as a noun ("the alternative to tapping the map") | **un toucher** ("à la place d'un toucher sur la carte") | settled 2026-11-13; never the anglicism "au tap" |
| goal | Objectif / Objectifs | |
| coach | Coach; AI Coach = **Coach IA** | |
| auto-pause | — | no catalogue string yet; build from "pause" ("Course en pause", "Mettre en pause") → "Pause automatique", and flag it as a new term |
| kudos | kudos ("donner des kudos", "retirer les kudos") | web also "Donner un kudos" / "Retirer le kudos" — use the plural form |
| workout / session | Séance; training = entraînement | |
| skip a workout / skipped | **Ignorer** / **ignorée** (séance) — un-skip **Ne plus ignorer** | settled 2026-10-21; never "sautée" for the status, never "l'ignorance". Skipping a step or setup is a different action: **Passer**. "Ne sautez pas" stays in coaching advice |
| warm-up / cool-down / recovery | Échauffement / **Retour au calme** / Récupération | cool-down is also "Récupération" in places, colliding with recovery — inconsistency 7 |
| save / settings / feed / followers | Enregistrer / **Réglages** (both surfaces) / Fil / Abonnés | settings settled 2026-11-13: « Réglages » for the app's settings on web and mobile, help guides included; « paramètres » stays for a browser's or another app's settings and for parameters (« paramètres du plan ») |
| arm / armed (race control) | **Armer** (vous: "Armez la course"), state **armé(e)** — "Armer la course", "Course armée", "Armer plus tôt", "Armer quand même" | settled 2026-11-10; never the tu-form "Arme" |
| self-timed (race) | **en chrono libre** ("course en chrono libre", "Fenêtre en chrono libre") | settled 2026-11-10; never "chronométrée en autonomie" / "chronométrée par chacun" |
| GO (the start signal) | **GO** — the button on the web and in the phone app, "GO par l'organisateur", "GO programmé"; prose "donner le GO", "le GO", "après le GO", "en attente du GO" | settled 2026-11-10; never "Lancer le Go" for the button. *Départ* stays for the start line and the time fields ("ligne de départ", "Heure de départ", "Départ à {when}"); the Wear armed banner is "COURSE ARMÉE" |
| age grade (the score against the best for your age and sex) | **indice d'âge**; an age-graded result is a **résultat avec indice d'âge** | settled 2026-11-13 (#1374 round 2026-11-13b), both surfaces; never « résultats ajustés par âge ». « calibration selon l'âge » stays only where the English says *age calibration* (`onboarding.dobNote`) |
| age band (the board filter and the consent statement) | **tranche d'âge** (already one term) | checked 2026-11-13; **catégorie d'âge** stays for a race's own age category in results (`races.ageGroup`) |
| name search (the profile search that « M'afficher dans la recherche par nom » controls, and that keeps under-18 accounts out) | **recherche par nom** everywhere, the DOB notes included; under-18s are « les comptes **des** moins de 18 ans » (the accounts of under-18s, not accounts younger than 18) | settled 2026-11-13 (#1374 round 2026-11-13b), both surfaces; never « recherche (publique) de personnes » for it |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **run vs race are both "course".** Since 2026-11-12 a run is always
   « course ». Since 2026-11-13 a listed race and a training-plan race are
   « épreuve » (see the two *race* rows): the race calendar (`races.*`), its
   shared names (`shareRace.calendar`, `integrations.*Open`,
   `learn.ctaRacing`, `courseAlerts.browseRaces`), the plan pages
   (`planDetail.*`, `planEditor.*`, `plansNew.*`, `plansPage.*`,
   `planRecap.*`, `planImport.*`, `planBreak.*`, `seasonPlanner.*`,
   `workoutEditor.race*`, `workoutDetail.taglineRace`, `planPhase.race`,
   the dashboard's plan card) on web. Still « course » for a race and owed
   the same move: the race-course tools (`raceCourse.*` claim and suggest,
   `routeHeatmap.races*`, `admin.reports.kind.raceListing`), the
   notifications about a race you are going to, the race-day panel and
   predictor, and the fuelling preferences.
2. **split**: web `prefs.cue.splits` "Fractionnés" (wrong sense) vs mobile
   `prefsCueSplits` "Intermédiaires"; web `landing.previewSplits` "Temps
   au km".
3. *(resolved 2026-10-15)* tu / vous — both catalogues are `vous`; see Register.
4. **settings**: resolved 2026-11-13 — « Réglages » on both surfaces.
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
