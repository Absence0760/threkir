import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/date_format.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/plan_ramp.dart';
import '../lib/plan_request_client.dart';
import '../lib/plan_start.dart';
import '../lib/screens/plan_new_screen.dart';
import '../lib/social_service.dart';
import '../lib/training.dart';
import '../lib/training_service.dart';

final _en = AppLocalizationsEn();

class _QuietTraining extends TrainingService {
  @override
  Future<TrainingGender> fetchViewerGender() async => null;
  @override
  Future<int?> fetchViewerAge() async => null;
  @override
  Future<RecentVolume?> fetchRecentRunVolume() async => null;
  @override
  Future<List<TrainingPlanRow>> fetchClubTemplates(String clubId) async =>
      const [];
}

class _NoClubs extends SocialService {
  @override
  Future<List<ClubView>> fetchMyClubs() async => const [];
}

/// Answers each description from a queue and records what it was asked.
class _Assistant {
  final List<Object> answers;
  final requests = <String>[];
  _Assistant(this.answers);

  Future<PlanRequestInputs> call(String request, String todayIso) async {
    requests.add(request);
    final next = answers[requests.length - 1];
    if (next is PlanRequestInputs) return next;
    throw next;
  }
}

PlanRequestInputs _inputs({
  GoalEvent goalEvent = GoalEvent.distanceHalf,
  String? raceDate,
  int? goalTimeSec,
  int? recent5kSec,
  int daysPerWeek = 4,
  int? weeks,
  bool beginnerWalkRun = false,
  String? planName,
  List<PlanRequestAssumption> assumptions = const [],
}) =>
    PlanRequestInputs(
      goalEvent: goalEvent,
      raceDate: raceDate,
      goalTimeSec: goalTimeSec,
      recent5kSec: recent5kSec,
      daysPerWeek: daysPerWeek,
      weeks: weeks,
      beginnerWalkRun: beginnerWalkRun,
      planName: planName,
      assumptions: assumptions,
    );

Future<void> _pump(
  WidgetTester tester, {
  bool available = true,
  _Assistant? assistant,
  String? initialDescription,
}) async {
  tester.view.physicalSize = const Size(1000, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PlanNewScreen(
      training: _QuietTraining(),
      social: _NoClubs(),
      initialDescription: initialDescription,
      loadAiPlanAvailable: () async => available,
      requestPlanInputsFn: (assistant ?? _Assistant(const [])).call,
    ),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<void> _describe(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('plan-new-ai-field')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('plan-new-ai-fill')));
  await _settle(tester);
}

TextEditingController _fieldByHint(WidgetTester tester, String hint) =>
    tester
        .widget<TextField>(find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == hint))
        .controller!;

TextEditingController _nameField(WidgetTester tester) => tester
    .widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == _en.planNewNameLabel))
    .controller!;

TextEditingController _weeksField(WidgetTester tester) => tester
    .widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.hintText == _en.planNewOverrideHint))
    .controller!;

GoalEvent? _goal(WidgetTester tester) {
  final value = tester
      .widget<DropdownButtonFormField<String>>(find.byWidgetPredicate((w) =>
          w is DropdownButtonFormField<String> &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('plan-new-goal-')))
      .initialValue;
  return value == null ? null : goalEventFromDb(value);
}

int? _days(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>))
    .initialValue;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

