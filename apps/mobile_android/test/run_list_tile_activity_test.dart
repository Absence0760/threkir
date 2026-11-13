// ignore_for_file: avoid_relative_lib_imports
// The run row says its activity once, and never as a stored-looking word
// (issue #1374, Training → Runs: "Nov 13 · 33m 0s · run" under a card that
// drew the runner glyph twice).
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/activity_type_labels.dart';
import '../lib/widgets/run_list_tile.dart';
import 'worst_case_layout.dart';

Run _run({List<Waypoint> track = const []}) => Run(
      id: 'r1',
      startedAt: DateTime(2026, 11, 13, 7),
      duration: const Duration(minutes: 33),
      distanceMetres: 8000,
      source: RunSource.app,
      track: track,
      metadata: const {'activity_type': 'run'},
    );

Widget _tile(Run run) => Scaffold(
      body: ListView(children: [
        RunListTile.owned(
          run: run,
          unit: DistanceUnit.km,
          api: null,
          onTap: () {},
        ),
      ]),
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('with no track the avatar names the activity, and only it',
      (tester) async {
    await tester.pumpWidget(worstCaseApp(locale: const Locale('en'), home: _tile(_run())));
    expect(find.byIcon(ActivityType.run.icon), findsOneWidget,
        reason: 'one runner glyph on the card');
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byKey(const ValueKey('run-tile-activity-glyph')), findsNothing);
  });

  testWidgets('with a track drawn in the leading slot, the glyph beside the '
      'distance names it', (tester) async {
    await tester.pumpWidget(worstCaseApp(
      locale: const Locale('en'),
      home: _tile(_run(track: const [
        Waypoint(lat: 37.5, lng: -77.5),
        Waypoint(lat: 37.51, lng: -77.49),
        Waypoint(lat: 37.52, lng: -77.5),
      ])),
    ));
    expect(find.byIcon(ActivityType.run.icon), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNothing);
    expect(find.byKey(const ValueKey('run-tile-activity-glyph')), findsOneWidget);
  });

  testWidgets('the meta line carries no activity word; the row\'s label '
      'reads the localized activity', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(worstCaseApp(locale: const Locale('en'), home: _tile(_run())));
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    expect(texts.any((t) => RegExp(r'·\s*run\b').hasMatch(t)), isFalse,
        reason: 'no lowercased activity word on the meta line: $texts');
    expect(find.bySemanticsLabel(RegExp(r'\bRun\b')), findsOneWidget,
        reason: 'a screen reader still hears the activity');
    handle.dispose();
  });

  worstCaseTestWidgets('the run row', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(locale: locale, home: _tile(_run())));
    await tester.pump();
  });
}
