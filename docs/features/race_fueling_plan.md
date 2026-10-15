# Race fueling plan — carbs/hr + fluids synced to the course

> **STATUS: shipped (2026-06-14).** Web canonical (`/routes/[id]/roadbook`
> Fueling toggle) + mobile (`RoadbookScreen`) + iOS twin byte-identical. The
> fueling half of the roadbook ([race_roadbook.md](race_roadbook.md) §
> Fueling). Read [CLAUDE.md](../../CLAUDE.md) for conventions. In-run
> reminders are a deferred separate phase (see § Decisions made).

## Context / why

The roadbook is pacing-only by design. This adds the fueling layer: a per-leg
**carbs/hr** + **fluid** plan synced to the aid-station timeline — "carry 3 gels
to Aid 2, refill 500 ml". It fuses the nutrition rates with the route, which no
competitor does. In-run reminders are a deferred separate phase.

## Reuse (it builds on, doesn't re-implement)

- **Roadbook engine** `roadbook.ts ↔ roadbook.dart`: produces the per-leg
  duration + aid-station schedule. `fuel_plan` consumes its legs — it does not
  fork the pacing model, so fueling inherits the grade-adjusted-effort
  allocation for free (a long climb leg gets proportionally more fuel).
- **`runCalories`** (run kcal from distance + duration) computes the optional
  per-leg energy figure when a bodyweight is present.

## Design (as shipped)

1. **Parity helper** `apps/web/src/lib/routes/fuel_plan.ts` ↔
   `apps/mobile_android/lib/fuel_plan.dart` (iOS twin byte-identical):
   `buildFuelPlan(roadbookLegs, { carbsPerHourG, fluidPerHourMl, heatFactor?,
   gelCarbsG?, weightKg? })` → per-leg `{ carbsG, fluidMl, kcal, carryToNextAid?:
   { carbsG, fluidMl, gels } }` + `{ totalCarbsG, totalFluidMl }`. Carbs/fluid
   scale with each leg's **duration** (from the roadbook). `carryToNextAid` is
   present on the start leg + each refill checkpoint whose services include
   water/food, summing the fuel needed to reach the next refill (inclusive).
   `heatFactor` (default 1; `HEAT_FLUID_FACTOR` = 1.5) multiplies fluid only.
   `kcal` is computed via `runCalories` only when a bodyweight is passed.
   Defaults: 60 g/hr carbs, 500 ml/hr fluid, 25 g/gel. 9 unit/mirror tests each
   side.
2. **Roadbook surface:** a "Fueling" toggle on the roadbook page (web,
   URL-backed) + `RoadbookScreen` (mobile, screen-local) adding per-leg carb +
   fluid columns + the carry hint, plus a "Heat" toggle. kcal is computed but
   not shown.
3. **Settings:** `carbs_per_hour` (g/hr) + `fluid_per_hour` (ml/hr) prefs in the
   universal settings bag (defaults 60 / 500), editable on Settings →
   Preferences. See [settings.md](../backend/settings.md).

No new schema (prefs in the existing universal bag).

## Coach fuelling handoff (2026-10-15, decisions § 1975)

The Coach no longer only refuses "how should I fuel my long run / race?".
Behind a default-off flag it answers with one link to **`/nutrition/fuel`**, a
route-less fuelling plan for a single run: the same `buildFuelPlan` over one
start-to-finish leg, showing total carbohydrate, the gel count and total fluid,
with a Heat toggle. The link carries `duration` (whole seconds, from the plan,
a comparable recent run or a time the runner gave) and `carbs` / `fluid` /
`heat` only when the runner stated them; otherwise the page uses the runner's
saved `carbs_per_hour` / `fluid_per_hour`, then the defaults, and labels which
source each rate came from.

- **Validation.** `parseFuelHandoff` (`apps/web/src/lib/routes/fuel_params.ts`)
  reads only plain non-negative numbers, refuses a rate above the Settings
  ceilings (200 g/h, 3000 ml/h) and a duration outside 10 min – 7 days, and
  DROPS an out-of-range value rather than clamping it. The roadbook's
  `?carbs=` / `?fluid=` overrides go through the same parser.
- **Still forbidden in the Coach:** naming foods, drinks, products, brands or
  supplements, calorie targets, and any carbohydrate / fluid / sodium amount of
  the model's own (`system_prompt.ts`, pinned by `system_prompt.test.ts`).
- **No new AI disclosure version:** the link is built from context the Coach
  already sends (plan, recent runs, chat). See § 1975 for the argument.
