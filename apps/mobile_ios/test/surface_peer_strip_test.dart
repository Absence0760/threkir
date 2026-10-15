import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/surface_peer_strip.dart';

/// The run surface's five peers, which no phone holds on one line: measured
/// in Manrope they need 480 dp in English and 538 in French. As a sideways
/// scroller the last one, Races, sat past the right edge with nothing saying
/// it was there (decisions § 1954). Asserted geometrically, so it holds under
/// the harness's fixed-advance font as well as the real one.
void main() {
  for (final locale in const [Locale('en'), Locale('fr'), Locale('es')]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('every peer is on screen at 360 dp ($locale, ${scale}x)',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Scaffold(
              body: SurfacePeerStrip(label: l10n.runSurfaceLabel, peers: [
                SurfacePeer(label: l10n.fitnessTabRuns),
                SurfacePeer(label: l10n.fitnessRunsRoutes, onTap: () {}),
                SurfacePeer(label: l10n.runSurfaceTabSegments, onTap: () {}),
                SurfacePeer(label: l10n.runSurfaceTabPlans, onTap: () {}),
                SurfacePeer(label: l10n.runSurfaceTabRaces, onTap: () {}),
              ]),
            );
          }),
        ));
        await tester.pumpAndSettle();
        final screen = Offset.zero & const Size(360, 800);
        final chips = find.byType(ChoiceChip);
        expect(chips, findsNWidgets(5));
        for (final element in chips.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(screen.intersect(rect), rect,
              reason: 'a peer chip ($rect) runs off a 360 dp screen');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('tapping a peer runs its action; the current peer has none',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SurfacePeerStrip(label: 'Run surfaces', peers: [
          const SurfacePeer(label: 'Runs'),
          SurfacePeer(label: 'Races', onTap: () => opened++),
        ]),
      ),
    ));
    await tester.tap(find.text('Runs'));
    await tester.tap(find.text('Races'));
    expect(opened, 1);
    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Runs')).selected,
      isTrue,
    );
  });
}
