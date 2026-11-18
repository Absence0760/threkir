import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' show MarkdownBody;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show DetailHero;

import '../../lib/dashboard_layout.dart';
import '../../lib/main.dart';
import '../../lib/screens/coach_screen.dart';
import '../../lib/screens/home_screen.dart';
import '../../lib/screens/plan_detail_screen.dart';
import '../../lib/screens/progress_screen.dart';
import '../../lib/screens/run_detail_screen.dart';
import '../../lib/screens/today_screen.dart';
import '../../lib/widgets/current_week_strip.dart';
import '../../lib/widgets/live_run_map.dart';
import '../../lib/widgets/race_predictor_card.dart' show raceLadderSlug;
import 'demo_data.dart';

/// Every place the store capture touches the app's layout, kept in one file so
/// a navigation change is one edit here rather than a hunt through the suite.
///
/// The hero screens are pushed with the same constructors and services the
/// app's own taps use, read off the mounted [RunApp], rather than reached by
/// tapping through the shell: a renamed screen or a changed constructor is
/// then a compile error in `dart analyze`, where a moved tile would be a
/// runtime miss that only the emulator run finds. Only the shell, Today's
/// own cards and the sections the panels crop are matched at runtime, by
/// widget type, state and key, so every locale finds them.
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

  /// The run-detail captures: the hero run's detail page.
  static Widget runDetail(RunApp app, Run run) => RunDetailScreen(
        run: run,
        runStore: app.runStore,
        routeStore: app.routeStore,
        preferences: app.preferences,
        apiClient: app.apiClient,
        settingsSync: app.settingsSync,
      );
  static final Finder runDetailReady = find.byType(LiveRunMap);

  /// The plan capture: the seeded plan's detail page.
  static Widget planDetail(RunApp app) =>
      PlanDetailScreen(training: app.training, planId: kDemoPlanId);
  static final Finder planDetailReady = find.text(kDemoPlanName);

  /// The coach capture: the conversation seeded on the plan.
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

  // ---- Sections the panels crop (assets/store/README.md, bounds.json).
  // Each is a keyed widget in the app; a renamed key fails the capture with
  // the section's name rather than shipping a panel cropped from nowhere.

  /// Run detail: "Heart rate zones", from its title to the end of the legend.
  static final Finder hrZonesTitle =
      find.byKey(const Key('run-detail-hr-zones-title'));
  static final Finder hrZonesLegend =
      find.byKey(const Key('run-detail-hr-zones-legend'));
  static Finder hrZoneRow(int zone) =>
      find.byKey(ValueKey('run-detail-hr-zone-$zone'));

  /// Run detail: the Splits section.
  static final Finder splitsTitle =
      find.byKey(const Key('run-detail-splits-title'));
  static final Finder pacingCard =
      find.byKey(const Key('run-detail-pacing-card'));
  static final Finder gapHeader =
      find.byKey(const Key('run-detail-gap-header'));
  static Finder splitRow(int km) =>
      find.byKey(ValueKey('run-detail-split-row-$km'));
  static final Finder splitsHint =
      find.byKey(const Key('run-detail-splits-hint'));

  /// The Progress page, pushed as Today's "Progress" link pushes it.
  static Widget progress(RunApp app) => ProgressScreen(
        apiClient: app.apiClient,
        training: app.training,
        runStore: app.runStore,
        routeStore: app.routeStore,
        gymStore: app.gymStore,
        preferences: app.preferences,
        settingsSync: app.settingsSync,
      );
  static final Finder predictorCard =
      find.byKey(const Key('race-predictor-card'));
  static Finder predictorRow(double distanceM) =>
      find.byKey(ValueKey('race-predictor-row-${raceLadderSlug(distanceM)}'));

  /// Plan detail: the race title and the header card, the week grid, and
  /// the "Plan progress" disclosure.
  static final Finder planTitle = find.byType(DetailHero);
  static final Finder planHeroCard =
      find.byKey(const Key('planDetailHeroCard'));
  static final Finder planWeek = find.byType(CurrentWeekStrip);
  static final Finder planProgress =
      find.byKey(const ValueKey('plan-disclosure-progress'));

  /// Coach: the context chip row.
  static final Finder coachContext =
      find.byKey(const Key('coach-context-strip'));

  /// Coach: the seeded thread's last question, as its bubble.
  static final Finder coachLastQuestion = find
      .ancestor(
        of: find.textContaining(kDemoCoachPhrase, findRichText: true),
        matching: find.byType(Container),
      )
      .first;

  /// Coach: the answer bubble that closes the thread (the last one drawn).
  static final Finder coachLastAnswer = find
      .ancestor(of: find.byType(MarkdownBody).last, matching: find.byType(Container))
      .first;

  /// Never inside a coach crop: the usage line or upgrade banner, and the
  /// typing indicator (spec, demo data items 2 and 3).
  static final Map<String, Finder> coachForbidden = {
    'coach-limit-banner': find.byKey(const Key('coach-limit-banner')),
    'coach-typing': find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_Dot'),
  };
}