- **Mobile:** the phone has no route-less fuelling screen; its Coach opens the
  link on the web host (`coachFuelLinkWebUrl` in `coach_screen.dart`).
- **Gates:** `PUBLIC_COACH_FUEL_ENABLED` (page, `coach_fuel_flag.ts`) and the
  coach Lambda's `COACH_FUEL_ENABLED` (prompt addendum, sops
  `coach_config_keys`). Both default off.

### Pre-deploy checklist (Coach fuelling handoff)

- [ ] Owner sign-off: the Coach answering fuelling questions through the
  deterministic plan (reverses § 12 in part).
- [ ] Counsel sign-off: the liability surface § 12 named, the system-prompt
  prohibitions, and the page's "planning totals, not a prescription" copy in
  all seven locales.
- [ ] Then set `PUBLIC_COACH_FUEL_ENABLED` (release-web secret) and
  `COACH_FUEL_ENABLED` (sops) together.

## Weight-based fluid (2026-10-15, decisions § 1976)

An opt-in **"Fluid from body weight"** toggle beside Heat (web `?bw=1` on
`/routes/[id]/roadbook` and `/nutrition/fuel`; screen-local on mobile
`RoadbookScreen`) replaces the flat fluid rate with
`weightFluidPerHourMl(weight)`: the 500 ml/h default scaled by body mass from a
70 kg reference, rounded to 25 ml and held to the ACSM 400–800 ml/h marathon
band (Sawka et al. 2007). Heat still multiplies it.

- **Consent-gated.** The weight is the latest `body_metrics` row, passed through
  `healthUseWeightKg` (the `health_consent` pair) so it is used only while
  `health_data_consent_at` is on record. Without consent or a weight the toggle
  is disabled with the reason and the flat rates stand.
- **No sodium figure:** sweat sodium varies independently of body mass; nothing
  published derives it from weight.
- **Not persisted** (like Heat) and not pushed to the custom watch, which keeps
  the synced flat `fluid_per_hour`.

### Pre-deploy checklist (weight-based fluid)

- [ ] CISO / counsel review: a new Art 9 use of body weight (fluid planning),
  covered by the existing health-data consent copy? If the copy names its uses
  exhaustively, add fuelling to it before deploy.

## Commit cadence

1. ✅ `fuel_plan.ts/.dart` helper + unit/mirror tests.
2. ✅ Web roadbook fueling toggle + Heat toggle + settings prefs + i18n (6
   locales) + Playwright.
3. ✅ Mobile mirror (+ iOS twin) + ARB keys (7 ARBs) + Flutter test.
4. ✅ Docs.

## Tests

- Unit: carbs/fluid scale with leg duration; `carryToNextAid` sums the gap
  between aids correctly; heat factor bumps fluid; zero-duration leg → zero.
- Playwright: toggle fueling on the roadbook, assert per-leg carbs + a carry
  hint; changing the carbs/hr pref updates the numbers.
- Flutter widget test for the fueling section.

## Decisions made

- **Flat per-hour rates, not weight-derived** (superseded in part by the
  opt-in weight-based fluid above, decisions § 1976). `carbs_per_hour` / `fluid_per_hour`
  are plain per-hour prefs (60 / 500 defaults), deliberately **not** a
  weight-based sweat-rate / ml-per-kg model — that keeps the feature out of the
  Art 9 health-special-category consent gate. The weight-derived fluid model
  (behind the gate) is the deferred upgrade.
- **Heat is a non-persisted toggle.** The "Heat" toggle multiplies fluid only
  (`HEAT_FLUID_FACTOR` = 1.5); it is a screen/URL toggle, not a stored pref, so
  the saved baseline stays moderate-conditions.
- **kcal is computed but not shown.** `buildFuelPlan` returns a per-leg `kcal`
  (via `runCalories`, only when a bodyweight is present) for a possible later
  surface, but the UI omits it to avoid clutter.
- **In-run reminders deferred to a separate phase.** They need the run recorder
  + the live workout band (`workout_execution_band.dart`); this feature ships
  plan-only.

See [decisions.md § 155](../architecture/decisions.md#155-the-race-fueling-plan-extends-the-roadbook-engine-with-flat-per-hour-rate-prefs-not-weight-derived-sweat-estimates)
for the full rationale.

## Docs

Cross-references: [race_roadbook.md](race_roadbook.md) § Fueling,
[decisions.md § 1975](../architecture/decisions.md) (Coach fuelling handoff),
[settings.md](../backend/settings.md) (`carbs_per_hour` / `fluid_per_hour`),
[parity.md](../product/parity.md) (Race fueling plan row), and
[decisions.md § 155](../architecture/decisions.md).
