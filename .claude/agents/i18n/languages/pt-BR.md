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
`registro` (logging), `gravar` / `gravação` (GPS recording), `compartilhar`, `tela`, `celular`, `arquivo`, `senha`,
`ao vivo` (live), `usuário`, `academia` (gym), `esteira` (treadmill),
`acessar`, `equipe`, `baixar` (download), `café da manhã`, `padrão`
(default and standard), `o app`.

## Typography

- Quotes **“…”**, always: a straight `"` in a message fails CI (`messages_parity.test.ts` on web, `architecture_guards_test.dart` on mobile — ARB and `app_localizations_pt.dart` getters). The last 53 straight-quoted strings moved to curly quotes 2026-10-14.
- Ellipsis **…**; spaced em dash ` — `.
- No space before `:` `!` `?`.
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals

`one` covers **0 and 1** (CLDR `pt`, on both platforms). Never write a
literal `1` in a `one` branch (it renders "1 …" for 0). Use `{count}` (ARB)
/ `#` (web). And when the plural is the **whole message**, its `one` branch
must name the count ("{count} convite enviado") or the plural must carry an
`=0{…}` branch: a count-free "Convite enviado" is what 0 renders. A plural
inside a longer sentence is agreement and stays as it is. Both rules are
guards (`l10n_parity_test.dart`, `messages_parity.test.ts`).

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
| fitness / fatigue / form (training load: CTL / ATL / TSB) | **Condicionamento** / **Fadiga** / **Forma** — "Condicionamento, fadiga e forma", "Condicionamento (CTL)", "Forma (TSB)", "condicionamento − fadiga". *Fitness* in its everyday sense ("reflete seu condicionamento atual", VDOT "pontuação de condicionamento") takes the same word, as the English does; same terms as pt-PT | settled 2026-11-12; never "forma" / "forma física" for fitness ("Quanto maior, melhor o condicionamento"), never "Frescor" for form. The idiom "Manter a forma" (*stay fit*, `setupGoalGeneralFitness`) is not the noun and stays. The *Fitness* destination (`navFitness`) stays "Fitness" |
| cadence (steps/min) | Cadência | "Frequência" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plano de treino; short Plano(s) | |
| race | **Prova** (workout kind, run source); "Corridas" in nav, tabs and `races.title` | collides with *run* — inconsistency 1 |
| finish | Chegada (finish line); Concluído (status); Concluir (mobile) / Finalizar (web) action | |
| Done | By what it does. A button that **closes** a sheet, a dialog, a selection mode or a finished screen is **Pronto** (`filterBarDone`, `runDone`, `coachShare.done`, `runs.done`). A **status** — a workout, a step or a goal that is done — is **Concluído / concluída / concluídos** (`dash.doneBadge`, `coachingAthleteStatusDone`, the widget's done state, the onboarding rail's last step), and so is a button that records a step as done (`session.run.done`); "Mark as done / not done" is "Marcar como concluído / não concluído", "{done} de {total} concluídos", "{pct}% concluído" | settled 2026-11-12; never "Feito" / "feitos" for the status, never "Concluído" for a button that only closes. Not a status, so kept: `gymRoutineHistoryLastDone` "Feita hoje / ontem" (the routine was *performed* then) |
| DNF | DNF; "Não concluiu" (web `checkpoint.statusDnf`) | |
| route | Rota / Rotas; percurso for a course | |
| segment | Segmento / Segmentos | |
| club | Clube / Clubes | |
| event | Evento / Eventos | |
| gym | **Academia** | |
| nutrition | Nutrição | |
| log (verb) | Registrar | `navLog` |
| record (GPS / an activity), recording | **Gravar** / **gravação** — "Gravando", "Gravação e voz", "Começar uma gravação", "corrida gravada", "distância gravada", "grave com uma cinta" | settled 2026-11-12; never *registrar* / *registro* for recording. *Registrar* / *registro* stay for logging (manual entry, diary, gym and food log), records on file (consent, DNF / DNS, weigh-ins, payment records, a DNS record) and a race finish being recorded |
| streak | Sequência | |
| goal | Meta / Metas | "Objetivo" occasionally on web |
| coach (a person) | **Treinador** | `coaching.*`, guided-run "voz de treinador" |
| AI Coach (the product) | **Coach** as its name (capital C, also mid-sentence: "o Coach está pensando"); **Coach de IA** where the English says *AI Coach* | settled 2026-10-13; never "Treinador IA", "Coach IA" or "AI Coach" |
| AI disclosure | **o aviso de IA** ("precisa do aviso de IA atualizado") | settled 2026-11-13; never "as informações atualizadas sobre IA". Consent wording: CISO/counsel review |
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
| Training (the Settings page: weekly goal, HR zones, fuelling, coach tone) | **Preferências de treino** — tab, page title, and in paths ("Configurações → Preferências de treino") | settled 2026-11-12; a bare "Treino" read as *workout*. The Training nav destination (`navTraining`) stays "Treino" |
| skip a workout / skipped | **Ignorar** / **ignorado** (treino) — un-skip **Deixar de ignorar** | settled 2026-10-21; never "pulado" for the status. Skipping a step or setup is **Pular**; "não pule" stays in coaching advice |
| readiness | **Prontidão** — "Prontidão {score}", "da sua prontidão para correr", "reduzem a sua prontidão", "Excluir a carga do ginásio da prontidão para correr" | settled 2026-11-13; never "preparo" (Brazilian colloquial, and a second word for one score) |
| taper (the plan phase and the act) | **Polimento** — phase "Polimento", "Polimento em torno das provas B/C", "está no polimento", "antes do polimento", "o polimento fica como está", "Em polimento — …" | settled 2026-11-13; never "afinamento", "afunilamento" or "redução de carga" for the taper. "Redução de carga" stays for a *deload* (`planDetail.replanDeload`) |
| a planned gym set that was not performed (status) | **Não atingido** (`gymReviewStatusMissed`, `gym.review.status.missed`), beside "Parcial" | settled 2026-11-13, phone aligned to web; never "Não feito" / "Falhado" |
| Let it go (missed workout) | button **Deixar passar**; its banner says the same act back: "Você deixou passar. Seu plano continua como estava." | settled 2026-11-13; never a bare "Pronto." / "Feito.", which drops what was let go |
| unlinking a matched run | "O treino aparecerá como ainda não concluído" on both platforms (`workoutUnlinkBody`, `workoutDetail.unlinkRunMessage`): the planned item is a *treino*, not a *sessão* | settled 2026-11-13 |
| warm-up / cool-down / recovery | Aquecimento / Desaquecimento / Recuperação | |
| save / settings / feed / followers | Salvar / Configurações (nav "Config.") / Feed / Seguidores | |
| Arm early / Arm anyway | **Preparar mais cedo** / **Preparar mesmo assim** | settled 2026-11-10; the last "Armar antes" / "Armar mesmo assim" / "Arme antes" / "arma a corrida" strings moved to *Preparar* |
| set up (a race created automatically before its start) | **configurada** ("A corrida é configurada um dia antes da largada") | settled 2026-11-10; never "preparada", which is *arm* |
| self-timed (race) | **de tempo próprio** ("corrida de tempo próprio", "Janela de tempo próprio") | settled 2026-11-10; never "com cronometragem própria" / "cronometrada por cada um" |
| GO (the start signal) | **GO** — the button on the web and in the phone app, "GO do organizador", "GO agendado"; prose "dar o GO", "o GO", "após o GO", "aguardando o GO" | settled 2026-11-10; never "JÁ" / "Disparar o Go". *Largada* stays for the start line and the time fields ("linha de largada", "Horário da largada", "Largada às {when}") |

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

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Apple Watch,
Wear OS, HealthKit (the framework), GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF. VO₂ max is **VO₂ máx**. The health platforms take their vendors'
names (`healthPlatformNameIos` / `healthPlatformNameAndroid`): Apple's app
is **Saúde da Apple** as a title and **o app Saúde** in running text;
Google's is **a Conexão Saúde** (feminine: na / à / da Conexão Saúde). Identifiers,
route paths, ICU keywords, `{placeholders}`.

## Provenance

Machine-extracted and model-translated; no native review yet
(`docs/product/followups.md` › "Native review of machine-extracted
translations"). Flag anything you're unsure of rather than guessing.
