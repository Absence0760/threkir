import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/dashboard_layout.dart';
import '../../lib/l10n/gen/app_localizations.dart';
import '../../lib/main.dart';
import '../../lib/screens/coach_screen.dart';
import '../../lib/screens/home_screen.dart';
import '../../lib/screens/plan_detail_screen.dart';
import '../../lib/screens/run_detail_screen.dart';
import '../../lib/screens/today_screen.dart';
import '../../lib/widgets/live_run_map.dart';
import 'demo_data.dart';

/// Every place the store capture touches the app's layout, kept in one file so
/// a navigation change is one edit here rather than a hunt through the suite.
///
/// The hero screens are pushed with the same constructors and services the
/// app's own taps use, read off the mounted [RunApp], rather than reached by
/// tapping through the shell: a renamed screen or a changed constructor is
/// then a compile error in `dart analyze`, where a moved tile would be a
/// runtime miss that only the emulator run finds. Only the shell and Today's
/// own cards are matched at runtime, by widget type, state and key, and the
/// map-match pill by the device locale's own catalogue, so every locale finds
/// them.
abstract final class StoreSelectors {
  /// The signed-in shell is up.
  static final Finder shell = find.byType(HomeScreen);

  /// Today has drawn the plan's session for today: the hero in its plan-day
  /// state (before the plan loads it reads "nothing planned"), and the
  /// progress card that closes the page.
  static final List<Finder> todayReady = [
    find.byWidgetPredicate((w) =>
        w is TodayHero &&
        w.key == const Key('dashboardTodayHero') &&
        w.state == TodayHeroState.planToday),
    find.byKey(const Key('todayProgressSummary')),
  ];

  /// A "missed session" prompt on Today. The plan loads before the device's
  /// runs reach the server and the server links each to its session, so one
  /// shows for yesterday's run until the plan re-reads after the push.
  static final Finder todayMissedPrompt = find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> &&
        key.value.startsWith('dashboardMissedPrompt-');
  });

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

  /// The run map's match-status pill, in any of its states (snapping,
  /// offline, skipped, failed). The settled, matched run shows none.
  static Finder matchPill(AppLocalizations l10n) => find.byWidgetPredicate(
        (w) =>
            w is Text &&
            {
              l10n.runDetailMatchPending,
              l10n.runDetailMatchOffline,
              l10n.runDetailMatchSkipped,
              l10n.runDetailMatchFailed,
            }.contains(w.data),
      );

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
  /// The phrase is the thread's last question, below the fold until the
  /// Coach has scrolled the thread to its latest exchange, so an on-screen
  /// match also proves that scroll landed: the panel shows the answer, not
  /// the start of the conversation.
  static final Finder coachReady =
      find.textContaining(kDemoCoachPhrase, findRichText: true);
}
