import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../parkrun_barcode.dart';

/// [number] as a Code 128 barcode with the number printed under it. Always
/// black on white, whatever the app theme: a finish-funnel scanner needs the
/// contrast, and an inverted code is not one every reader decodes.
class ParkrunBarcodeView extends StatelessWidget {
  const ParkrunBarcodeView({super.key, required this.number, this.barHeight = 120});

  /// A canonical athlete number ([normalizeParkrunAthleteNumber]'s output).
  final String number;
  final double barHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modules = code128BModules(number);
    final text = Theme.of(context).textTheme.headlineSmall;
    return Semantics(
      label: l10n.parkrunBarcodeSemantics(number),
      image: true,
      excludeSemantics: true,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: barHeight,
                width: double.infinity,
                child: CustomPaint(
                  key: const ValueKey('parkrun-barcode-bars'),
                  painter: ParkrunBarcodePainter(modules),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                number,
                style: text?.copyWith(
                  color: Colors.black,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints [modules] across the available width with a quiet zone either side,
/// snapping each bar to whole logical pixels per module where the width allows
/// so no bar is drawn narrower than its neighbours by rounding.
class ParkrunBarcodePainter extends CustomPainter {
  ParkrunBarcodePainter(this.modules) : bars = barcodeBars(modules);

  final String modules;
  final List<BarcodeBar> bars;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final total = modules.length + 2 * kCode128QuietZoneModules;
    final exact = size.width / total;
    final module = exact >= 1 ? exact.floorToDouble() : exact;
    // Centring an odd leftover would put every bar edge on a half pixel,
    // and antialiasing then greys a pixel either side of each bar.
    final margin = (size.width - module * modules.length) / 2;
    final left = exact >= 1 ? margin.floorToDouble() : margin;
    final ink = Paint()..color = Colors.black;
    for (final bar in bars) {
      canvas.drawRect(
        Rect.fromLTWH(left + bar.start * module, 0, bar.width * module, size.height),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(ParkrunBarcodePainter oldDelegate) =>
      oldDelegate.modules != modules;
}
