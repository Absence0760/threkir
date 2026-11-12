import 'package:flutter/material.dart';

/// The colours a chart draws its marks in — one per-brightness palette shared
/// by every data-visualisation surface, so a runner reading two charts on one
/// screen reads one colour system.
///
/// Four scales, because charts need four shapes of answer:
///
///  * [series] is CATEGORICAL — unordered things drawn together (fitness /
///    fatigue / form). Entries separate by LUMINANCE rather than hue, which is
///    what survives greyscale and red-green colour-vision deficiency. Pairwise
///    3:1 between three series is unreachable once each also owes 3:1 to the
///    card it is drawn on: it forces the extreme pair past 9:1, and light's
///    whole usable range is 5.98:1. So the floor between entries is the
///    achievable one and the ORDER is what holds — a monotone ladder.
///  * [zones] is ORDINAL — the five heart-rate bands, an ordered scale whose
///    steps are named. Same luminance-ladder reasoning as [series], and five
///    bands genuinely cannot be pairwise 3:1: four steps of 3:1 need 81:1 and
///    sRGB offers 21:1. What each band owes is 3:1 against the surface behind
///    the bar, which is what makes a separator drawn in that surface colour
///    visible against both its neighbours. Draw the bar with
///    [zoneSeparatorWidth] of the ambient background between segments. The ramp
///    direction inverts with the background (§489): the cool recovery end
///    always sits furthest from the page and the hot end nearest it, because a
///    saturated red cannot occupy the far end of either ramp without turning
///    brown-black on light or pink-white on dark.
///  * [ramp] is SEQUENTIAL — one quantity at increasing intensity (a heatmap
///    cell, a bar's fill). Single-hue, monotone, each step clearing WCAG
///    1.4.11's 3:1 non-text floor against its card, adjacent steps ~1.85:1
///    apart. Built as a tint ladder from the card toward [series]`.first`, so
///    the ramp's top step and the categorical scale's most legible entry are
///    the same colour and there is one intensity ladder in the app.
///  * [kinds] is CATEGORICAL too, and separate from [series] rather than an
///    extension of it: [series] means the three training-load curves and is
///    pinned at three entries by the web lockstep, while these are the six
///    planned-workout groups a plan calendar marks its days with. Six groups
///    cannot be pairwise 3:1 either — five steps of 3:1 need 243:1 — so the
///    same bargain holds: 3:1 against every surface the mark is drawn on, and
///    a monotone luminance ladder between the entries. Index order is the
///    ladder, coolest and furthest from the page first:
///    0 easy/recovery, 1 long/race, 2 tempo, 3 marathon pace,
///    4 interval/walk-run, 5 rest. That order is hue temperature, NOT session
///    prominence: §489's constraint fixes which hues can occupy which end (a
///    saturated red cannot be the far end without going brown-black on light),
///    and prominence is not what tells one kind from another — the localized
///    kind WORD beside the mark is, which is why these paint marks only.
///
/// `colorScheme.primary` is deliberately NOT a chart colour. It is a brand and
/// interaction token whose hue is not stable across brightnesses — dusk in
/// light, coral in dark — so a mark painted in it means "data" in one theme and
/// collides with an interaction affordance (or another chart's warm series) in
/// the other. Charts take their marks from here.
///
/// Web's `--chart-fitness` / `--chart-fatigue` / `--chart-form`,
/// `--zone-1`..`--zone-5` and `--kind-1`..`--kind-6` in `apps/web/src/app.css`
/// are [series], [zones] and [kinds] by value, per brightness; all three
/// locksteps are asserted from the web side, by scale name, in
/// `apps/web/src/lib/contrast_guard.test.ts` — renaming a scale here breaks a
/// guard in the other language's suite. [ramp] has no web twin and is not owed
/// one: web retired its only sequential surface, the dashboard calendar
/// heatmap, in favour of the Training intensity card (§ 515).
@immutable
class ChartPalette {
  const ChartPalette({
    required this.series,
    required this.zones,
    required this.ramp,
    required this.kinds,
  });

  final List<Color> series;
  final List<Color> zones;
  final List<Color> ramp;
  final List<Color> kinds;

  /// Gap between zone-bar segments, filled with the surface behind the bar.
  static const double zoneSeparatorWidth = 2;

  /// A single-series chart is a one-level ramp, so its bars draw the ramp's
  /// top step — the same colour the heatmap's busiest day gets.
  Color get bar => ramp.last;

  /// "Dusk, refined" hues (decisions § 1772) at the luminances the § 495 /
  /// § 516 ladders were measured at. Contrast against the white card —
  /// series: 14.849 / 3.468 / 7.369;
  /// zones z1->z5: 16.743 / 11.214 / 7.665 / 5.236 / 3.590;
  /// ramp: 4.326 / 8.002 / 14.849;
  /// kinds 0->5: 16.874 / 12.575 / 9.555 / 7.229 / 5.446 / 4.123.
  static const light = ChartPalette(
    series: [
      Color(0xFF340F68),
      Color(0xFFB97E12),
      Color(0xFFA62115),
    ],
    zones: [
      Color(0xFF121B3F),
      Color(0xFF114421),
      Color(0xFF714C09),
      Color(0xFFAE520A),
      Color(0xFFE65846),
    ],
    ramp: [
      Color(0xFF7E73A1),
      Color(0xFF584684),
      Color(0xFF340F68),
    ],
    kinds: [
      Color(0xFF032122),
      Color(0xFF13345B),
      Color(0xFF6C2C68),
      Color(0xFF774F05),
      Color(0xFFC72F20),
      Color(0xFF7E7B8B),
    ],
  );

  /// "Dusk, refined" hues (decisions § 1772) at the luminances the § 495 /
  /// § 516 ladders were measured at. Contrast against the nightRaised card —
  /// series: 14.017 / 6.865 / 3.524;
  /// zones z1->z5: 14.659 / 10.330 / 7.317 / 5.197 / 3.677;
  /// ramp: 4.085 / 7.588 / 14.017;
  /// kinds 0->5: 15.383 / 12.743 / 10.379 / 8.571 / 7.056 / 5.803.
  static const dark = ChartPalette(
    series: [
      Color(0xFFEAE5FE),
      Color(0xFFE1931D),
      Color(0xFFCF3C13),
    ],
    zones: [
      Color(0xFFE6EDFF),
      Color(0xFF95D8A3),
      Color(0xFFD99F2C),
      Color(0xFFE16C10),
      Color(0xFFD83727),
    ],
    ramp: [
      Color(0xFF7F7798),
      Color(0xFFAFA8CA),
      Color(0xFFEAE5FE),
    ],
    kinds: [
      Color(0xFFDBF8F9),
      Color(0xFFCAE0FC),
      Color(0xFFE7BCE2),
      Color(0xFFE9AC4F),
      Color(0xFFED8B84),
      Color(0xFF9794A5),
    ],
  );

  static ChartPalette of(BuildContext context) => ofTheme(Theme.of(context));

  static ChartPalette ofTheme(ThemeData theme) =>
      theme.brightness == Brightness.dark ? dark : light;
}
