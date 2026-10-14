# Brazilian Portuguese (pt-BR)

Web: `locales/pt-BR.ts`. Mobile: `app_pt_BR.arb` (`@@locale` `pt_BR`).
Brazilian clients always send the region (`pt-BR`), so they reach this
catalogue by exact tag; a bare `pt` goes to European Portuguese
(decisions.md § 755, § 761). This catalogue and pt-PT differ on 1,233 of
3,934 mobile keys — **never derive one from the other by moving an
accent**, in either direction.

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — `você`

The reader is **você** (210 / 323 strings), with `seu`/`sua` possessives
and 3rd-person verbs; the `tu` family (`teu`, `tua`, `podes` …) appears
in zero strings.

- `common.unsavedBody` (web) and `discardChangesBody` (mobile): "Você tem alterações não salvas. Sair sem salvar?"
- `clubInviteEnterCodeError` (mobile): "Digite o código de convite do seu link."
- `rateLimit.generic` (web): "Você está fazendo isso rápido demais — espere {wait} e tente de novo."
- `clubInviteIntro` (mobile): "Cole o código de convite que o administrador do clube compartilhou com você."

Continuous aspect uses the gerund ("está fazendo"). Instructions use the
imperative as Brazilians write it ("Digite", "Cole", "Tente de novo");
buttons the infinitive ("Salvar", "Pausar corrida"). The proclitic `te`
with `você` is tolerated in colloquial strings (5 web strings such as
"Outros podem te encontrar por ele"); prefer `você`/`o`/`a`/`lhe` in new
copy. `navYou` is "Você".

## The guards that enforce this

`apps/web/src/lib/i18n/locale_reach.test.ts` and the "locale reach" group
in `apps/mobile_android/test/architecture_guards_test.dart` ban the
**European-only** words in pt-BR: `palavra-passe`, `ecrã`, `ficheiro`,
`telemóvel`, `passadeira`, `partilhar`, `quilómetro`, `género`,
`autocarro`, `frigorífico`, `chávena`, `ginásio` (and plurals), and any
tu-register marker (`teu`, `tua`, `podes`, the `-te` enclitic, the
`-aste`/`-este`/`-iste` preterite …).

## Spelling and style authority

**Acordo Ortográfico de 1990 as applied in Brazil** — VOLP (Academia
Brasileira de Letras); Houaiss / Aurélio for usage. Brazilian accents on
proparoxytones: `quilômetro`, `gênero`, `oxigênio`, `cronômetro`.
`contato` (never `contacto`).

House vocabulary (verified in both catalogues): `salvar`, `registrar` /
`registro`, `compartilhar`, `tela`, `celular`, `arquivo`, `senha`,
`ao vivo` (live), `usuário`, `academia` (gym), `esteira` (treadmill),
`acessar`, `equipe`, `baixar` (download), `café da manhã`, `padrão`
(default and standard), `o app`.

## Typography

- Quotes **“…”** (20 / 6); straight `"` is a slip. The notification family (`notificationBell.*Titled`, `notificationsList.verb*Titled`, mobile `profileNotif*Titled`) was moved to curly quotes 2026-10-14; 23 web and 30 mobile strings still use straight quotes, mostly around `{name}` / `{query}` / `{word}` (inconsistency 6).
- Ellipsis **…**; spaced em dash ` — `.
- No space before `:` `!` `?`.
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals

`one` covers **0 and 1** (CLDR `pt`, on both platforms). Never write a
literal `1` in a `one` branch — 11 mobile strings already do (e.g.
`importFailuresHeading`), rendering "1 …" for 0. Use `{count}` (ARB) /
`#` (web).

## Running glossary (what the catalogues already use)