void main() {
  testWidgets('the box is hidden when the deploy has no AI plan assistant',
      (tester) async {
    await _pump(tester, available: false);
    expect(find.byKey(const Key('plan-new-ai-card')), findsNothing);
    expect(find.text(_en.planNewAiTitle), findsNothing);
  });

  testWidgets('the box shows when the AI plan assistant is live',
      (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('plan-new-ai-card')), findsOneWidget);
    final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('plan-new-ai-fill')));
    expect(button.onPressed, isNull, reason: 'nothing typed yet');
  });

  testWidgets('a fill sets the form fields and explains itself',
      (tester) async {
    final assistant = _Assistant([
      _inputs(
        goalEvent: GoalEvent.distanceFull,
        goalTimeSec: 3 * 3600 + 45 * 60 + 30,
        recent5kSec: 26 * 60 + 30,
        daysPerWeek: 5,
        planName: 'Autumn marathon',
        assumptions: const [PlanRequestAssumption.weeksClamped],
      ),
    ]);
    await _pump(tester, assistant: assistant);
    await _describe(tester, 'A 3:45:30 marathon, 5 days a week');

    expect(assistant.requests, ['A 3:45:30 marathon, 5 days a week']);
    expect(_goal(tester), GoalEvent.distanceFull);
    expect(_days(tester), 5);
    expect(_fieldByHint(tester, 'h').text, '3');
    expect(_fieldByHint(tester, 'm').text, '45');
    expect(_fieldByHint(tester, 's').text, '30');
    expect(_fieldByHint(tester, 'min').text, '26');
    expect(_fieldByHint(tester, 'sec').text, '30');
    expect(_nameField(tester).text, 'Autumn marathon');

    // The recent 5K is filled but never confirmed for the runner.
    final confirm = tester.widget<CheckboxListTile>(find.widgetWithText(
        CheckboxListTile, _en.planNewRecent5kConfirm));
    expect(confirm.value, isFalse);

    expect(find.byKey(const Key('plan-new-ai-status')), findsOneWidget);
    expect(find.textContaining(_en.planNewAiAppliedTitle), findsOneWidget);
    expect(find.textContaining(_en.planNewAiAppliedGenerator), findsOneWidget);
    expect(find.textContaining(_en.planNewAiAppliedRecent5k), findsOneWidget);
    expect(find.textContaining(_en.planNewAiAssumptionWeeksClamped),
        findsOneWidget);
  });

  testWidgets('a beginner fill ticks the walk-run box', (tester) async {
    await _pump(tester,
        assistant: _Assistant([
          _inputs(
            goalEvent: GoalEvent.distance5k,
            beginnerWalkRun: true,
            daysPerWeek: 3,
            assumptions: const [PlanRequestAssumption.beginner5k],
          ),
        ]));
    await _describe(tester, 'I have never run');
    final beginner = tester.widget<CheckboxListTile>(find.widgetWithText(
        CheckboxListTile, _en.planNewBeginnerTitle));
    expect(beginner.value, isTrue);
    expect(_goal(tester), GoalEvent.distance5k);
    expect(find.textContaining(_en.planNewAiAssumptionBeginner5k),
        findsOneWidget);
  });

  testWidgets('the runner\'s own plan name beats the extracted one',
      (tester) async {
    await _pump(tester,
        assistant: _Assistant([_inputs(planName: 'From the AI')]));
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField && w.decoration?.labelText == _en.planNewNameLabel),
        'Mine');
    await tester.pump();
    await _describe(tester, 'a half');
    expect(_nameField(tester).text, 'Mine');
  });

  testWidgets(
      'a race date sizes the plan to end on race week, a shorter request '
      'starting later', (tester) async {
    final today = _day(DateTime.now());
    final race = DateTime(today.year, today.month, today.day + 140);
    final raceIso = toIsoDate(race);
    await _pump(tester,
        assistant: _Assistant([
          _inputs(raceDate: raceIso, weeks: 10, goalTimeSec: 7200),
          _inputs(),
        ]));
    await _describe(tester, 'A half on that date, 10 weeks');

    final raceWeekStart =
        DateTime(race.year, race.month, race.day - race.weekday % 7);
    final expectedStart = DateTime(raceWeekStart.year, raceWeekStart.month,
        raceWeekStart.day - 9 * 7);
    expect(find.text(toIsoDate(expectedStart)), findsOneWidget);
    expect(_weeksField(tester).text, '10');
    expect(
        find.textContaining(
            _en.planNewAiRaceApplied(formatDateMed(race, 'en'))),
        findsOneWidget);

    // A second description that names no race, length or goal time must not
    // inherit the first one's.
    await _describe(tester, 'Actually just a half, no race');
    final defaultStart = nextSunday(DateTime.now().add(const Duration(days: 7)));
    expect(find.text(toIsoDate(defaultStart)), findsOneWidget);
    expect(_weeksField(tester).text, isEmpty);
    expect(_fieldByHint(tester, 'h').text, isEmpty);
    expect(_fieldByHint(tester, 'm').text, isEmpty);
  });

  testWidgets('a past race date leaves the start date and says why',
      (tester) async {
    final today = _day(DateTime.now());
    final before = nextSunday(DateTime.now().add(const Duration(days: 7)));
    await _pump(tester,
        assistant: _Assistant([
          _inputs(
              raceDate: toIsoDate(
                  DateTime(today.year, today.month, today.day - 3))),
        ]));
    await _describe(tester, 'the race I already ran');
    expect(find.text(toIsoDate(before)), findsOneWidget);
    expect(find.textContaining(_en.planNewAiRacePast), findsOneWidget);
  });

  testWidgets('a consent refusal offers the disclosure, the form still works',
      (tester) async {
    await _pump(tester,
        assistant: _Assistant(
            [const PlanRequestError(PlanRequestErrorKind.consent)]));
    await _describe(tester, 'a half');
    expect(find.text(_en.planNewAiErrorConsent), findsOneWidget);
    expect(find.byKey(const Key('plan-new-ai-review-disclosure')),
        findsOneWidget);
    expect(find.byKey(const Key('plan-new-ai-status')), findsNothing);

    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField && w.decoration?.labelText == _en.planNewNameLabel),
        'By hand');
    await tester.pump();
    expect(_nameField(tester).text, 'By hand');
  });

  testWidgets('the daily limit and every other failure read as such',
      (tester) async {
    await _pump(tester,
        assistant: _Assistant([
          const PlanRequestError(PlanRequestErrorKind.dailyLimit),
          const PlanRequestError(PlanRequestErrorKind.notUnderstood),
          StateError('boom'),
        ]));
    await _describe(tester, 'one');
    expect(find.text(_en.planNewAiErrorDailyLimit), findsOneWidget);
    await _describe(tester, 'two');
    expect(find.text(_en.planNewAiErrorFallback), findsOneWidget);
    await _describe(tester, 'three');
    expect(find.text(_en.planNewAiErrorFallback), findsOneWidget);
    expect(find.byKey(const Key('plan-new-ai-review-disclosure')),
        findsNothing);
    expect(_goal(tester), GoalEvent.distanceHalf);
  });

  testWidgets('an initial description prefills the box and fills once',
      (tester) async {
    final assistant =
        _Assistant([_inputs(goalEvent: GoalEvent.distance10k)]);
    await _pump(tester,
        assistant: assistant, initialDescription: '  A 10K in spring  ');
    expect(assistant.requests, ['A 10K in spring']);
    expect(_goal(tester), GoalEvent.distance10k);
    expect(find.byKey(const Key('plan-new-ai-status')), findsOneWidget);
    await _settle(tester);
    expect(assistant.requests, hasLength(1));
  });

  testWidgets('an initial description does nothing when the box is off',
      (tester) async {
    final assistant = _Assistant([_inputs()]);
    await _pump(tester,
        available: false,
        assistant: assistant,
        initialDescription: 'A 10K in spring');
    expect(assistant.requests, isEmpty);
  });
}
