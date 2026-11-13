# European Portuguese (pt-PT)

European Portuguese is a separate catalogue from Brazilian, on both
surfaces. Web: `locales/pt-PT.ts`. Mobile: **`app_pt.arb`** (`@@locale`
`pt`): gen-l10n refuses a country-coded file without a bare base, so the
base file carries European Portuguese. `locale_support.dart` maps the tag
`pt-PT` onto it. A bare `pt` and the other European-orthography regions
(`pt-AO`, `pt-MZ`, `pt-CV`) land here too, on both platforms
(decisions.md § 755, § 761). The two catalogues differ on 1,233 of 3,934
mobile keys. **A pt-PT string must never be derived from the pt-BR one by
moving an accent.**

Everything below is derived from the shipped catalogues (measured
2026-10-04 at `28e1267ef`). Counts read "mobile / web" in strings.

## Register — the third-person `você`-form, with `você` itself left out

The reader is addressed in the **third person** (verb in the 3rd person,
`seu`/`sua`, clitics `-o`/`-a`/`-lhe`, `consigo`), and the pronoun **`você`
is never written** (0 / 0). Possessives `seu`/`sua` appear in 298 / 494
strings; the `tu` family (`teu`, `tua`, `podes`, `-te` …) in **zero**. This
was settled across decisions.md § 755, § 760, § 782 and § 784 and is
enforced by guards (below).

- `clubInviteEnterCodeError` (mobile): "Introduza o código de convite do seu link."
- `common.unsavedBody` (web) and `discardChangesBody` (mobile): "Tem alterações não guardadas. Sair sem guardar?"
- `rateLimit.generic` (web): "Está a fazer isto demasiado depressa — aguarde {wait} e tente novamente."
- `profileBlockConfirmBody` (mobile): "Esta pessoa não poderá segui-lo, dar kudos às suas corridas nem comentá-las."

Continuous aspect is **`estar a` + infinitive** ("Está a fazer"), never the
Brazilian gerund ("está fazendo"). Instructions use the formal imperative
("Introduza", "Cole", "Tente novamente"); buttons the infinitive
("Guardar", "Pausar corrida").

Deliberate exceptions: the bare pronoun **`Tu`** is used where a label
names the reader on its own — `navYou` "Tu", web `clubEvent.youTag`
"(tu)", `messages.youPrefix` "Tu: " (§ 760; the register guard does not
list bare `tu` for this reason). Don't extend it to running prose.

## The guards that enforce this (a pt-PT string that breaks them fails the PR)

`apps/web/src/lib/i18n/locale_reach.test.ts` and the "locale reach" group
in `apps/mobile_android/test/architecture_guards_test.dart`:

- **Brazilian-only words are banned**: `você`, `senha`, `tela`, `arquivo`,
  `celular`, `esteira`, `excluir`, `registrar`, `compartilhar`, `baixar`,
  `ônibus`, `geladeira`, `xícara`, `aplicativo`, `cadastrar`, `planejar`,
  `gerenciar`, `tênis`, `quilômetro`, `gênero`, `acessar`, `câmera`,
  `escanear`, `cronômetro`, `oxigênio`, `autônomo`, `autônoma`,
  `planilha`, `usuário`, `deletar`, `esporte`, `pareado`, `pareada`,
  `pareamento`, `monitorar`, `monitoramento`, `login` (and their plurals).
- **`padrão` is banned** except at allowlisted keys meaning *standard* or
  *pattern* (§ 767). A default value is a **`predefinição`**.
- **No tu-register marker** anywhere (`teu`, `tua`, `ti`, `contigo`,
  `podes`, `estás`, `tens`, `queres`, the `-te` enclitic, the proclitic
  `te`, the `-aste`/`-este`/`-iste` preterite …), and no tu affirmative
  imperative that the pt-BR twin doesn't also have.
  A bare third-person verb that opens a clause after a comma reads as a tu
  imperative too: "Antes de definir os ritmos, confirma que …" became
  "… vai confirmar que …" (2026-11-13). Give the clause a subject or a
  future.

## Spelling and style authority

**Acordo Ortográfico de 1990 as applied in Portugal** (Vocabulário
Ortográfico do Português, Portal da Língua Portuguesa; Priberam for
usage): `atualizar`, `direto`, `ativo`, `ótimo`, `ação` (no silent
consonants), but the European forms that AO1990 keeps: `contacto` (21 /
24, never `contato`), `facto`, `receção`. European accents on
proparoxytones: `quilómetro`, `género`, `oxigénio`, `cronómetro`.

