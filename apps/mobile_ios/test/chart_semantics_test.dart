import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/training_load.dart';
import '../lib/widgets/elevation_chart.dart';
import '../lib/widgets/training_load_chart.dart';

/// #1374 A11Y-14: the elevation and training-load charts were paint with no
/// semantic value. Each is one node with a summary of what is drawn, and
/// the elevation chart's cursor can be stepped by a screen reader.
Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  await Preferences().init();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the elevation chart summarises the profile and steps its cursor',
      (tester) async {
    final handle = tester.ensureSemantics();
    // A climb from 100 m to 160 m and back to 120 m over about 2.2 km.
    final eles = [100.0, 120.0, 140.0, 160.0, 150.0, 130.0, 120.0];
    final track = [
      for (var i = 0; i < 25; i++)
        Waypoint(
          lat: 51.5 + i * 0.0008,
          lng: -0.12,
          elevationMetres: eles[(i * (eles.length - 1) / 24).round()],
        ),
    ];
    int? hovered;
    await _pump(
      tester,
      ElevationChart(
        track: track,
        theme: AppTheme.light,
        unit: DistanceUnit.km,
        onHoverIdx: (i) => hovered = i,
      ),
    );
    final node = find.byKey(const Key('elevationChartSemantics'));
    final data = tester.getSemantics(node).getSemanticsData();
    expect(data.label, startsWith('Elevation over '));
    expect(data.label, contains('lowest'));
    expect(data.label, contains('climbed'));
    expect(data.value, contains(' at '));
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isFalse,
        reason: 'the cursor starts at the start of the track');

    tester.semantics.increase(find.semantics.byLabel(RegExp('^Elevation over ')));
    await tester.pump();
    expect(hovered, isNotNull, reason: 'a step moves the linked map marker');
    final after = tester.getSemantics(node).getSemanticsData();
    expect(after.value, data.increasedValue);
    expect(after.hasAction(SemanticsAction.decrease), isTrue);
    handle.dispose();
  });

  testWidgets('the training-load chart says where each line went', (tester) async {
    final handle = tester.ensureSemantics();
    TrainingLoadPoint p(DateTime d, double ctl, double atl, double tsb) =>
        TrainingLoadPoint(date: d, stress: 0, atl: atl, ctl: ctl, tsb: tsb);
    await _pump(
      tester,
      TrainingLoadChart(
        hasHr: true,
        points: [
          p(DateTime(2026, 9, 1), 30.4, 40, -9.6),
          p(DateTime(2026, 10, 1), 42.6, 55.2, -12.4),
        ],
      ),
    );
    final label = tester
        .getSemantics(find.byKey(const Key('trainingLoadChartSemantics')))
        .getSemanticsData()
        .label;
    expect(label, startsWith('Fitness 30 to 43, fatigue 40 to 55, form -10 to -12, '));
    handle.dispose();
  });
}
