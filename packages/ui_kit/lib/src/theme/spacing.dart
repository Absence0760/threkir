import 'package:flutter/widgets.dart';

/// The spacing scale. Each rung that web has carries web's name for it, so a
/// layout reads the same on both platforms: `AppSpace.md` is
/// `--space-md` (16), `AppSpace.lg` is `--space-lg` (24). `xxs` and `xxl` are
/// web's `--space-2xs` and `--space-2xl`, since a Dart name can't start with a
/// digit. `test/spacing_test.dart` reads `apps/web/src/app.css` and fails when
/// a shared rung's value drifts from web's.
///
/// [smPlus] is mobile's own: 12 is the app's second most common gap (205 of
/// 831 `SizedBox(height:)` sites, issue #1374 report 5 § 1c) and web has no
/// rung for it.
abstract final class AppSpace {
  /// `--space-2xs`.
  static const double xxs = 2;

  /// `--space-xs`.
  static const double xs = 4;

  /// `--space-sm`.
  static const double sm = 8;

  /// Mobile only, between [sm] and [md].
  static const double smPlus = 12;

  /// `--space-md`: the page gutter.
  static const double md = 16;

  /// `--space-lg`: the gap between sections.
  static const double lg = 24;

  /// `--space-xl`.
  static const double xl = 32;

  /// `--space-2xl`.
  static const double xxl = 48;

  /// Every rung, smallest first, for a guard or a caller that snaps a value.
  static const List<double> scale = [xxs, xs, sm, smPlus, md, lg, xl, xxl];
}

/// The named insets a page is laid out with, built from [AppSpace].
abstract final class AppInsets {
  /// The side gutter of every page and sheet. Web's narrow
  /// `--page-padding-x`.
  static const double gutter = AppSpace.md;

  /// From the chrome above (a tab strip, a filter row) to the first row.
  static const double pageTop = AppSpace.smPlus;

  /// Between two sections of a page.
  static const double sectionGap = AppSpace.lg;

  /// Between two cards or rows of a list; the value
  /// `list_separator_guard_test` already pins.
  static const double itemGap = AppSpace.sm;

  /// A card's inner padding.
  static const EdgeInsets card = EdgeInsets.all(AppSpace.md);

  /// A dense card's inner padding.
  static const EdgeInsets cardDense =
      EdgeInsets.fromLTRB(AppSpace.md, AppSpace.smPlus, AppSpace.md, AppSpace.smPlus);

  /// A modal sheet's padding, before the system inset `SheetScaffold` adds.
  static const EdgeInsets sheet =
      EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md);

  /// A page's list: the gutter on both sides and [pageTop] above.
  static const EdgeInsets page =
      EdgeInsets.fromLTRB(gutter, pageTop, gutter, 0);
}