House vocabulary (verified in both catalogues): `registar` / `registo`
(never `registrar`/`registro`) for logging, `gravar` / `gravação` for GPS recording, `guardar` (never `salvar`), `partilhar`,
`ecrã`, `telemóvel`, `ficheiro`, `palavra-passe`, `em direto` (live),
`utilizador`, `ginásio`, `passadeira` (treadmill), `aceder`, `equipa`,
`transferir` (download), `pequeno-almoço`, `predefinição`.

## Typography

- Quotes: **“…”**, to match the catalogue. A straight `"` in a message
  fails CI (`messages_parity.test.ts` on web, `architecture_guards_test.dart`
  on mobile — ARB and `app_localizations_pt.dart` getters); the last 60
  moved to curly quotes 2026-10-14. The traditional European « » appears in
  2 / 4 strings; the « » question is a finding.
- Ellipsis **…**; spaced em dash ` — `.
- No space before `:` `!` `?`.
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals — mind the platform difference

Web `pt-PT` uses `Intl.PluralRules('pt-PT')`: `one` = exactly 1. The
phone resolves `app_pt.arb` through intl's **`pt`** rule (its localeName
is `pt`), where `one` = **0 and 1**. So in mobile strings never write a
literal `1` in a `one` branch (it renders "1 …" for 0). Use `{count}` (ARB)
/ `#` (web). And when the plural is the **whole message**, its `one` branch
must name the count ("{count} convite enviado") or the plural must carry an
`=0{…}` branch: a count-free "Convite enviado" is what 0 renders. A plural
inside a longer sentence is agreement and stays as it is. Write the web
twin the same way so the two surfaces read alike. Both rules are guards
(`l10n_parity_test.dart`, `messages_parity.test.ts`).

## Running glossary (what the catalogues already use)

