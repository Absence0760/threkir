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
  `planilha`, `usuário`, `deletar`, `esporte` (and their plurals).
- **`padrão` is banned** except at allowlisted keys meaning *standard* or
  *pattern* (§ 767). A default value is a **`predefinição`**.
- **No tu-register marker** anywhere (`teu`, `tua`, `ti`, `contigo`,
  `podes`, `estás`, `tens`, `queres`, the `-te` enclitic, the proclitic
  `te`, the `-aste`/`-este`/`-iste` preterite …), and no tu affirmative
  imperative that the pt-BR twin doesn't also have.

## Spelling and style authority

**Acordo Ortográfico de 1990 as applied in Portugal** (Vocabulário
Ortográfico do Português, Portal da Língua Portuguesa; Priberam for
usage): `atualizar`, `direto`, `ativo`, `ótimo`, `ação` (no silent
consonants), but the European forms that AO1990 keeps: `contacto` (21 /
24, never `contato`), `facto`, `receção`. European accents on
proparoxytones: `quilómetro`, `género`, `oxigénio`, `cronómetro`.

House vocabulary (verified in both catalogues): `registar` / `registo`
(never `registrar`/`registro`), `guardar` (never `salvar`), `partilhar`,
`ecrã`, `telemóvel`, `ficheiro`, `palavra-passe`, `em direto` (live),
`utilizador`, `ginásio`, `passadeira` (treadmill), `aceder`, `equipa`,
`transferir` (download), `pequeno-almoço`, `predefinição`.

## Typography

- Quotes: the catalogues use **“…”** (19 / 6) with straight `"` slips;
  the traditional European « » appears in 2 / 4 strings. Use “…” to match
  the catalogue; the « » question is a finding.
- Ellipsis **…**; spaced em dash ` — `.
- No space before `:` `!` `?`.
- Literal number samples use the decimal comma ("5,0 km · 5:00 /km").

## Plurals — mind the platform difference

Web `pt-PT` uses `Intl.PluralRules('pt-PT')`: `one` = exactly 1. The
phone resolves `app_pt.arb` through intl's **`pt`** rule (its localeName
is `pt`), where `one` = **0 and 1**. So in mobile strings never write a
literal `1` in a `one` branch — 11 already do (e.g. `importFailuresHeading`),
rendering "1 …" for 0. Use `{count}` (ARB) / `#` (web).

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
| cadence (steps/min) | Cadência | "Frequência" in `discover.cadenceLabel` means *recurrence* |
| training plan | Plano de treino; short Plano(s) | |
| race | **Prova** (workout kind, run source); "Corridas" in nav, tabs and `races.title` "Calendário de corridas" | collides with *run* — inconsistency 1 |
| finish | Chegada (finish line); Concluído (status); Concluir (mobile) / Finalizar (web) action | |
| DNF | DNF; "Não concluiu" (web `checkpoint.statusDnf`) | |
| route | Rota / Rotas (100 / 138); percurso for a course | |
| segment | Segmento / Segmentos | |
| club | Clube / Clubes | |
| event | Evento / Eventos | |
| gym | **Ginásio** | |
| nutrition | Nutrição | |
| log (verb) | Registar | `navLog` |
| streak | Sequência | |
| goal | Meta / Metas (dominant); "Objetivo" on web onboarding and plans | |
| coach | Treinador; AI Coach = **Treinador IA** | web `coachChat.coach` "Coach" |
| auto-pause | — | no catalogue string yet; build from "Corrida pausada" / "Pausar" → "Pausa automática", and flag it as a new term |
| kudos | kudos ("dar kudos", "remover kudos") | |
| workout | Treino | |
| warm-up / cool-down / recovery | Aquecimento / Desaquecimento / Recuperação | |
| save / settings / feed / followers | Guardar / **Definições** / Feed / Seguidores | `navSettings` is "Config." — inconsistency 3 |
| app | app — gender mixed | inconsistency 4 |

## Known inconsistencies (findings for the user — don't fix them in a batch)

1. **run vs race**: web `runSurface.tabRuns` and `runSurface.tabRaces` both
   render "Corridas" on one tab bar (`RunSurfaceTabs.svelte`); "Prova" is
   used for race elsewhere and would separate them.
2. **plural `one` with literal 1** in 11 mobile strings, made worse by the
   phone's `pt` plural rule — see Plurals.
3. **settings**: mobile `navSettings` "Config." abbreviates
   *Configurações*, a Brazilian word; everywhere else (incl. mobile
   `runSettings`) is "Definições".
4. **"app" gender**: "o app" (14 / 16 strings) vs "a app" (3 / 5);
   European usage is usually feminine (*a app*, from *a aplicação*).
5. **elevation gain**: Subida / Ganho de elevação / Elevação.
6. **PR badge**: RP (mobile) vs PR (web).
7. **goal**: Meta vs Objetivo.
8. **Longão** — see glossary.
9. **finish action**: "Concluir" (mobile `gymSessionFinish`,
   `sessionRunFinish`) vs "Finalizar" (web `gym.session.finish`,
   `session.run.finish`).

## Don't translate

Threkir, Pro, Strava, Garmin, parkrun, Health Connect, Apple Watch,
Wear OS, HealthKit, GPX/TCX/FIT, VDOT, CTL, ATL, TSB, TRIMP, RPE, 1RM, GAP,
DNF. VO₂ max is **VO₂ máx** (`metric.vo2max.label`). Apple's app is
**Apple Saúde**. Identifiers, route paths, ICU keywords, `{placeholders}`.

## Provenance

Model-authored and **not natively reviewed** (decisions.md § 767;
`docs/product/followups.md` › "Native review of machine-extracted
translations"). The Wear OS and watchOS pt-PT sets are guarded by the same
scan but are outside these agents' scope. Flag anything you're unsure of.
