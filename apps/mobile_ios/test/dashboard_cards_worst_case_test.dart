// ignore_for_file: avoid_relative_lib_imports
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/recent_5k_suggestion.dart';
import '../lib/training_load.dart';
import '../lib/walk_run_graduation.dart';
import '../lib/widgets/plan_discovery_card.dart';
import '../lib/widgets/race_predictor_card.dart';
import '../lib/widgets/readiness_card.dart';
import '../lib/widgets/walk_run_graduation_card.dart';
import 'worst_case_layout.dart';

/// The Today and Progress cards that only show with data the screens'
/// own worst-case walk does not seed, each on its own at 320 dp, 2x text
/// and the 3-button bar in every locale (issue #1374). They are ListCards,
/// so the inner padding is the component's; what is checked here is that
/// their content reflows inside it.
void main() {
  final now = DateTime(2026, 6, 10, 12);

  Future<void> pump(WidgetTester tester, Locale locale, Widget card) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [card],
        ),
      ),
    ));
    await tester.pump();
  }

  worstCaseTestWidgets('Train for something', (tester, locale) async {
    await pump(tester, locale, TrainForSomethingCard(onTap: () {}));
  });

  worstCaseTestWidgets('A recent 5K plan suggestion', (tester, locale) async {
    await pump(
      tester,
      locale,
      Recent5kPlanCard(
        suggestion: const Recent5kSuggestion(
          runId: 'r1',
          startedAt: '2026-06-03T07:00:00.000Z',
          seconds: 1450,
        ),
        onBuild: () {},
        onDismiss: () {},
      ),
    );
  });

  worstCaseTestWidgets('Readiness', (tester, locale) async {
    await pump(
      tester,
      locale,
      ReadinessCard(
        runs: const [],
        now: now,
        loadSeries: [
          TrainingLoadPoint(
            date: DateTime(2026, 6, 10),
            stress: 50,
            atl: 30,
            ctl: 50,
            tsb: 20,
          ),
        ],
      ),
    );
  });

  worstCaseTestWidgets('Race predictor', (tester, locale) async {
    await pump(
      tester,
      locale,
      RacePredictorCard(
        now: now,
        runs: [
          Run(
            id: 'r1',
            startedAt: now.subtract(const Duration(days: 5)),
            duration: const Duration(seconds: 1300),
            distanceMetres: 5000,
            source: RunSource.app,
          ),
        ],
      ),
    );
  });

  worstCaseTestWidgets('Walk-run graduation', (tester, locale) async {
    await pump(
      tester,
      locale,
      WalkRunGraduationCard(
        graduation: const WalkRunGraduation(
            workoutId: 'b', date: '2026-03-06', ranFiveK: true),
        onTrainForTenK: () {},
      ),
    );
  });
}
