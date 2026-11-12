import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// `AppTheme`'s own component themes, measured where they paint (issue #666,
/// the round-12 open item).
///
/// The navigation bar's selected icon is drawn INSIDE the indicator pill, so
/// the pill is the background it owes WCAG 1.4.11's 3:1 against — not the bar.
/// Measuring on the bar is §503's recorded trap and it flatters the light
/// theme: `coralDeep` reads 2.767:1 on parchment and 2.337:1 on the pill it
/// actually lands on. The FAB is the other half of the same token problem, and
/// there the answer is the opposite way round — the glyph moved, not the fill,
/// because a FAB carries its own elevation and shadow, so under §503's
/// foreground-XOR-fill rule the boundary is not the fill's to earn.
///
/// Every figure is computed from the real tokens. Each repair is pinned in both
/// directions, so reverting one fails here rather than passing quietly.
double _luminance(Color c) {
  double chan(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _over(Color c, Color bg) => Color.alphaBlend(c, bg);

const _aaText = 4.5;
const _aaMark = 3.0;

T _resolve<T>(WidgetStateProperty<T?>? prop, Set<WidgetState> states) {
  expect(prop, isNotNull);
  final value = prop!.resolve(states);
  expect(value, isNotNull);
  return value!;
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    final s = theme.colorScheme;
    final bar = theme.navigationBarTheme;
    final barBg = bar.backgroundColor!;
    final pill = _over(bar.indicatorColor!, barBg);

    group('$name navigation bar', () {
      test('the selected icon clears 3:1 on the indicator it sits inside', () {
        final icon =
            _resolve(bar.iconTheme, const {WidgetState.selected}).color!;
        expect(_contrast(icon, pill), greaterThanOrEqualTo(_aaMark),
            reason: 'the selected icon is drawn on the indicator, not the bar');
        expect(_contrast(icon, barBg), greaterThanOrEqualTo(_aaMark),
            reason: 'and on the bar, for the frame in which the indicator is '
                'still growing into place');
      });

      test('the unselected icon clears 3:1 on the bar', () {
        final icon = _resolve(bar.iconTheme, const <WidgetState>{}).color!;
        expect(_contrast(_over(icon, barBg), barBg),
            greaterThanOrEqualTo(_aaMark));
      });

      test('both labels clear AA on the bar', () {
        for (final states in [
          const {WidgetState.selected},
          const <WidgetState>{},
        ]) {
          final label = _resolve(bar.labelTextStyle, states).color!;
          expect(_contrast(_over(label, barBg), barBg),
              greaterThanOrEqualTo(_aaText),
              reason: 'the label sits below the indicator, on the bar itself');
        }
      });
    });

    group('$name floating action button', () {
      test('the glyph clears 3:1 on the fill', () {
        final fab = theme.floatingActionButtonTheme;
        expect(_contrast(fab.foregroundColor!, fab.backgroundColor!),
            greaterThanOrEqualTo(_aaMark));
      });
    });

    group('$name primary container is the coral family', () {
      // Hue angle in degrees. A container seeded from the brand violet put
      // the run screen's coral lap flag on a purple disc (issue #1300) while
      // every contrast figure passed, so the hue is what this pins.
      double hue(Color c) => HSLColor.fromColor(c).hue;
      double gap(double a, double b) {
        final d = (a - b).abs() % 360;
        return d > 180 ? 360 - d : d;
      }

      test('container and its ink share the accent hue', () {
        expect(gap(hue(s.primaryContainer), hue(s.primary)), lessThan(10),
            reason: '$name primaryContainer is not a coral');
        expect(gap(hue(s.onPrimaryContainer), hue(s.primary)), lessThan(10),
            reason: '$name onPrimaryContainer is not a coral');
      });

      test('the lap flag, drawn in onPrimaryContainer, clears AA', () {
        expect(_contrast(s.onPrimaryContainer, s.primaryContainer),
            greaterThanOrEqualTo(_aaText),
            reason: 'onPrimaryContainer is also the text token on it');
      });

      test('primary stays a 3:1 mark on the container, never its text', () {
        // The route, activity, goal and onboarding glyphs draw primary on the
        // container; the superset chip, the challenge rank and both next-event
        // eyebrows drew it as type and took onPrimaryContainer instead.
        expect(_contrast(s.primary, s.primaryContainer),
            greaterThanOrEqualTo(_aaMark));
        expect(_contrast(s.primary, s.primaryContainer), lessThan(_aaText));
      });

      test('the next-event cards fade from the container to '
          'surfaceContainerHighest, and both ends carry their marks', () {
        for (final bg in [s.primaryContainer, s.surfaceContainerHighest]) {
          expect(_contrast(s.onPrimaryContainer, bg),
              greaterThanOrEqualTo(_aaText),
              reason: 'the eyebrow');
          expect(_contrast(s.onSurfaceVariant, bg),
              greaterThanOrEqualTo(_aaMark),
              reason: 'the date and place glyphs');
        }
        if (name == 'dark') {
          // 2.960:1 — the outline glyphs these replaced, at the container end.
          expect(_contrast(s.outline, s.primaryContainer), lessThan(_aaMark));
        }
      });

      test('the challenge standing card carries muted type on the container',
          () {
        expect(_contrast(s.onSurfaceVariant, s.primaryContainer),
            greaterThanOrEqualTo(_aaText));
        if (name == 'dark') {
          // 4.484:1 — hintColor is a 60% white, not a measured token, and it
          // fell under AA when the container moved from violet to coral.
          expect(
              _contrast(_over(theme.hintColor, s.primaryContainer),
                  s.primaryContainer),
              lessThan(_aaText));
        }
      });
    });

    group('$name secondary is a foreground token', () {
      test('it clears 3:1 as a mark on every surface it can land on', () {
        for (final (label, bg) in [
          ('surface', s.surface),
          ('scaffold', theme.scaffoldBackgroundColor),
          ('surfaceContainerLowest', s.surfaceContainerLowest),
          ('surfaceContainerLow', s.surfaceContainerLow),
          ('surfaceContainer', s.surfaceContainer),
          ('surfaceContainerHigh', s.surfaceContainerHigh),
          ('surfaceContainerHighest', s.surfaceContainerHighest),
          ('primaryContainer', s.primaryContainer),
          ('secondaryContainer', s.secondaryContainer),
          ('tertiaryContainer', s.tertiaryContainer),
        ]) {
          expect(_contrast(s.secondary, bg), greaterThanOrEqualTo(_aaMark),
              reason: '$name secondary on $label — the mobile tree paints it '
                  'only as an icon, so 1.4.11 applies at every one of them');
        }
      });

      test('the onSecondary pairing clears AA', () {
        expect(_contrast(s.onSecondary, s.secondary),
            greaterThanOrEqualTo(_aaText));
      });
    });

    group('$name error is a text token', () {
      final semantic = theme.extension<AppSemanticColors>()!;
      final surfaces = [
        ('surface', s.surface),
        ('scaffold', theme.scaffoldBackgroundColor),
        ('card', theme.cardTheme.color!),
        ('sheet', theme.bottomSheetTheme.modalBackgroundColor!),
        ('surfaceContainerLowest', s.surfaceContainerLowest),
        ('surfaceContainerLow', s.surfaceContainerLow),
        ('surfaceContainer', s.surfaceContainer),
        ('surfaceContainerHigh', s.surfaceContainerHigh),
        ('raised', name == 'light' ? AppTheme.snowDim : AppTheme.nightHigh),
      ];

      test('it clears AA as text on every surface an errorText lands on', () {
        for (final (label, bg) in surfaces) {
          expect(_contrast(s.error, bg), greaterThanOrEqualTo(_aaText),
              reason: '$name colorScheme.error on $label is '
                  '${_contrast(s.error, bg).toStringAsFixed(2)}:1');
        }
      });

      test('onError clears AA on the error fill', () {
        expect(_contrast(s.onError, s.error), greaterThanOrEqualTo(_aaText));
      });

      test('it is the semantic danger pair, so the two cannot drift', () {
        expect(s.error, semantic.danger);
        expect(s.onError, semantic.onDanger);
      });

      test('the coral it replaced failed AA on the card', () {
        expect(_contrast(const Color(0xFFD8594C), theme.cardTheme.color!),
            lessThan(_aaText));
      });
    });
  }

  group('the light theme has one coral, used as fill and as mark', () {
    test('white type on coralDeep clears AA (buttons, FAB, selected chip)', () {
      expect(_contrast(Colors.white, AppTheme.coralDeep),
          greaterThanOrEqualTo(_aaText));
    });

    test('coralDeep clears AA as a mark on the card and the scaffold', () {
      for (final bg in [Colors.white, AppTheme.snow]) {
        expect(_contrast(AppTheme.coralDeep, bg),
            greaterThanOrEqualTo(_aaText));
      }
    });

    test('coralDeep clears 3:1 on every light container and its own pill', () {
      final s = AppTheme.light.colorScheme;
      final pill = _over(AppTheme.coralDeep.withOpacity(0.18), AppTheme.snow);
      for (final bg in [
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
        s.surfaceContainerHighest,
        s.primaryContainer,
        s.secondaryContainer,
        s.tertiaryContainer,
        AppTheme.snowDim,
        pill,
      ]) {
        expect(_contrast(AppTheme.coralDeep, bg), greaterThanOrEqualTo(3));
      }
    });

    test('coralDeep is the light primary and FAB; violet the secondary', () {
      final light = AppTheme.light;
      expect(light.colorScheme.primary, AppTheme.coralDeep);
      expect(light.colorScheme.primaryContainer, AppTheme.coralTint);
      expect(light.colorScheme.onPrimaryContainer, AppTheme.coralInk);
      expect(AppTheme.dark.colorScheme.primaryContainer, AppTheme.coralInk);
      expect(AppTheme.dark.colorScheme.onPrimaryContainer, AppTheme.coralTint);
      expect(light.colorScheme.secondary, AppTheme.violet);
      expect(light.floatingActionButtonTheme.backgroundColor,
          AppTheme.coralDeep);
      expect(light.navigationBarTheme.indicatorColor,
          AppTheme.coralDeep.withOpacity(0.18));
    });
  });
}
