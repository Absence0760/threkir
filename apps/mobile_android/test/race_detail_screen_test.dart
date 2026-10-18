import 'package:api_client/api_client.dart' show UltraSignUpPersonLink;
import 'package:core_models/core_models.dart' show TrainingPlanRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/race_detail_screen.dart';
import '../lib/training.dart' show toIsoDate;
import '../lib/training_service.dart';

class _FakeTraining extends TrainingService {
  List<TrainingPlanRow> plans = const [];

  @override
  Future<List<TrainingPlanRow>> fetchMyPlans() async => plans;

  @override
  Future<PlanRunHistory?> fetchPlanRunHistory() async => null;
}

class _FakeRaceService extends RaceService {
  RaceListingView? listing;
  List<RaceListingRun> runs = const [];
  int listingFailures;
  int listingCalls = 0;
  int runsCalls = 0;
  String? lastImportProvider;

  _FakeRaceService({this.listing, this.listingFailures = 0});

  @override
  Future<RaceListingView?> fetchRaceListing(String id) async {
    listingCalls++;
    if (listingFailures > 0) {
      listingFailures--;
      throw Exception('network down');
    }
    return listing;
  }

  @override
  Future<List<RaceListingRun>> fetchMyRunsAtRace(String listingId) async {
    runsCalls++;
    return runs;
  }

  @override
  Future<bool> isProviderConfigured(String provider) async => false;

  @override
  Future<ImportRaceResultOutcome> importRaceResult({
    required String provider,
    required String listingId,
    String? bib,
    UltraSignUpPersonLink? ultraSignUpPerson,
    String? matchRunId,
    PastedRaceResult? result,
  }) async {
    lastImportProvider = provider;
    runs = [
      RaceListingRun(
        id: 'run-1',
        startedAt: '${toIsoDate(DateTime.now())}T08:00:00Z',
        distanceM: 10000,
        durationS: 2712,
        chipTime: result?.chipTime,
      ),
    ];
    return const ImportRaceResultOutcome(
        imported: 1, skipped: 0, enriched: 0, complete: true);
  }
}

String _isoDaysOut(int days) => toIsoDate(DateTime.now().add(Duration(days: days)));

RaceListingView _listing({
  String provider = 'manual',
  required String raceDate,
  String? entryUrl,
  RaceListingCourse? course,
}) =>
    RaceListingView(
      id: '11111111-1111-4111-8111-111111111111',
      provider: provider,
      providerRaceId: null,
      name: 'Moab Marathon',
      raceDate: raceDate,
      distanceM: 42195,
      locationLabel: 'Moab, UT, US',
      entryUrl: entryUrl,
      resultsUrl: null,
      isVerified: true,
      distanceMAway: null,
      course: course,
    );

Widget _app(RaceService service, {_FakeTraining? training, bool aiPlan = false}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RaceDetailScreen(
        service: service,
        listingId: '11111111-1111-4111-8111-111111111111',
        training: training ?? _FakeTraining(),
        loadAiPlanAvailable: () async => aiPlan,
      ),
    );

TrainingPlanRow _activePlan({required String name, required int endsInDays}) {
  final end = DateTime.now().add(Duration(days: endsInDays));
  return TrainingPlanRow(
    id: 'plan-before',
    userId: 'user-a',
    name: name,
    goalEvent: 'distance_10k',
    goalDistanceM: 10000,
    startDate: end.subtract(const Duration(days: 55)),
    endDate: end,
    daysPerWeek: 4,
    status: 'active',
    source: 'generated',
    rules: const [],
    isTemplate: false,
    isPublicTemplate: false,
  );
}

void main() {
  testWidgets('a future race offers the race page and says when the import opens',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        provider: 'runsignup',
        raceDate: _isoDaysOut(60),
        entryUrl: 'https://runsignup.com/Race/UT/Moab/X',
      ),
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Listed on RunSignUp'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Race page & register'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Share'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Import my result'), findsNothing);
    expect(find.textContaining('You can import your official result from race day'),
        findsOneWidget);
    expect(find.textContaining('No runs linked to this race yet'), findsOneWidget);
  });

  testWidgets('on race day a pasted result shows under your runs at this race',
      (tester) async {
    final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(0)));
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Added by a runner'), findsOneWidget);
    expect(find.textContaining('You can import your official result'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Import my result'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextField, 'Chip time')),
      '45:12',
    );
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, 'Import result'),
    ));
    await tester.pumpAndSettle();

    expect(service.lastImportProvider, 'paste');
    expect(service.runsCalls, 2, reason: 'the import reloads the linked runs');
    expect(find.textContaining('Chip time 45:12'), findsOneWidget);
    expect(find.textContaining('No runs linked to this race yet'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a listing on a public course shows the course summary',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(60),
        course: const RaceListingCourse(
            distanceM: 42195, ascentM: 180, surface: 'road'),
      ),
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    final course = find.byKey(const Key('race-detail-course'));
    expect(course, findsOneWidget);
    expect(find.descendant(of: course, matching: find.text('Course')),
        findsOneWidget);
    expect(
      find.descendant(
          of: course, matching: find.textContaining('180 m elevation gain')),
      findsOneWidget,
    );
    expect(find.descendant(of: course, matching: find.textContaining('Road')),
        findsOneWidget);
  });

  testWidgets('a listing with no visible course shows no course section',
      (tester) async {
    final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(60)));
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Moab Marathon'), findsWidgets);
    expect(find.byKey(const Key('race-detail-course')), findsNothing);
  });

  testWidgets('a listing that no longer exists reads as not found', (tester) async {
    final service = _FakeRaceService(listing: null);
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();
    expect(find.text("This race isn't in the calendar any more."), findsOneWidget);
    expect(service.runsCalls, 0);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final service = _FakeRaceService(
      listing: _listing(raceDate: _isoDaysOut(10)),
      listingFailures: 1,
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("Couldn't load this race"), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(service.listingCalls, 2);
    expect(find.text('Added by a runner'), findsOneWidget);
  });

  testWidgets('a future race offers one primary build action and no AI action while it is off',
      (tester) async {
    final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(120)));
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Build a plan for this race'), findsOneWidget);
    expect(find.byKey(const Key('race-detail-tailor-ai')), findsNothing);
    expect(find.byKey(const Key('race-detail-add-to-season')), findsNothing);
    expect(find.byKey(const Key('race-detail-season-hint')), findsNothing);
  });

  testWidgets('with the AI plan assistant live, "Tailor it with AI" sits beside it',
      (tester) async {
    final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(120)));
    await tester.pumpWidget(_app(service, aiPlan: true));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Build a plan for this race'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Tailor it with AI'), findsOneWidget);
  });

  testWidgets('an active plan ending before the race offers "Add to my season" first',
      (tester) async {
    final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(120)));
    final training = _FakeTraining()
      ..plans = [_activePlan(name: 'Autumn 10k', endsInDays: 30)];
    await tester.pumpWidget(_app(service, training: training));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FilledButton, 'Add to my season'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Build a plan for this race'), findsOneWidget);
    expect(find.textContaining('Starts after Autumn 10k ends on'), findsOneWidget);
    expect(find.textContaining('with 3 days to recover'), findsOneWidget);
  });

  test('raceShareUrl points at the public share page', () {
    expect(raceShareUrl('abc', webBase: 'https://threkir.com/'),
        'https://threkir.com/share/race/abc');
  });
}
