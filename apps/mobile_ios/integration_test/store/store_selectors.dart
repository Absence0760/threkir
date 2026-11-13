import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/main.dart';
import '../../lib/screens/coach_screen.dart';
import '../../lib/screens/home_screen.dart';
import '../../lib/screens/plan_detail_screen.dart';
import '../../lib/screens/run_detail_screen.dart';
import '../../lib/widgets/live_run_map.dart';
import 'demo_data.dart';

/// Every place the store capture touches the app's layout, kept in one file so
/// a navigation change is one edit here rather than a hunt through the suite.
///
/// The hero screens are pushed with the same constructors and services the
/// app's own taps use, read off the mounted [RunApp], rather than reached by
/// tapping through Home: a renamed screen or a changed constructor is then a
/// compile error in `dart analyze`, where a moved tile would be a runtime miss
/// that only the emulator run finds. Only the shell and Home's own cards are
/// matched at runtime, by widget type and by key, never by text, so every
/// device locale finds them.
abstract final class StoreSelectors {
  /// The signed-in shell is up.
  static final Finder shell = find.byType(HomeScreen);

  /// Home has drawn its plan-aware lead: the today hero and the week strip.
  static final List<Finder> homeReady = [
    find.byKey(const Key('dashboardTodayHero')),
    find.byKey(const Key('dashboardWeekLead')),
  ];

  /// The record panel: the hero run's detail page, map first.
  static Widget runDetail(RunApp app, Run run) => RunDetailScreen(
        run: run,
        runStore: app.runStore,
        routeStore: app.routeStore,
        preferences: app.preferences,
        apiClient: app.apiClient,
        settingsSync: app.settingsSync,
      );
  static final Finder runDetailReady = find.byType(LiveRunMap);

  /// The train panel: the seeded plan's detail page.
  static Widget planDetail(RunApp app) =>
      PlanDetailScreen(training: app.training, planId: kDemoPlanId);
  static final Finder planDetailReady = find.text(kDemoPlanName);

  /// The coach panel: the conversation seeded on the plan.
  static Widget coach(RunApp app) => CoachScreen(
        api: app.apiClient!,
        training: app.training,
        initialPlanId: kDemoPlanId,
      );
  static final Finder coachReady =
      find.textContaining(kDemoCoachPhrase, findRichText: true);
}
