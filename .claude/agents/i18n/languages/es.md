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
124 and 6 / 13 strings). `cardíaca` (16 / 24) is the house form —
`cardiaca` appears once per surface and is a slip. `correo` for email
(34 / 41). Sentence case for labels.

## Typography

- Quotes: **« … »** without inner spaces (43 / 30); straight `"` survives in
  some strings and is a slip.
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
| personal record / PR | Récord personal / Récords personales; badge **PR** (web) / "RP" (mobile `gymPrBadge`) | mobile `dashboardSectionPersonalBests` "Mejores marcas personales"; "marca" for a time |
| tempo run | Tempo | |
| interval | Intervalo (a step) / **Series** (workout kind) | |
| long run | Tirada larga | |
| easy run | Suave | `intensityBalance.easyLabel` "fácil" is the odd one |
| elevation gain | **Desnivel positivo** | web; mobile "Desnivel +", "Desnivel", "Subida", "Ascenso", web `dash.elevationGain` "desnivel acumulado" |
| heart rate / HR | Frecuencia cardíaca / FC | |
| heart rate zone | Zonas de frecuencia cardíaca | |
| cadence (steps/min) | Cadencia | `runStatCadence`; "Frecuencia" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plan de entrenamiento; short Plan(es) | |
| race | Carrera; "Competir" for the race phase intent | collides with *run* — inconsistency 1 |
| finish | **Meta** (finish line); Finalizado (status); Finalizar (action) | "Meta" also used once for *goal* on web |
| DNF | DNF | web `liveEvent`/checkpoint also "Abandono" |
| route | Ruta / Rutas | |
| segment | Segmento / Segmentos | |
| club | Club / Clubes | |
| event | Evento / Eventos | |
| gym | **Gimnasio** (mobile) / **Gym** (web `nav.gym`, `gym.title`) | inconsistency 2 |
| nutrition | Nutrición | |
| log (verb) | Registrar | `navLog` |
| streak | Racha | |
| goal | Objetivo / Objetivos | |
| coach | Entrenador; AI Coach = **Entrenador IA** | web `coachChat.coach` "Coach" |
| auto-pause | — | no catalogue string yet; build from "pausa" ("Carrera en pausa", "Pausar") → "Pausa automática", and flag it as a new term |
| kudos | kudos ("dar kudos", "quitar/retirar kudos") | |
| workout / session | Entrenamiento / sesión | |
| warm-up / cool-down / recovery | Calentamiento / Enfriamiento / Recuperación | |
| challenge | Desafío | web also "reto" (0 / 7) |
| save / settings / feed / followers | Guardar / **Ajustes** (mobile) – **Configuración** (web `shell.settings`) / Feed / Seguidores | inconsistency 3 |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **run vs race are both "Carrera(s)".** Web `runSurface.tabRuns` and
   `runSurface.tabRaces` render "Carreras" twice on one tab bar
   (`RunSurfaceTabs.svelte`); `nav.races` / `navRaces` (unused) too.
2. **gym**: "Gimnasio" (mobile `gymTitle`, `fitnessTabGym`) vs "Gym" (web
   `nav.gym`, `gym.title`).
3. **settings**: "Ajustes" (mobile `navSettings`, web `prefs.kicker`) vs
   "Configuración" (web `shell.settings`).
4. **PR badge**: "RP" (mobile `gymPrBadge`) vs "PR" (web `gym.pr.badge`).
5. **elevation gain** — five renderings, see table.
6. **VO₂ max**: "VO₂ máx" (`metric.vo2max.label`, `fitnessStatVo2Max`) vs
   "VO2 máx." (`watchMetricVo2Max`).
7. **plural you**: vosotros vs ustedes — see Register.
8. **challenge**: Desafío vs Reto.

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Health Connect, Apple Watch,
Wear OS, HealthKit, GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF. VO₂ max is written **VO₂ máx** (the catalogue's form). Apple's app is
**Apple Salud** (its official Spanish name, as `importHealthSubtitleIos`
already does). Identifiers, route paths, ICU keywords, `{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
