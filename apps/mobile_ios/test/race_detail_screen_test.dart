import 'package:api_client/api_client.dart' show UltraSignUpPersonLink;
import 'package:core_models/core_models.dart'
    show RouteMarkerRow, TrainingPlanRow, Waypoint;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/race_service.dart';
import '../lib/screens/course_drive_screen.dart';
import '../lib/screens/race_detail_screen.dart';
import '../lib/training.dart' show toIsoDate;
import '../lib/training_service.dart';
import '../lib/widgets/undo_bar.dart';

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
  bool signedIn = false;
  List<OrganiserClub> clubs = const [];
  List<CourseRouteOption> clubRoutes = const [];
  List<CourseRouteOption> myRoutes = const [];
  String? mySuggestionRouteId;
  final List<List<String?>> claims = [];
  final List<List<String?>> links = [];
  final List<List<String?>> suggestions = [];
  List<RaceCourseSuggestion> forReview = const [];
  final List<List<Object?>> reviews = [];

  List<CourseAlertView> alerts = const [];
  final List<List<String?>> postedAlerts = [];
  final List<String> deletedAlerts = [];

  _FakeRaceService({this.listing, this.listingFailures = 0});

  @override
  bool get isSignedIn => signedIn;

  @override
  bool get isReady => true;

  @override
  Future<List<CourseAlertView>> fetchCourseAlerts(
          {String? listingId, String? routeId, int limit = 20}) async =>
      alerts;

  @override
  Future<void> postCourseAlert(
      {String? listingId,
      String? routeId,
      required String kind,
      required String message}) async {
    postedAlerts.add([listingId, routeId, kind, message]);
    alerts = [
      CourseAlertView(
        id: 'alert-${postedAlerts.length}',
        clubId: 'club-1',
        listingId: listingId,
        routeId: routeId,
        kind: kind,
        message: message.trim(),
        createdAt: '2036-10-02T09:00:00Z',
      ),
      ...alerts,
    ];
  }

  @override
  Future<void> deleteCourseAlert(String alertId) async {
    deletedAlerts.add(alertId);
  }

  @override
  Future<List<OrganiserClub>> fetchMyOrganiserClubs() async => clubs;

  @override
  Future<List<CourseRouteOption>> fetchClubPublicRoutes(String clubId) async =>
      clubRoutes;

  @override
  Future<List<CourseRouteOption>> fetchMyPublicRoutes() async => myRoutes;

  @override
  Future<String?> fetchMyRaceCourseSuggestionRouteId(String listingId) async =>
      mySuggestionRouteId;

  @override
  Future<void> claimRaceListing(String listingId, String clubId) async {
    claims.add([listingId, clubId]);
    listing = _copyWith(listing!, organiserClubId: clubId, organiserClubName: 'Moab Trail Club');
  }

  @override
  Future<void> linkRaceCourse(String listingId, String? routeId, String? source) async {
    links.add([listingId, routeId, source]);
  }

  @override
  Future<void> suggestRaceCourse(String listingId, String routeId, String? note) async {
    suggestions.add([listingId, routeId, note]);
  }

  @override
  Future<List<RaceCourseSuggestion>> fetchRaceCourseSuggestionsForReview(
          String listingId) async =>
      forReview;

  @override
  Future<void> reviewRaceCourseSuggestion(String suggestionId, bool approve,
      {String? routeId, String source = 'official'}) async {
    reviews.add([suggestionId, approve, routeId, source]);
    forReview = forReview.where((s) => s.id != suggestionId).toList();
  }

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

  String? driveRouteId;

  @override
  Future<({List<Waypoint> line, List<RouteMarkerRow> markers})>
      fetchCourseForDrive(String routeId) async {
    driveRouteId = routeId;
    return (
      line: const [
        Waypoint(lat: 37.5, lng: -77.45),
        Waypoint(lat: 37.52, lng: -77.45),
      ],
      markers: const <RouteMarkerRow>[],
    );
  }

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

