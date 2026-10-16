import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/plan_races.dart';
import '../lib/widgets/plan_races_list.dart';

final _races = planRaces(
  endDate: '2027-06-13',
  goalDistanceM: 91000,
  goalTimeSec: 39600,
  trimmedAt: null,
  workouts: const [
    PlanRaceWorkout(
      id: 'w-two-oceans',
      scheduledDate: '2027-04-04',
      kind: 'race',
      raceName: 'Two Oceans Ultra',
      racePriority: 'B',
      targetDistanceM: 56000,
      targetDurationSeconds: 23400,
    ),
  ],
);

Future<void> _pump(WidgetTester tester, String today,
    {ValueChanged<String>? onSelect, double textScale = 1}) {
  return tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: PlanRacesList(
        planName: 'Comrades block',
        planStartIso: '2027-01-04',
        races: _races,
        todayIso: today,
        onSelectWorkout: onSelect,
      ),
    ),
  ));
}

void main() {
  test('shows only when the plan has more than one race', () {
    expect(PlanRacesList.shows(_races), isTrue);
    expect(PlanRacesList.shows([_races.last]), isFalse);
  });

  testWidgets('lists each race with its priority, name, distance and goal',
      (tester) async {
    await _pump(tester, '2027-03-25');
    expect(find.text('Races in this plan'), findsOneWidget);
    expect(find.text('Two Oceans Ultra'), findsOneWidget);
    // The synthetic end-date race is named after the plan.
    expect(find.text('Comrades block'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.textContaining('56.0 km'), findsOneWidget);
    expect(find.textContaining('6:30:00'), findsOneWidget);
    expect(find.textContaining('91.0 km'), findsOneWidget);
    expect(find.textContaining('11:00:00'), findsOneWidget);
    // Each row merges into one node, so a screen reader hears the priority
    // spelled out ahead of the race it belongs to, never a bare letter.
    expect(find.bySemanticsLabel(RegExp(r'^Priority B\nTwo Oceans Ultra\n')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Priority A\nComrades block\n')),
        findsOneWidget);
  });

  testWidgets('the priority badge grows with the text scale', (tester) async {
    Size badge(String letter) => tester.getSize(find
        .ancestor(of: find.text(letter), matching: find.byType(Container))
        .first);
    final letter = find.text('B');

    await _pump(tester, '2027-03-25');
    expect(badge('B'), const Size(28, 28));

    await _pump(tester, '2027-03-25', textScale: 2);
    final scaled = badge('B');
    expect(scaled.width, greaterThanOrEqualTo(56));
    expect(scaled.height, greaterThanOrEqualTo(56));
    final glyph = tester.getSize(letter);
    expect(scaled.width, greaterThanOrEqualTo(glyph.width));
    expect(scaled.height, greaterThanOrEqualTo(glyph.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the next race carries the countdown', (tester) async {
    await _pump(tester, '2027-03-25');
    expect(
        tester
            .widget<Text>(find.byKey(const Key('planRacesNextCountdown')))
            .data,
        'Race in 10 days');
    await _pump(tester, '2027-04-05');
    expect(
        tester
            .widget<Text>(find.byKey(const Key('planRacesNextCountdown')))
            .data,
        'Race in 69 days');
  });

  testWidgets('tapping a race workout opens it; the plan race is inert',
      (tester) async {
    final opened = <String>[];
    await _pump(tester, '2027-03-25', onSelect: opened.add);
    await tester.tap(find.text('Two Oceans Ultra'));
    await tester.tap(find.text('Comrades block'));
    expect(opened, ['w-two-oceans']);
  });
}