| English | pt-BR | Evidence / note |
|---|---|---|
| run (noun) | corrida / corridas | `nav.runs`, `navRun` "Corrida" |
| pace | Ritmo | |
| split | Parciais | |
| lap | Volta / Voltas | |
| personal record / PR | Recorde pessoal / Recordes pessoais; badge **PR** (web) / "RP" (mobile `gymPrBadge`) | |
| tempo run | Tempo | |
| interval | Intervalo (a step) / Intervalado (workout kind) | |
| long run | Longão | |
| easy run | Leve | |
| elevation gain | **Ganho de elevação** (web); "Subida" (mobile) | `runStatElevation` "Elevação" |
| heart rate / HR | Frequência cardíaca / FC | |
| heart rate zone | Zonas de frequência cardíaca | |
| cadence (steps/min) | Cadência | "Frequência" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plano de treino; short Plano(s) | |
| race | **Prova** (workout kind, run source); "Corridas" in nav, tabs and `races.title` | collides with *run* — inconsistency 1 |
| finish | Chegada (finish line); Concluído (status); Concluir (mobile) / Finalizar (web) action | |
| DNF | DNF; "Não concluiu" (web `checkpoint.statusDnf`) | |
| route | Rota / Rotas; percurso for a course | |
| segment | Segmento / Segmentos | |
| club | Clube / Clubes | |
| event | Evento / Eventos | |
| gym | **Academia** | |
| nutrition | Nutrição | |
| log (verb) | Registrar | `navLog` |
| streak | Sequência | |
| goal | Meta / Metas | "Objetivo" occasionally on web |
| coach (a person) | **Treinador** | `coaching.*`, guided-run "voz de treinador" |
| AI Coach (the product) | **Coach** as its name (capital C, also mid-sentence: "o Coach está pensando"); **Coach de IA** where the English says *AI Coach* | settled 2026-10-13; never "Treinador IA", "Coach IA" or "AI Coach" |
| event host | **Organizador** | `admin.earnings.*`; never "Anfitrião" |
| payouts / payout account | **Repasses** / **conta de repasses** | `payouts.pageTitle`, `fundraiser.setUpPayouts`; *payment* (a charge) stays "pagamento" |
| activity discipline (yoga, pilates…) | **Modalidade** | `eventEditor.discipline`, `session.discipline` |
| yoga | **ioga** (lower case; "Ioga vinyasa" at a sentence start) | never "yoga" |
| Pro & support | **Pro e apoio** | *support* here is supporting the app ("apoiar o app"); "suporte" is tech support |
| arm / armed (race control) | **Preparar** / **preparada** — "Preparar corrida", "Corrida preparada", "Prova preparada", the watch's "PROVA PREPARADA", the spectator status "Preparada" | settled 2026-10-14 (decisions 1890); never "Armar" / "armado" or "Prova pronta" |
| End race (the host's control) | **Encerrar corrida** / "Encerrar a corrida?" | settled 2026-10-14; *Finalizar* is the runner's own **Finalizar prova** (Finish race), so the two never share a verb |
| gun time / chip time | **Tempo bruto** / **Tempo líquido**; the short split "bruto {gun} · líquido {chip}" | settled 2026-10-14; never "Tempo oficial" for gun time — *oficial* stays for an imported official result |
| Not back by… (return-time alert) | **Sem retorno até…**; the alert is the **alerta de horário de retorno** | settled 2026-10-14; never "Sem voltar até…", "aviso de horário de volta" |
| late start | **Largada tardia** | phone `runRaceLateStart`, Wear `race_late_start` |
| auto-pause | — | no catalogue string yet; build from "Corrida pausada" / "Pausar" → "Pausa automática", and flag it as a new term |
| kudos | kudos ("dar kudos", "remover kudos") | |
| workout | Treino | |
| warm-up / cool-down / recovery | Aquecimento / Desaquecimento / Recuperação | |
| save / settings / feed / followers | Salvar / Configurações (nav "Config.") / Feed / Seguidores | |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **run vs race**: web `runSurface.tabRuns` and `runSurface.tabRaces` both
   render "Corridas" on one tab bar (`RunSurfaceTabs.svelte`); "Prova"
   would separate them.
2. **plural `one` with literal 1** in 11 mobile strings.
3. **elevation gain**: Subida / Ganho de elevação / Elevação.
4. **PR badge**: RP (mobile) vs PR (web).
5. **finish action**: "Concluir" (mobile `gymSessionFinish`,
   `sessionRunFinish`) vs "Finalizar" (web `gym.session.finish`,
   `session.run.finish`).
6. **straight quotes** in 23 web and 30 mobile strings, mostly around a placeholder
   (`routesSaved`, `plansDeleteTitle`, `socialPeople.noMatch`, …),
   against the curly-quote rule above.

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Health Connect, Apple Watch,
Wear OS, HealthKit, GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF. VO₂ max is **VO₂ máx**. Apple's app is **Apple Saúde**. Identifiers,
route paths, ICU keywords, `{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