RaceListingView _copyWith(RaceListingView r,
        {String? organiserClubId, String? organiserClubName}) =>
    RaceListingView(
      id: r.id,
      provider: r.provider,
      providerRaceId: r.providerRaceId,
      name: r.name,
      raceDate: r.raceDate,
      distanceM: r.distanceM,
      locationLabel: r.locationLabel,
      entryUrl: r.entryUrl,
      resultsUrl: r.resultsUrl,
      isVerified: r.isVerified,
      distanceMAway: r.distanceMAway,
      course: r.course,
      organiserClubId: organiserClubId,
      organiserClubName: organiserClubName,
      // Only a verified club can claim, so a claimed listing starts official.
      organiserIsOfficial: organiserClubId != null,
    );

String _isoDaysOut(int days) => toIsoDate(DateTime.now().add(Duration(days: days)));

RaceListingView _listing({
  String provider = 'manual',
  required String raceDate,
  String? entryUrl,
  RaceListingCourse? course,
  String? organiserClubId,
  String? organiserClubName,
  bool? organiserIsOfficial,
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
      organiserClubId: organiserClubId,
      organiserClubName: organiserClubName,
      organiserIsOfficial: organiserIsOfficial ?? organiserClubId != null,
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

  group('Drive this course', () {
    tearDown(() => dotenv.loadFromString(envString: '', isOptional: true));

    RaceListingView onCourse() => _listing(
          raceDate: _isoDaysOut(60),
          course: const RaceListingCourse(
              distanceM: 42195,
              ascentM: 180,
              surface: 'road',
              routeId: '22222222-2222-4222-8222-222222222222'),
        );

    testWidgets('with the flag on, a public course opens the drive screen on its route',
        (tester) async {
      dotenv.loadFromString(envString: 'COURSE_DRIVE_ENABLED=true');
      final service = _FakeRaceService(listing: onCourse());
      await tester.pumpWidget(_app(service));
      await tester.pump();
      await tester.pump();

      final open = find.byKey(const Key('race-detail-drive-course'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(CourseDriveScreen), findsOneWidget);
      expect(service.driveRouteId, '22222222-2222-4222-8222-222222222222');
    });

    testWidgets('with the flag off nothing is offered', (tester) async {
      dotenv.loadFromString(envString: '', isOptional: true);
      await tester.pumpWidget(_app(_FakeRaceService(listing: onCourse())));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('race-detail-course')), findsOneWidget);
      expect(find.byKey(const Key('race-detail-drive-course')), findsNothing);
    });

    testWidgets('a course with no public route offers nothing', (tester) async {
      dotenv.loadFromString(envString: 'COURSE_DRIVE_ENABLED=true');
      await tester.pumpWidget(_app(_FakeRaceService(
        listing: _listing(
          raceDate: _isoDaysOut(60),
          course: const RaceListingCourse(distanceM: 42195),
        ),
      )));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('race-detail-course')), findsOneWidget);
      expect(find.byKey(const Key('race-detail-drive-course')), findsNothing);
    });
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

  testWidgets('a hand-added race a club claimed is credited to the club',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
      ),
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Added by Moab Trail Club'), findsOneWidget);
    expect(find.text('Added by a runner'), findsNothing);
    expect(find.byKey(const Key('race-course-tools')), findsNothing,
        reason: 'a signed-out reader is offered no course tools');
  });

  testWidgets('the course says where it came from, when it was checked and that it changed',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        provider: 'runsignup',
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
        course: const RaceListingCourse(
          distanceM: 42195,
          routeId: 'route-1',
          source: 'traced',
          checkedAt: '2036-10-01T10:00:00Z',
          updatedAt: '2036-10-20T10:00:00Z',
        ),
      ),
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(
      find.text("Course drawn by Moab Trail Club from the race's published map"
          ' · last checked 2036-10-01'),
      findsOneWidget,
    );
    expect(find.text('Course updated 2036-10-20'), findsOneWidget);
    expect(find.text('Listed on RunSignUp'), findsOneWidget);
  });

  testWidgets('the race and its course carry their provenance badges',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
        course: const RaceListingCourse(
          distanceM: 42195,
          routeId: 'route-1',
          source: 'traced',
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('race-detail-provenance')),
        matching: find.byKey(const Key('provenance-badge-official')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('race-detail-course-provenance')),
        matching: find.byKey(const Key('provenance-badge-traced')),
      ),
      findsOneWidget,
    );
    expect(find.text('Traced'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byKey(const Key('provenance-badge-traced')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(
      find.bySemanticsLabel(RegExp(
          r"Traced: drawn by a verified club from the race's published map")),
      findsOneWidget,
      reason: 'a screen reader hears what the mark means, not an icon name',
    );
    semantics.dispose();
  });

  testWidgets('a revoked organiser vouches for nothing: community, no source line',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
        organiserIsOfficial: false,
        course: const RaceListingCourse(
          distanceM: 42195,
          routeId: 'route-1',
          source: 'official',
        ),
      ),
    );
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('provenance-badge-official')), findsNothing);
    expect(find.byKey(const Key('provenance-badge-community')), findsNWidgets(2));
    expect(find.byKey(const Key('race-detail-course-source')), findsNothing);
  });

  testWidgets('anyone reads the organiser course alerts; only its admin gets the form',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
      ),
    )..alerts = const [
        CourseAlertView(
          id: 'alert-0',
          clubId: 'club-1',
          listingId: '11111111-1111-4111-8111-111111111111',
          routeId: null,
          kind: 'closure',
          message: 'The river path is closed.',
          createdAt: '2036-10-01T09:00:00Z',
        ),
      ];
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.text('Course alerts'), findsOneWidget);
    expect(find.text('Closure'), findsOneWidget);
    expect(find.textContaining('The river path is closed.'), findsOneWidget);
    expect(find.byKey(const Key('course-alert-post')), findsNothing);
    expect(find.byKey(const Key('course-alert-remove-alert-0')), findsNothing);
  });

  testWidgets('the organiser posts a course alert and removal is held for undo',
      (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
      ),
    )
      ..signedIn = true
      ..clubs = const [OrganiserClub(id: 'club-1', name: 'Moab Trail Club')];
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    await tester.scrollUntilVisible(
        find.byKey(const Key('course-alert-message')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('course-alerts-empty')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('course-alert-message')), ' Mile 12 turns left. ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('course-alert-post')));
    await tester.pump();
    await tester.pump();

    expect(service.postedAlerts, [
      ['11111111-1111-4111-8111-111111111111', null, 'notice', 'Mile 12 turns left.']
    ]);
    expect(find.textContaining('Mile 12 turns left.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('course-alert-remove-alert-1')));
    await tester.pump();
    expect(find.textContaining('Mile 12 turns left.'), findsNothing);
    expect(service.deletedAlerts, isEmpty,
        reason: 'the delete waits out the undo window');
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(service.deletedAlerts, ['alert-1']);
    debugResetUndo();
  });

  testWidgets('a verified club admin claims an unclaimed race', (tester) async {
    final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(30)))
      ..signedIn = true
      ..clubs = const [OrganiserClub(id: 'club-1', name: 'Moab Trail Club')];
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('race-course-claim')));
    await tester.pumpAndSettle();
    expect(find.text('Claim this race for your club'), findsOneWidget);
    await tester.tap(find.byKey(const Key('race-course-claim-confirm')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(service.claims, [
      ['11111111-1111-4111-8111-111111111111', 'club-1'],
    ]);
    expect(find.text('Race claimed.'), findsOneWidget);
    expect(find.text('Added by Moab Trail Club'), findsOneWidget,
        reason: 'the screen re-reads the listing after the claim');
    expect(find.byKey(const Key('race-course-claim')), findsNothing);
    expect(find.byKey(const Key('race-course-link')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the organiser club links a traced course', (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
      ),
    )
      ..signedIn = true
      ..clubs = const [OrganiserClub(id: 'club-1', name: 'Moab Trail Club')]
      ..clubRoutes = const [CourseRouteOption(id: 'route-1', name: 'Moab course')];
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-course-suggest')), findsNothing,
        reason: 'the organiser links, it does not suggest');
    await tester.tap(find.byKey(const Key('race-course-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('race-course-source-traced')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('race-course-link-confirm')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(service.links, [
      ['11111111-1111-4111-8111-111111111111', 'route-1', 'traced'],
    ]);
    expect(find.text('Course linked.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a runner suggests one of their public routes', (tester) async {
    final service = _FakeRaceService(
      listing: _listing(
        raceDate: _isoDaysOut(30),
        organiserClubId: 'club-1',
        organiserClubName: 'Moab Trail Club',
      ),
    )
      ..signedIn = true
      ..myRoutes = const [CourseRouteOption(id: 'mine-1', name: 'My trace')];
    await tester.pumpWidget(_app(service));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('race-course-link')), findsNothing);
    expect(find.byKey(const Key('race-course-claim')), findsNothing);
    await tester.tap(find.byKey(const Key('race-course-suggest')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('race-course-suggest-note')), 'From the 2036 map');
    await tester.tap(find.byKey(const Key('race-course-suggest-confirm')));
    await tester.pump();
    await tester.pump();

    expect(service.suggestions, [
      ['11111111-1111-4111-8111-111111111111', 'mine-1', 'From the 2036 map'],
    ]);
    expect(find.text('Suggestion sent.'), findsOneWidget);
    expect(find.byKey(const Key('race-course-suggest-pending')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  group('review and remove (decisions § 2381, § 2396)', () {
    tearDown(debugResetUndo);

    // The armed undo window owns a real Timer; drain it before the test ends.
    Future<void> drain(WidgetTester tester) =>
        tester.pump(const Duration(seconds: 9));

    _FakeRaceService organiser({RaceListingCourse? course}) => _FakeRaceService(
          listing: _listing(
            raceDate: _isoDaysOut(30),
            organiserClubId: 'club-1',
            organiserClubName: 'Moab Trail Club',
            course: course,
          ),
        )
          ..signedIn = true
          ..clubs = const [OrganiserClub(id: 'club-1', name: 'Moab Trail Club')]
          ..clubRoutes = const [
            CourseRouteOption(id: 'route-1', name: 'Moab course'),
            CourseRouteOption(id: 'route-2', name: 'Moab course (club copy)'),
          ];

    const linked = RaceListingCourse(
      distanceM: 42195,
      routeId: 'route-1',
      source: 'official',
      checkedAt: '2036-10-01T10:00:00Z',
    );

    testWidgets('removing the course is held for undo, and Undo keeps it',
        (tester) async {
      final service = organiser(course: linked);
      await tester.pumpWidget(_app(service));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Official course from Moab Trail Club'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('race-course-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('race-course-unlink')));
      await tester.pump();
      await tester.pump();

      expect(find.text('Course removed.'), findsOneWidget);
      expect(find.textContaining('Official course from Moab Trail Club'),
          findsNothing,
          reason: 'the course leaves the screen while the removal is held');
      expect(service.links, isEmpty,
          reason: 'nothing reaches the server while the offer stands');

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.textContaining('Official course from Moab Trail Club'),
          findsOneWidget);
      await drain(tester);
      expect(service.links, isEmpty);
    });

    testWidgets('a removal the undo window lets through unlinks the course',
        (tester) async {
      final service = organiser(course: linked);
      await tester.pumpWidget(_app(service));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('race-course-link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('race-course-unlink')));
      await tester.pump();
      await drain(tester);

      expect(service.links, [
        ['11111111-1111-4111-8111-111111111111', null, null],
      ]);
    });

    testWidgets('the organiser approves a suggestion with the club copy',
        (tester) async {
      final service = organiser()
        ..forReview = const [
          RaceCourseSuggestion(
            id: 'sug-1',
            routeId: 'runner-route',
            routeName: 'Runner trace',
            note: 'From the 2036 map',
          ),
        ];
      await tester.pumpWidget(_app(service));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Course suggestions'), findsOneWidget);
      expect(find.text('Runner trace'), findsOneWidget);
      expect(find.text('From the 2036 map'), findsOneWidget);
      expect(find.byKey(const Key('race-course-review-claim-first')), findsNothing);

      await tester.tap(find.byKey(const Key('race-course-approve')));
      await tester.pumpAndSettle();
      expect(find.text('Approve this course'), findsOneWidget);
      expect(find.byKey(const Key('race-course-unlink')), findsNothing,
          reason: 'approving never offers to remove the course');
      await tester.tap(find.byKey(const Key('race-course-link-confirm')));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(service.reviews, [
        ['sug-1', true, 'route-1', 'official'],
      ]);
      expect(find.text('Suggestion approved and course linked.'), findsOneWidget);
      expect(find.text('Runner trace'), findsNothing,
          reason: 'the queue is re-read after the review');
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('rejecting a suggestion is held for undo', (tester) async {
      final service = organiser()
        ..forReview = const [
          RaceCourseSuggestion(
              id: 'sug-1', routeId: 'runner-route', routeName: 'Runner trace'),
        ];
      await tester.pumpWidget(_app(service));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('race-course-reject')));
      await tester.pump();
      expect(find.text('Suggestion rejected.'), findsOneWidget);
      expect(find.text('Runner trace'), findsNothing);
      expect(service.reviews, isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.text('Runner trace'), findsOneWidget);

      await tester.tap(find.byKey(const Key('race-course-reject')));
      await tester.pump();
      await drain(tester);
      expect(service.reviews, [
        ['sug-1', false, null, 'official'],
      ]);
    });

    testWidgets('on an unclaimed race a verified admin is told to claim first',
        (tester) async {
      final service = _FakeRaceService(listing: _listing(raceDate: _isoDaysOut(30)))
        ..signedIn = true
        ..clubs = const [OrganiserClub(id: 'club-1', name: 'Moab Trail Club')]
        ..forReview = const [
          RaceCourseSuggestion(
              id: 'sug-1', routeId: 'runner-route', routeName: 'Runner trace'),
        ];
      await tester.pumpWidget(_app(service));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Runner trace'), findsOneWidget);
      expect(find.byKey(const Key('race-course-review-claim-first')), findsOneWidget);
      expect(find.byKey(const Key('race-course-approve')), findsNothing);
      expect(find.byKey(const Key('race-course-reject')), findsNothing);
      expect(find.byKey(const Key('race-course-claim')), findsOneWidget);
    });
  });

  test('raceCourseAccess matches web: claim, manage or suggest', () {
    const mine = [OrganiserClub(id: 'c1', name: 'A')];
    final unclaimed = raceCourseAccess(
        signedIn: true, organiserClubId: null, myOrganiserClubs: mine);
    expect([unclaimed.canClaim, unclaimed.canManage, unclaimed.canSuggest],
        [true, false, true]);
    final managed = raceCourseAccess(
        signedIn: true, organiserClubId: 'c1', myOrganiserClubs: mine);
    expect([managed.canClaim, managed.canManage, managed.canSuggest],
        [false, true, false]);
    final other = raceCourseAccess(
        signedIn: true, organiserClubId: 'c2', myOrganiserClubs: mine);
    expect([other.canClaim, other.canManage, other.canSuggest],
        [false, false, true]);
    final out = raceCourseAccess(
        signedIn: false, organiserClubId: null, myOrganiserClubs: mine);
    expect([out.canClaim, out.canManage, out.canSuggest], [false, false, false]);
  });

  test('raceShareUrl points at the public share page', () {
    expect(raceShareUrl('abc', webBase: 'https://threkir.com/'),
        'https://threkir.com/share/race/abc');
  });
}
