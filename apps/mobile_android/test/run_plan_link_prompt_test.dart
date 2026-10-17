import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_service.dart' show PlanWorkoutLinkCandidate;
import '../lib/widgets/run_plan_link_prompt.dart';

// 2031-01-16 is a Thursday.
const _thursdayLong = PlanWorkoutLinkCandidate(
  workoutId: 'w-long',
  scheduledDate: '2031-01-16',
  kind: 'long',
  targetDistanceM: 16000,
  dayOffset: 1,
);
const _mondayEasy = PlanWorkoutLinkCandidate(
  workoutId: 'w-easy',
  scheduledDate: '2031-01-13',
  kind: 'easy',
  targetDistanceM: 8000,
  dayOffset: -2,
);

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<PlanWorkoutLinkCandidate>> Function() load,
  required Future<void> Function(String) link,
}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: RunPlanLinkPrompt(load: load, link: link)),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting());

  testWidgets('asks about the nearest workout, early, and yes links it',
      (tester) async {
    final linked = <String>[];
    await _pump(
      tester,
      load: () async => const [_thursdayLong, _mondayEasy],
      link: (id) async => linked.add(id),
    );

    expect(find.text("Did you do Thursday's planned workout early?"),
        findsOneWidget);
    expect(find.textContaining('Long run'), findsOneWidget);

    await tester.tap(find.text('Link to plan'));
    await tester.pump();
    expect(linked, ['w-long']);
    expect(find.byKey(const Key('plan-link-prompt')), findsNothing);
    expect(find.text('Linked to your plan.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('"Not this one" moves on to the next workout, links nothing',
      (tester) async {
    final linked = <String>[];
    await _pump(
      tester,
      load: () async => const [_thursdayLong, _mondayEasy],
      link: (id) async => linked.add(id),
    );

    await tester.tap(find.text('Not this one'));
    await tester.pump();
    expect(find.text("Did you do Monday's planned workout late?"),
        findsOneWidget);
    expect(find.textContaining('Easy'), findsOneWidget);

    await tester.tap(find.text('Not this one'));
    await tester.pump();
    expect(find.byKey(const Key('plan-link-prompt')), findsNothing);
    expect(linked, isEmpty);
  });

  testWidgets('a failed link says so and keeps the question', (tester) async {
    await _pump(
      tester,
      load: () async => const [_thursdayLong],
      link: (_) async => throw Exception('offline'),
    );

    await tester.tap(find.text('Link to plan'));
    await tester.pump();
    expect(find.text("Couldn't link this to your plan. Try again."),
        findsOneWidget);
    expect(find.byKey(const Key('plan-link-prompt')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a failed load shows nothing', (tester) async {
    await _pump(
      tester,
      load: () async => throw Exception('offline'),
      link: (_) async {},
    );
    expect(find.byKey(const Key('plan-link-prompt')), findsNothing);
  });
}
