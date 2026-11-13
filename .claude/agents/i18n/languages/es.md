# Spanish (es)

One Spanish catalogue for every Spanish-speaking reader: `app_es.arb`
(mobile) and `locales/es.ts` (web). `es-MX`, `es-AR`, `es-419` all fall
back to it. The catalogues are written in **Peninsular (Spain) Spanish**:
`Introduce` (38 / 19, never `Ingresa`), `móvil` (3 / 15, never
`celular`), and web uses `vosotros` forms. Keep that variety, but prefer
wording that also reads naturally in Latin America where a neutral choice
exists.

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — `tú`, everywhere

The app addresses the runner as **tú** (361 / 588 strings with tú-forms;
`usted` is unused). decisions.md § 1675 records it ("… `tú` on Spanish").

- `clubInviteEnterCodeError` (mobile): "Introduce el código de invitación de tu enlace."
- `common.unsavedBody` (web) and `discardChangesBody` (mobile): "Tienes cambios sin guardar. ¿Salir sin guardar?"
- `rateLimit.generic` (web): "Estás haciendo eso demasiado rápido: espera {wait} e inténtalo de nuevo."

Third-person `su` for *someone else's* account (`profile.notFoundText`
"… haya eliminado su cuenta") is not `usted`. Buttons are infinitives
("Guardar", "Pausar carrera", "Unirse"); instructions use the tú imperative
("Introduce", "Pega").

**Plural "you" is mixed (finding):** web uses `vosotros` —
`routeDetail.sendDm.relationMutual` "Os seguís mutuamente",
`routeDetail.sendDm.intro` "… vuestra conversación", `clubEditor.locationHint`
"… os encuentre" — but `profileBlockConfirmBody` / `profile.blockConfirmMessage`
say "entre ustedes". Prefer a construction that avoids plural address;
where it can't, use `vosotros` and flag it.

## Spelling and style authority

**RAE / ASALE** (*Diccionario de la lengua española*, *Ortografía* 2010):
no accent on `solo` or demonstratives; opening `¿` and `¡` always (106 /
124 and 6 / 13 strings). `cardíaca` is the house form, never `cardiaca` (the last one,
`prefs.dateOfBirthPurpose`, moved 2026-11-13). `correo` for email
(34 / 41). Sentence case for labels.

## Typography

- Quotes: **«…»** without inner spaces, always;
  a straight `"` in a message fails CI (`messages_parity.test.ts` on web, `architecture_guards_test.dart` on mobile — ARBs and the `gen/` getters). The last 6 web and 15 mobile straight-quoted strings moved to «…»
  2026-10-14.
- Ellipsis **…**. Spaced em dash ` — ` as in English, or a colon where
  Spanish reads better (the catalogues do both).
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals

`one` = exactly 1, `other` otherwise.

## Running glossary (what the catalogues already use)

