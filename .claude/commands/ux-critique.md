---
description: Judge whether a surface is something someone will enjoy using — web, mobile, or both in parallel — via the read-only `ux-critic` agent. Reports a ranked verdict; never edits.
argument-hint: <surface> [web|mobile|both]
---

Critique the UX of `$ARGUMENTS` with the `ux-critic` agent. **Read-only** — this command reports, it does not change code.

Use it when the question is *"is this good to use?"* rather than *"is this screen well laid out?"* or *"does it contain a known anti-pattern?"* A surface can pass `/polish-ui`, `/ux-hunt` and `/a11y-hunt` and still be tiring, because what makes a product enjoyable is not a property of any single screen.

## Which tool for which question

| Question | Tool |
| --- | --- |
| Is **this screen** well composed? | `/polish-ui` |
| Does this surface hold a **known anti-pattern**? | `/ux-hunt` |
| Does it clear **WCAG 2.2 AA**, measured? | `/a11y-hunt` |
| Would someone **enjoy using** this? | **this command** |

## Resolving the target

`$ARGUMENTS` is a surface plus an optional platform. A surface is a route or screen and what it reaches in a couple of steps — "clubs", "onboarding", "the fitness hub", "/dashboard", "gear".

- A **web route** (`/clubs`, `/dashboard`) → `apps/web/src/routes/<slug>/`.
- A **mobile screen** (`clubs_screen`, `fitness_hub`) → `apps/mobile_android/lib/screens/<name>_screen.dart`.
- A **bare concept** ("clubs", "nutrition") → resolve on both platforms.

Resolve by listing, never by assuming a path exists:

```bash
ls apps/web/src/routes | grep -i <surface>
ls apps/mobile_android/lib/screens | grep -i <surface>
```

If the surface exists on only one platform, check `docs/product/parity.md` before reporting that as a gap — it may be a deliberate parity position, in which case say so and critique the platform it does ship on.

## Picking the platform

The optional second argument is `web`, `mobile`, or `both`. **Default to `both` when the surface resolves on both platforms**, because the highest-value findings are the ones present on each — that is the same reasoning `/ux-hunt` uses.

Watch surfaces (`apps/watch_wear`, `apps/watch_ios`, `apps/custom_watch`) are out of scope: they are glance-first, wrist-only complements ([decisions § 24](../../docs/architecture/decisions.md)) and judging them against a pocket-app rubric produces noise. Say so and offer the matching watch persona agent instead.

## Running it

**Spawn one `ux-critic` per platform, in a single message, so they run in parallel.** Each gets its own platform and its own surface paths; neither tries to cover both, because the method is inhabiting one person on one device.

Tell each agent, explicitly:

- the platform (`web` or `mobile`),
- the resolved paths for that platform's surface,
- that it is read-only and writes its findings to `reviews/ux-critic-<platform>-<surface>.md`,
- to flag, per finding, whether it believes the same problem exists on the other platform (or to say "not checked").

Mobile note to pass on: read and cite `apps/mobile_android`, never `apps/mobile_ios` — they are byte-identical twins ([decisions § 39](../../docs/architecture/decisions.md)), and an iOS-only behaviour is a `Platform.isIOS` branch inside the shared file.

## Merging the two verdicts

When both ran, do not just concatenate. Produce:

1. **One verdict paragraph** for the surface as a product, naming the single thing most in the way.
2. **Cross-platform findings first** — anything both critics reported, or one reported and the other confirmed. These are the highest-value items: one root cause, two surfaces, and usually one shared decision behind them.
3. **Then per-platform findings**, each labelled `blocking` / `corrosive` / `polish`.
4. **Divergences worth naming**: where the two platforms solve the same problem differently and one is clearly better. That is a consistency finding the single-platform tools structurally cannot see.
5. **What was deliberately left out**, from both.

Keep the merged list to roughly a dozen. Two ten-item reports concatenated is twenty items nobody acts on.

## After the verdict

You are read-only, so end by offering the route to action rather than taking it:

- a **blocking** or **corrosive** finding that is a known anti-pattern → `/ux-hunt <surface>` fixes it cross-platform with tests and i18n.
- a finding that is really composition → `/polish-ui <target>`.
- anything you named a number for (contrast, tap size, text scale) → `/a11y-hunt <surface>`, which computes rather than eyeballs.
- a genuine gap in what the product does → `docs/product/followups.md` or the roadmap, not a UX fix.

Do not apply fixes from this command, and do not commit. The user decides what is worth acting on.
