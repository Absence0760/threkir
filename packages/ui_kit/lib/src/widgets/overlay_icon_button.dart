import 'package:flutter/material.dart';

/// An icon button drawn over a photo or a map: a dark scrim disc around a
/// light glyph, with the full 48 dp tap target around it.
///
/// The run, route and club photo tiles each hand-built a
/// `Material(CircleBorder) > InkWell > SizedBox(30)`: a 30 dp target with
/// delete 4 dp from edit, invisible to the IconButton-only tap-target
/// guard (issue #1374 A11Y-6). This one is an `IconButton`, so it keeps the
/// tooltip, the button semantics and the 48 dp box; buttons placed side by
/// side need no gap, because the boxes themselves keep the discs
/// [kMinInteractiveDimension] - [discDiameter] apart.
///
/// The disc is [scrim] whatever the photo, so the glyph's contrast does not
/// depend on the picture: over a white photo the glyph is 8.59:1 and the
/// disabled glyph 4.30:1, where the old `black54` disc left the disabled
/// glyph at 2.51:1. A [selected] toggle fills the disc
/// with the scheme's primary under `onPrimary`.
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;

  /// Already localized; also the button's accessible name.
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  static const double discDiameter = 36;
  static const double glyphSize = 20;
  static const Color scrim = Color(0xB3000000);
  static const Color glyph = Colors.white;
  static const Color disabledGlyph = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: glyphSize,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primary : scrim,
        foregroundColor: selected ? scheme.onPrimary : glyph,
        disabledBackgroundColor: scrim,
        disabledForegroundColor: disabledGlyph,
        fixedSize: const Size.square(discDiameter),
        minimumSize: const Size.square(discDiameter),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