| English | Spanish | Evidence / note |
|---|---|---|
| run (noun) | carrera / carreras; nav verb **Correr** | `nav.runs` "Carreras", `navRun` "Correr", `runPauseA11yLabel` "Pausar carrera" |
| pace | Ritmo | all stat labels |
| split | Parciales | |
| lap | Vuelta / Vueltas | |
| personal record / PR | Récord personal / Récords personales; badge **PR** (web `gym.pr.badge` and mobile `gymPrBadge`); a route's best = "mejor marca personal" (`routeHistory.personalBest` / `runDetailPersonalBest`) | mobile `dashboardSectionPersonalBests` "Mejores marcas personales"; "marca" for a time |
| tempo run | Tempo | |
| interval | Intervalo (a step) / **Series** (workout kind) | |
| long run | Tirada larga | |
| easy run | Suave | `intensityBalance.easyLabel` "fácil" is the odd one |
| elevation gain | **Desnivel positivo** | web; mobile "Desnivel +", "Desnivel", "Subida", "Ascenso", web `dash.elevationGain` "desnivel acumulado" |
| heart rate / HR | Frecuencia cardíaca / FC | |
| heart rate zone | Zonas de frecuencia cardíaca | |
| fitness / fatigue / form (training load: CTL / ATL / TSB) | **Estado físico** / **Fatiga** / **Forma** — "Estado físico, fatiga y forma", "Estado físico (CTL)", "CTL (estado físico)", "Forma (TSB)", "estado físico − fatiga". *Fitness* in its everyday sense ("refleja tu estado físico actual", VDOT "puntuación de estado físico", "tu estado físico reciente") takes the same word, as the English does | settled 2026-11-12; never "forma física" or bare "Estado" for fitness, never "frescura" for form. *Forma* is the TSB alone (and *form* in its everyday sense, "tu forma pasada"). The *Fitness* destination (`navFitness`) stays "Fitness" |
| max HR / resting HR | **frecuencia cardíaca máxima** / **frecuencia cardíaca en reposo** in sentences, setting titles and errors; abbreviated **FC máxima** / **FC en reposo** only where the HR row allows *FC* (a field label with its unit, a button: "FC máxima (ppm)", "Definir FC máxima"); coordinated "frecuencia cardíaca en reposo y máxima". The unit is **ppm**, never "bpm" / "lpm". A zone's upper bound is "el límite superior de frecuencia cardíaca", not "frecuencia cardíaca máxima" | settled 2026-11-12; never "FC máx." |
| cadence (steps/min) | Cadencia | `runStatCadence`; "Frecuencia" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plan de entrenamiento; short Plan(es) | |
| race (a competition you find, enter, browse or are listed for) | **Prueba / Pruebas** — `navRaces` / `nav.races` "Pruebas", "Calendario de pruebas" (`racesTitle`, `races.title`), "Pruebas y recorridos", "Próximas pruebas", "Buscar pruebas por nombre…", "Página de la prueba e inscripción", "Reclamar esta prueba", "Ficha de prueba", "página de la prueba" (race photo gallery), "resultados de pruebas" (RunSignUp / ChronoTrack); "Es una contrarreloj, no una prueba organizada" (park courses) | settled 2026-11-12 (inconsistency 1). Covers every race-discovery, calendar, registration, race-listing, race-page, race-course-claim and results-import string. Feminine like *carrera*, so agreement is unchanged ("esta prueba", "Próximas pruebas"). *Prueba* in its other senses ("periodo de prueba", "Prueba encontrada", "prueba a ampliarlo") are unaffected |
| race (as the athlete's own effort, in training plans) | **Carrera** — "carrera objetivo", "carreras A/B/C", "Semana de carrera", "Día de carrera", "Fecha de carrera", "Estrategia de carrera", "Predictor de tiempo de carrera", "Avituallamiento de carrera"; "Competir" for the race phase intent | settled 2026-11-12: plan / season / workout / prediction strings keep *carrera*, as Spanish running coaching does. A plan string that points at the race *listing* takes *prueba* ("Toca «Añadir a mi temporada» en la prueba", "Buscar una prueba") |
| race (a club-hosted live race: control, live page, results) | **Carrera** — the race-control rows below, "Control de carrera", "Carrera en vivo", "Director de carrera", help category `helpCategoryRaces` / `help.categoryRaces` "Carreras"; never «competición» for this race ("No se pudo cargar la carrera de esta actividad", "la llegada que deshiciste durante la carrera") | settled 2026-11-10 / 2026-11-12: the host's live race keeps *carrera* (Preparar / Finalizar / Cancelar carrera, «CARRERA PREPARADA» on Wear) |
| run (the runner's own recording, in a string that also names a race «carrera») | **Actividad** — the self-timed button «Esta actividad es mi intento» (phone, web, help and the Wear watch's `race_attempt`), "Tu actividad se sigue grabando, pero no se enviará ningún resultado", "la traza de esta actividad" (re-time), "Una actividad que no marques como tu intento nunca se une a la carrera", "Ninguna actividad el día de la carrera" (plan recap) | settled 2026-11-13: where a live-race or training-plan string already says *carrera* for the race, the run beside it is *actividad*, so «Esta carrera es mi intento» beside «Abre la carrera» can't be read as the race. A string that names only the run keeps *carrera*; the run screen is «la pantalla Correr» |
| finish | **Meta** (finish line); Finalizado (status); Finalizar (action) | "Meta" also used once for *goal* on web |
| DNF | DNF | web `liveEvent`/checkpoint also "Abandono" |
| route | Ruta / Rutas | |
| segment | Segmento / Segmentos | |
| club | Club / Clubes | |
| event | Evento / Eventos | |
| gym | **Gym** as the feature and tab name (web `nav.gym`, `gym.title`; mobile `gymTitle`, `fitnessTabGym`, "pestaña Gym"); a gym workout is an **entreno**; prose may keep "sesiones de gimnasio" | settled 2026-11-10, phone aligned to web |
| gun time / chip time | **Tiempo bruto** / Tiempo chip (`races.gunTime`, `racesGunTime`, "¡Meta! Tiempo bruto {time}") | settled 2026-11-10; never "Tiempo oficial" for gun time (web `clubEvent.timeSplitGun*` still says "oficial", open) |
| RSVP "I'm in" | **Me apunto** (`clubEvent.imIn`, `eventRsvpGoing`) | settled 2026-11-10; never "Voy" |
| segment effort | **intento** ("No hay intentos de segmento") | web `segments.*` / `segmentEfforts.*`; phone aligned 2026-11-10 |
| nutrition | Nutrición | |
| log (verb) | Registrar | `navLog` |
| streak | Racha | |
| goal | Objetivo / Objetivos | |
| coach | Entrenador; AI Coach = **Entrenador IA** | web `coachChat.coach` "Coach" |
| auto-pause | — | no catalogue string yet; build from "pausa" ("Carrera en pausa", "Pausar") → "Pausa automática", and flag it as a new term |
| kudos | kudos ("dar kudos", "quitar/retirar kudos") | |
| workout / session | Entrenamiento / sesión | |
| warm-up / cool-down / recovery | Calentamiento / Enfriamiento / Recuperación | |
| taper (the plan phase and the act) | **Puesta a punto** — phase label `planPhaseTaper` / `planPhase.taper` "Puesta a punto", "Puesta a punto en torno a carreras B/C", "estás en la puesta a punto", "Bien para una puesta a punto o una semana de recuperación", "En puesta a punto: una sesión dura no te hará daño" | settled 2026-11-13; never "afinamiento" / "afinando", "tapering", or "descarga", which is a *deload* / step-back week ("semana de descarga") |
| challenge | Desafío | web also "reto" (0 / 7) |
| save / settings / feed / followers | Guardar / **Ajustes** / Feed / Seguidores | settings settled 2026-11-13 on **Ajustes** everywhere (`navSettings`, web `shell.settings`, `prefs.kicker`, help "en Ajustes"); never "Configuración" for the settings area. *Configuración* stays for *setup* ("Configuración incompleta" for payouts) |
| arm / armed (race control) | **Preparar** / **preparada** — "Preparar carrera", "Carrera preparada", status "Preparada", "Preparar antes", "Preparar de todos modos", "Prepárala antes" | settled 2026-11-10; never "Armar" / "armado" or "lista" / "Listo" (reads as *ready*, confusable with GO). The Wear watch's banner is «CARRERA PREPARADA» |
| set up (a race created automatically before its start) | **configurar** ("La carrera se configura un día antes") | settled 2026-11-10; never "preparar", which is *arm* |
| self-timed (race) | **con cronometraje propio** ("carrera con cronometraje propio", "Ventana de cronometraje propio") | settled 2026-11-10; never "autocronometrada" |
| GO (the start signal) | **GO** — the button on the web and in the phone app ("GO"), "GO del organizador", "GO programado"; prose "dar el GO", "el GO", "después del GO", "esperando el GO" | settled 2026-11-10; never "YA" / "Dar la salida" for the button or "dar la salida" / "la salida" for the signal. *Salida* stays for the start line and the time fields ("línea de salida", "Hora de salida", "Salida a las {when}") |
| race ended (watch) / host End | "Carrera finalizada" / **Finalizar carrera**, status "Finalizada" | settled 2026-11-10 |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. ~~**run vs race are both "Carrera(s)"**~~: resolved 2026-11-12. A race
   you find, enter, browse or are listed for is **prueba(s)** (the race
   calendar, race pages, listings, claims, results import, `nav.races` /
   `navRaces` "Pruebas"; the run-surface tab is `runSurface.tabRacesCourses`
   "Pruebas y recorridos" beside `tabRuns` "Carreras"). The run stays
   *carrera*, and so do the training-plan race terms and the club-hosted
   live race-control vocabulary settled 2026-11-10 — see the three *race*
   rows in the glossary for the boundary.
   The help category `helpCategoryRaces` / `help.categoryRaces` stays
   **Carreras** (checked 2026-11-12): eight of its nine guides are the
   club-hosted live race (set it up, choose how it starts, race day for
   hosts, racing in it, following it live, start and finish lines,
   self-timed races, results), none of them points at the race calendar,
   and each already says *carrera*; the ninth, `drive-a-course`, is about a
   public race course and rightly says *prueba* in its own text. A category
   label names its guides, so it follows the live-race row, not the
   calendar's. Revisit only if a calendar or race-listing guide joins it.
2. ~~**gym**~~: resolved 2026-11-10, the phone says "Gym" like the web.
3. ~~**settings**~~: resolved 2026-11-13, "Ajustes" everywhere.
4. ~~**PR badge**~~: resolved 2026-11-10, "PR" on both.
5. **elevation gain** — five renderings, see table.
6. **VO₂ max**: "VO₂ máx" (`metric.vo2max.label`, `fitnessStatVo2Max`) vs
   "VO2 máx." (`watchMetricVo2Max`).
7. **plural you**: vosotros vs ustedes — see Register.
8. **challenge**: Desafío vs Reto.

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Apple Watch,
Wear OS, HealthKit (the framework), GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF. VO₂ max is written **VO₂ máx** (the catalogue's form). The two health
platforms take their vendors' Spanish names, `healthPlatformNameIos` /
`healthPlatformNameAndroid`: **Salud de Apple** (apple.com/es/health) and
**Salud conectada** (Google's Spanish help centre) — never "Apple Salud" or
"Health Connect". Identifiers, route paths, ICU keywords, `{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