| English | pt-PT | Evidence / note |
|---|---|---|
| run (noun) | corrida / corridas | `nav.runs`, `navRun` "Corrida" |
| pace | Ritmo | |
| split | Parciais | |
| lap | Volta / Voltas | |
| personal record / PR | Recorde pessoal / Recordes pessoais; badge **PR** (web) / "RP" (mobile `gymPrBadge`) | |
| tempo run | Tempo | |
| interval | Intervalo (a step) / Intervalado (workout kind) | |
| long run | Longão | Brazilian running slang, left deliberately pending native review (§ 767) |
| easy run | Leve | |
| elevation gain | **Ganho de elevação** (web); "Subida" (mobile) | `runStatElevation` "Elevação" |
| heart rate / HR | Frequência cardíaca / FC | |
| heart rate zone | Zonas de frequência cardíaca | |
| fitness / fatigue / form (training load: CTL / ATL / TSB) | **Condicionamento** / **Fadiga** / **Forma** — "Condicionamento, fadiga e forma", "Condicionamento (CTL)", "Forma (TSB)", "condicionamento − fadiga". *Fitness* in its everyday sense ("reflete o seu condicionamento atual", VDOT "pontuação de condicionamento") takes the same word, as the English does; same terms as pt-BR | settled 2026-11-12; never "forma física" / "condição física" / bare "Forma" for fitness, never "Frescor" / "frescura" for form. The idiom "Manter a forma" (*stay fit*, `setupGoalGeneralFitness`) is not the noun and stays. The *Fitness* destination (`navFitness`) stays "Fitness" |
| cadence (steps/min) | Cadência | "Frequência" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plano de treino; short Plano(s) | |
| race | **Prova** everywhere: workout kind, nav and tabs ("Provas"), `races.title` "Calendário de provas", race control ("Preparar prova", "Encerrar prova") | settled 2026-10-13; *corrida* is only ever a run, so the Runs and Races tabs no longer collide |
| sign in (in a sentence) | « Inicie sessão » — « Inicie sessão primeiro para … » | settled 2026-11-13 (#1374 round 3.5), both surfaces; a bare « Entre » is only a button label |
| @username help | « nome de utilizador/usuário público (@…) », never « @nome de … » | settled 2026-11-13 (#1374 round 3.5), both surfaces |
| Threkir's gender | **o Threkir** for the app (« no Threkir », « do Threkir »); **a Threkir** only for the company in legal and consent text (« em nome da Threkir ») | settled 2026-11-13 (#1374 round 3.5), both surfaces |
| cue (guided run) | **dica** / dicas — « Ouvir dica », « # dicas na corrida » | settled 2026-11-13 (#1374 round 3.5), both surfaces; never « alerta », « sinal » or « indicação » for a guided-run cue (a session plan's breath / alignment cue stays « Indicação ») |
| backup (the full archive you download and restore) | **cópia de segurança** (feminine: « a cópia de segurança completa », « nesta cópia de segurança ») | settled 2026-11-13 (#1374 round 3.5), both surfaces; never « backup » |
| build (the plan's build phase) | **construção** — « semanas de construção », « Encurtar a construção » | settled 2026-11-13 (#1374 round 3.5), both surfaces; never « desenvolvimento » |
| gun time / chip time | **Tempo oficial** / **Tempo de chip**; short forms "oficial {gun} · chip {chip}" | settled 2026-10-13; not "bruto"/"líquido" (Brazilian race-results usage) nor "tempo real" (collides with *em tempo real*) |
| finish | Chegada (finish line); Concluído (status); Concluir (mobile) / Finalizar (web) action | |
| DNF | DNF; "Não concluiu" (web `checkpoint.statusDnf`) | |
| route | Rota / Rotas (100 / 138); percurso for a course | |
| segment | Segmento / Segmentos | |
| club | Clube / Clubes | |
| event | Evento / Eventos | |
| gym | **Ginásio** | |
| nutrition | Nutrição | |
| log (verb) | Registar | `navLog` |
| record (GPS / an activity), recording | **Gravar** / **gravação** — "A gravar", "Gravação e voz", "Começar uma gravação", "corrida gravada", "distância gravada", "grave com uma cinta" | settled 2026-11-12; never *registar* / *registo* for recording. *Registar* / *registo* stay for logging (manual entry, diary, gym and food log), sign-up, records on file (consent, DNF / DNS, weigh-ins, payment records, a DNS record) and a race finish being recorded |
| streak | Sequência | |
| goal | Meta / Metas (dominant); "Objetivo" on web onboarding and plans | |
| coach (a person) | **Treinador** | `coaching.*`, guided-run "voz de treinador" |
| AI Coach (the product) | **Coach** as its name (capital C, also mid-sentence: "o Coach está a pensar"); **Coach de IA** where the English says *AI Coach* | settled 2026-10-13; never "Treinador IA", "Coach IA" or "AI Coach" |
| AI disclosure | **o aviso de IA** ("precisa do aviso de IA atualizado") | settled 2026-11-13; never "as informações atualizadas sobre IA". Consent wording: CISO/counsel review |
| Pro & support | **Pro e apoio** | *support* here is supporting the app ("apoiar a app"); "suporte" is tech support |
| sign in | **Iniciar sessão** ("Inicie sessão…", "início de sessão", "sem sessão iniciada"); a bare "Entrar" on a button | never "login" / "Faça login" — guarded |
| pair (Bluetooth) | **Emparelhar** / emparelhado / emparelhamento | never "parear" — guarded |
| auto-pause | — | no catalogue string yet; build from "Corrida pausada" / "Pausar" → "Pausa automática", and flag it as a new term |
| kudos | kudos ("dar kudos", "remover kudos") | |
| workout | Treino | |
| Training (the Settings page: weekly goal, HR zones, fuelling, coach tone) | **Preferências de treino** — tab, page title, ; a string names the page, never a path to it (decisions § 2496) | settled 2026-11-12; a bare "Treino" read as *workout*. The Training nav destination (`navTraining`) stays "Treino" |
| skip a workout / skipped | **Ignorar** / **ignorado** (treino) — un-skip **Deixar de ignorar**; status = **estado** | settled 2026-10-21; never "saltado" for the status. Skipping a step or setup is **Saltar**; "não salte" stays in coaching advice |
| readiness | **Prontidão** — "Prontidão {score}", "da sua prontidão para correr", "reduzem a sua prontidão", "Deixar a carga do ginásio fora da prontidão para correr" | settled 2026-11-13; never "preparo" (Brazilian colloquial, and a second word for one score) |
| taper (the plan phase and the act) | **Polimento** — phase "Polimento", "Polimento em torno das provas B/C", "está no polimento", "antes do polimento", "o polimento fica como está", "Em polimento — …" | settled 2026-11-13; never "afinamento", "afunilamento" or "redução de carga" for the taper. "Redução de carga" stays for a *deload* (`planDetail.replanDeload`) |
| a planned gym set that was not performed (status) | **Não atingido** (`gymReviewStatusMissed`, `gym.review.status.missed`), beside "Parcial" | settled 2026-11-13, phone aligned to web; never "Não feito" / "Falhado" |
| Let it go (missed workout) | button **Deixar passar**; its banner says the same act back: "Deixou passar. O seu plano continua como estava." | settled 2026-11-13; never a bare "Pronto." / "Feito.", which drops what was let go |
| unlinking a matched run | "O treino aparecerá como ainda não feito" on both platforms (`workoutUnlinkBody`, `workoutDetail.unlinkRunMessage`): the planned item is a *treino*, not a *sessão* | settled 2026-11-13 |
| warm-up / cool-down / recovery | Aquecimento / Desaquecimento / Recuperação | |
| save / settings / feed / followers | Guardar / **Definições** / Feed / Seguidores | `navSettings` is "Config." — inconsistency 3 |
| app | **a app** (feminine, from *a aplicação*): "na app", "da app", "esta app", "outra app", plural "as apps" | settled 2026-10-13; never "aplicação" in UI text (the last web and phone strings moved 2026-11-10). Only an Android menu path quotes the OS ("Definições → Aplicações") |
| arm / armed (race control) | **Preparar** / **preparada** — "Preparar prova", "Prova preparada", "Preparar mais cedo", "Preparar na mesma", "Prepare-a mais cedo" | settled 2026-11-10; never "Armar" / "armada" / "Arme", never "mesmo assim" |
| set up (a race created automatically before its start) | **configurada** ("A prova é configurada um dia antes da partida") | settled 2026-11-10; never "preparada", which is *arm* |
| self-timed (race) | **de tempo próprio** ("prova de tempo próprio", "Janela de tempo próprio") | settled 2026-11-10; never "com cronometragem própria" / "cronometrada por cada um" |
| GO (the start signal) | **GO** — the button on the web and in the phone app, "GO do organizador", "GO agendado"; prose "dar o GO", "o GO", "depois do GO", "a aguardar o GO" | settled 2026-11-10; never "JÁ" / "Disparar o Go" for the button or "dar a partida" for the signal. *Partida* stays for the start line and the time fields ("linha de partida", "Hora da partida", "Partida às {when}") |
| race on the Wear watch | "PROVA PREPARADA", "Prova encerrada", "Terminar prova", "Prova {clock}", "Prova DNF" | settled 2026-11-10; *corrida* only where the watch means a run ("Esta corrida é a minha tentativa") |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. ~~**run vs race**~~ — settled 2026-10-13: race is always *prova*.
2. **plural `one` with literal 1** in 11 mobile strings, made worse by the
   phone's `pt` plural rule — see Plurals.
3. **settings**: mobile `navSettings` "Config." abbreviates
   *Configurações*, a Brazilian word; everywhere else (incl. mobile
   `runSettings`) is "Definições".
4. ~~**"app" gender**~~ — settled 2026-10-13: *a app*.
5. **elevation gain**: Subida / Ganho de elevação / Elevação.
6. **PR badge**: RP (mobile) vs PR (web).
7. **goal**: Meta vs Objetivo.
8. **Longão** — see glossary.
9. **finish action**: "Concluir" (mobile `gymSessionFinish`,
   `sessionRunFinish`) vs "Finalizar" (web `gym.session.finish`,
   `session.run.finish`).

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Apple Watch,
Wear OS, HealthKit (the framework), GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF. VO₂ max is **VO₂ máx** (`metric.vo2max.label`). The health platforms
take their vendors' names (`healthPlatformNameIos` /
`healthPlatformNameAndroid`): Apple's app is **Saúde da Apple** as a title
and **a app Saúde** in running text; Google's is **a Conexão Saúde**
(feminine: na / à / da Conexão Saúde). Identifiers, route paths, ICU keywords, `{placeholders}`.

## Provenance

Model-authored and **not natively reviewed** (decisions.md § 767;
`docs/product/followups.md` › "Native review of machine-extracted
translations"). The Wear OS and watchOS pt-PT sets are guarded by the same
scan but are outside these agents' scope. Flag anything you're unsure of.
