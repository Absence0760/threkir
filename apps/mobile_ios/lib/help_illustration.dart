import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui_kit/ui_kit.dart';

/// The help-guide illustrations (docs/features/help.md § Illustrations).
///
/// Each is a text-free SVG authored once under
/// `apps/web/src/lib/help/illustrations/` and copied to
/// `assets/help/illustrations/<id>.svg` by `scripts/gen_help_guides.mjs`. A
/// file paints with only `currentColor` and one placeholder colour per theme
/// token; flutter_svg reads no CSS variables, so the placeholders are swapped
/// here for this theme's colours, the way web swaps them for CSS variables.
/// The palette must match `ILLUSTRATION_PALETTE` in
/// `apps/web/src/lib/help/illustration.ts`, which `help_illustration_test.dart`
/// checks against that file.
const Map<String, int> helpIllustrationPalette = {
  'accent': 0xff00a1,
  'accent-soft': 0xff00a2,
  'muted': 0xff00a3,
  'surface': 0xff00a4,
  'tint': 0xff00a5,
  'positive': 0xff00a6,
  'caution': 0xff00a7,
};

/// Every illustration is drawn on a 320 x 200 view box.
const double helpIllustrationAspectRatio = 320 / 200;

/// Token → colour for [theme], the same mapping web makes from its CSS tokens.
Map<String, Color> helpIllustrationColors(ThemeData theme) {
  final scheme = theme.colorScheme;
  final semantic = AppSemanticColors.ofTheme(theme);
  return {
    'accent': scheme.primary,
    'accent-soft': scheme.primaryContainer,
    'muted': scheme.outline,
    'surface': scheme.surface,
    'tint': scheme.surfaceContainerHighest,
    'positive': semantic.success,
    'caution': semantic.warning,
  };
}

/// Swaps each placeholder colour for its token's theme colour, keeping the
/// alpha the file gave it (a `fill-opacity` tint stays a tint).
class HelpIllustrationColorMapper extends ColorMapper {
  HelpIllustrationColorMapper(Map<String, Color> colors)
    : _byPlaceholder = {
        for (final e in helpIllustrationPalette.entries)
          if (colors[e.key] != null) e.value: colors[e.key]!,
      };

  final Map<int, Color> _byPlaceholder;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    final mapped = _byPlaceholder[color.toARGB32() & 0xffffff];
    if (mapped == null) return color;
    return mapped.withValues(alpha: mapped.a * color.a);
  }
}

/// One illustration block: the drawing, themed, announced by its [alt] text.
/// A missing or unreadable file renders nothing rather than an error — help is
/// an auxiliary surface.
class HelpIllustration extends StatelessWidget {
  const HelpIllustration({super.key, required this.id, required this.alt});

  final String id;
  final String alt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      key: ValueKey('help-illustration-$id'),
      container: true,
      image: true,
      label: alt,
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: AspectRatio(
              aspectRatio: helpIllustrationAspectRatio,
              child: SvgPicture.asset(
                'assets/help/illustrations/$id.svg',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                theme: SvgTheme(currentColor: scheme.onSurface),
                colorMapper: HelpIllustrationColorMapper(
                  helpIllustrationColors(theme),
                ),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
