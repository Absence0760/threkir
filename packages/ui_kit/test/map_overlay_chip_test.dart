import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  testWidgets('a long label wraps inside its bound rather than overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const label = 'Chargement de la trace GPS en cours, veuillez patienter';
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Stack(children: [
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: MapOverlayChip(
                  label: label,
                  leading: Icon(Icons.cloud_off, size: 14),
                ),
              ),
            ),
          ]),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(MapOverlayChip)).width,
        lessThanOrEqualTo(296));
    expect(find.text(label), findsOneWidget);
  });
}
