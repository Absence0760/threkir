import 'package:api_client/api_client.dart' show ApiClient;
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show TextLane;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';
import '../lib/event_category.dart';
import '../lib/event_gym_template.dart';
import '../lib/gym_routine.dart' show PlannedExercise, PlannedRoutine, PlannedSet;
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/session_steps.dart';
import '../lib/social_service.dart';
import 'pump_until.dart';
import 'realtime_drain.dart';

ClubView _club(String? viewerRole) => ClubView(
  row: ClubRow(
    shadowHidden: false,
    id: 'club-1',
    slug: 'club-1',
    name: 'Club',
    description: null,
    locationLabel: null,
    isPublic: true,
    joinPolicy: 'open',
    ownerId: 'owner-1',
    createdAt: DateTime(2026, 1, 1),
    memberCount: 1,
    isVerified: false,
    requiresActivityWaiver: false,
  ),
  memberCount: 1,
  viewerRole: viewerRole,
  viewerStatus: viewerRole == null ? null : 'active',
  joinPolicy: 'open',
);

/// Renders one upcoming athletic event (so the RSVP row shows) and throws
/// on the RSVP write to drive the swallowed-failure banner.
class _RsvpFailSocial extends SocialService {
  int rsvpCalls = 0;

  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get currentUserId => 'u-viewer';
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => null;
  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
    row: EventRow(
      id: 'e1',
      clubId: 'club-1',
      title: 'Saturday Long Run',
      startsAt: DateTime.utc(2026, 6, 20, 8),
      authorId: 'host',
      category: 'run',
      isPublic: true,
    ),
    byday: null,
    attendeeCount: 0,
    viewerRsvp: null,
    nextInstanceStart: DateTime.utc(2026, 6, 20, 8),
  );
  @override
  Future<List<AttendeeView>> fetchAttendees(
    String eventId,
    DateTime instance,
  ) async => const [];
  @override
  Future<List<EventResultView>> fetchEventResults(
    String eventId,
    DateTime instance,
  ) async => const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(
    String eventId,
    DateTime instance,
  ) async => null;
  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(
    String eventId,
  ) async => null;
  @override
  Future<void> rsvpEvent(
    String eventId,
    String status,
    DateTime instance, {
    String? courseId,
  }) async {
    rsvpCalls++;
    throw Exception('network down');
  }

  @override
  Future<List<EventCourseView>> fetchEventCourses(String eventId) async =>
      const [];
}

/// Configurable fake that drives the happy paths: a club (role configurable),
/// an athletic event, a canned attendee list, and a recording RSVP write.
class _EventSocial extends SocialService {
  /// The screen gates on the viewer id, so a fake must declare who is
  /// looking rather than falling through to a real Supabase read.
  @override
  String? get currentUserId => 'u-viewer';

  _EventSocial({
    this.club,
    this.category = 'run',
    this.attendees = const [],
    this.viewerRsvp,
    this.cancelled = const {},
    this.paceTargetSec,
    this.courses = const [],
    this.raceStatus,
    this.dnfCount,
  });
  List<EventCourseView> courses;
  /// The occurrence's race session status, or null for none.
  String? raceStatus;
  /// What `race_pending_dnf_count` answers; null when it cannot be read.
  int? dnfCount;
  int dnfPreviewCalls = 0;
  String? lastRsvpCourseId;
  ClubView? club;
  String category;
  List<AttendeeView> attendees;
  String? viewerRsvp;
  Set<DateTime> cancelled;
  int? paceTargetSec;
  int rsvpCalls = 0;
  int clearCalls = 0;
  String? lastRsvpStatus;

  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => club;
  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
    row: EventRow(
      id: 'e1',
      clubId: 'club-1',
      title: 'Saturday Long Run',
      startsAt: DateTime.utc(2026, 6, 20, 8),
      authorId: 'host',
      category: category,
      distanceM: 21097,
      paceTargetSec: paceTargetSec,
      isPublic: true,
    ),
    byday: null,
    attendeeCount: attendees.length,
    viewerRsvp: viewerRsvp,
    nextInstanceStart: DateTime.utc(2026, 6, 20, 8),
  );
  @override
  Future<Set<DateTime>> fetchCancelledInstances(String eventId) async =>
      cancelled;

  @override
  Future<List<AttendeeView>> fetchAttendees(
    String eventId,
    DateTime instance,
  ) async => attendees;
  @override
  Future<List<EventResultView>> fetchEventResults(
    String eventId,
    DateTime instance,
  ) async => const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(
    String eventId,
    DateTime instance,
  ) async {
    final status = raceStatus;
    if (status == null) return null;
    final at = DateTime.utc(2026, 6, 20, 8);
    return RaceSessionRow(
      eventId: eventId,
      instanceStart: instance,
      status: status,
      startedAt: status == 'armed' ? null : at,
      createdAt: at,
      updatedAt: at,
      isAutoApprove: true,
    );
  }

  @override
  Future<int?> fetchRaceDnfPreview(String eventId, DateTime instance) async {
    dnfPreviewCalls++;
    return dnfCount;
  }

  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(
    String eventId,
  ) async => null;
  @override
  Future<void> rsvpEvent(
    String eventId,
    String status,
    DateTime instance, {
    String? courseId,
  }) async {
    rsvpCalls++;
    lastRsvpStatus = status;
    lastRsvpCourseId = courseId;
  }

  @override
  Future<List<EventCourseView>> fetchEventCourses(String eventId) async =>
      courses;

  @override
  Future<void> clearRsvp(String eventId, DateTime instance) async {
    clearCalls++;
  }

  @override
  RealtimeChannel subscribeToEvent(
    String eventId,
    String clubId,
    void Function() onChange,
  ) => Supabase.instance.client.channel('test-$eventId');
}

/// Drives the Submit-time sheet's failure path: a recent-runs fetch that
/// always throws, so the sheet must show the error + retry affordance
/// instead of spinning forever.
class _RecentRunsFailSocial extends _EventSocial {
  _RecentRunsFailSocial({super.club});
  int fetchRecentRunsCalls = 0;

  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async {
    fetchRecentRunsCalls++;
    throw Exception('network down');
  }
}

/// The result WRITE always fails — drives the submit-failure banner and
/// its Retry action (which must re-send the picked result, not re-open
/// the sheet).
class _SubmitFailSocial extends _EventSocial {
  _SubmitFailSocial({super.club});
  int submitCalls = 0;

  @override
  Future<List<RecentRunRow>> fetchRecentRuns({int limit = 20}) async =>
      const [];

  @override
  Future<void> submitEventResult({
    required String eventId,
    required DateTime instance,
    required int durationS,
    required double distanceM,
    String? runId,
    String finisherStatus = 'finished',
    double? ageGradePct,
    String? note,
    String? courseId,
    int? gunTimeS,
    int? chipTimeS,
    String? finishMethod,
  }) async {
    submitCalls++;
    throw Exception('network down');
  }
}

/// A class event carrying an attached gym routine (decisions § 1869) or
/// session plan. The fake applies the organiser's writes the way the database
/// does: attaching either one clears the other in the same write (§ 1884).
class _ClassRoutineSocial extends _EventSocial {
  _ClassRoutineSocial({super.club, this.gymRoutineId, this.sessionPlanId})
      : super(category: 'class');
  String? gymRoutineId;
  String? sessionPlanId;
  bool failWrite = false;
  bool failPlanWrite = false;
  final List<String?> routineWrites = [];
  final List<String?> planWrites = [];

  @override
  Future<List<({String id, String title})>> fetchSessionPlanOptions() async =>
      const [
        (id: 'plan-flow', title: 'Morning Flow'),
        (id: 'plan-core', title: 'Core Pilates'),
      ];

  @override
  Future<void> setEventSessionPlan(String eventId, String? id) async {
    planWrites.add(id);
    if (failPlanWrite) throw Exception('rls');
    sessionPlanId = id;
    if (id != null) gymRoutineId = null;
  }

  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
    row: EventRow(
      id: 'e1',
      clubId: 'club-1',
      title: 'Strength Class',
      startsAt: DateTime.utc(2026, 6, 20, 8),
      authorId: 'host',
      category: 'class',
      isPublic: true,
      gymRoutineId: gymRoutineId,
      sessionPlanId: sessionPlanId,
    ),
    byday: null,
    attendeeCount: 0,
    viewerRsvp: null,
    nextInstanceStart: DateTime.utc(2026, 6, 20, 8),
  );

  @override
  Future<List<({String id, String title})>> fetchClubGymRoutineOptions(
    String clubId,
  ) async => const [
    (id: 'r-lower', title: 'Lower Body'),
    (id: 'r-upper', title: 'Upper Body'),
  ];

  @override
  Future<void> setEventGymRoutine(String eventId, String? id) async {
    routineWrites.add(id);
    if (failWrite) throw Exception('rls');
    gymRoutineId = id;
    if (id != null) sessionPlanId = null;
  }
}

/// Answers the routine read for the routines this viewer can read; any other
/// id reads as null, which is what RLS hands a non-member.
class _RoutineApi extends ApiClient {
  _RoutineApi({
    this.readable = const {'r-lower', 'r-upper'},
    this.readablePlans = const {},
  });
  final Set<String> readable;

  /// Session plans this viewer can read, as [readable] is for routines.
  final Set<String> readablePlans;

  static final _at = DateTime.utc(2026, 6, 1);

  static GymRoutineExerciseRow _exercise(String routineId, String name, int pos) =>
      GymRoutineExerciseRow(
        id: '$routineId-$pos',
        routineId: routineId,
        exerciseName: name,
        exerciseKey: name.toLowerCase(),
        position: pos,
        modality: 'reps',
        progression: 'none',
        progressionParams: const <String, dynamic>{},
      );

  static List<GymRoutineSetRow> _sets(String exerciseId, int n) => [
    for (var i = 0; i < n; i++)
      GymRoutineSetRow(
        id: '$exerciseId-s$i',
        routineExerciseId: exerciseId,
        setIndex: i,
        setType: 'working',
        targetRepsMin: 5,
      ),
  ];

  @override
  Future<({
    GymRoutineRow routine,
    List<({GymRoutineExerciseRow exercise, List<GymRoutineSetRow> sets})> exercises,
  })?> fetchGymRoutineDetail(String id) async {
    if (!readable.contains(id)) return null;
    final lower = id == 'r-lower';
    final plan = lower
        ? [('Back Squat', 3), ('Romanian Deadlift', 1)]
        : [('Bench Press', 2)];
    final exercises = [
      for (final (i, (name, _)) in plan.indexed) _exercise(id, name, i),
    ];
    return (
      routine: GymRoutineRow(
        id: id,
        authorId: 'host',
        title: lower ? 'Lower Body' : 'Upper Body',
        periodisation: 'none',
        exerciseCount: exercises.length,
        lastModifiedAt: _at,
        createdAt: _at,
        clubId: 'club-1',
        isPublicTemplate: false,
      ),
      exercises: [
        for (final (i, ex) in exercises.indexed)
          (exercise: ex, sets: _sets(ex.id, plan[i].$2)),
      ],
    );
  }

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
    bool isOfficial,
  })?> fetchSessionPlan(String id) async {
    if (!readablePlans.contains(id)) return null;
    final flow = id == 'plan-flow';
    return (
      plan: SessionPlanRow(
        id: id,
        authorId: 'host',
        title: flow ? 'Morning Flow' : 'Core Pilates',
        isPublic: false,
        createdAt: _at,
        updatedAt: _at,
      ),
      blocks: [SessionPlanBlockRow(id: '$id-b0', planId: id, position: 0)],
      items: flow
          ? [
              SessionPlanItemRow(
                id: '$id-i0',
                planId: id,
                blockId: '$id-b0',
                position: 0,
                movementName: 'Cat-Cow',
                kind: 'flow',
                durationS: 30,
                perSide: false,
                cue: 'Breathe with the spine',
              ),
              SessionPlanItemRow(
                id: '$id-i1',
                planId: id,
                blockId: '$id-b0',
                position: 1,
                movementName: 'Pigeon',
                kind: 'hold',
                durationS: 45,
                perSide: true,
              ),
            ]
          : [
              SessionPlanItemRow(
                id: '$id-i0',
                planId: id,
                blockId: '$id-b0',
                position: 0,
                movementName: 'Hundred',
                kind: 'reps',
                reps: 100,
                perSide: false,
              ),
            ],
      isOfficial: false,
    );
  }
}

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EventDetailScreen(
        social: SocialService(),
        clubSlug: 'fake-slug',
        eventId: 'fake-event-id',
      ),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('EventDetailScreen — initial render', () {
    realtimeWidgetTest('first frame shows the full-body loader', (
      tester,
    ) async {
      // Reason: while _loading is true the screen returns a bare
      // Scaffold carrying nothing but the loader.
      await _pump(tester);
      expect(find.byType(FullBodyLoader), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
    });

    realtimeWidgetTest('initial Scaffold has no AppBar yet', (tester) async {
      await _pump(tester);
      expect(find.byType(AppBar), findsNothing);
    });
  });

  group('EventDetailScreen — cancelled occurrence', () {
    Future<_EventSocial> pumpWith(
      WidgetTester tester,
      Set<DateTime> cancelled,
    ) async {
      final social = _EventSocial(club: _club('member'), cancelled: cancelled);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'fake-slug',
            eventId: 'fake-event-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
      return social;
    }

    realtimeWidgetTest(
      'a cancelled occurrence says so and withholds the RSVP row',
      (tester) async {
        // event_exceptions was never read on mobile, so a cancelled occurrence
        // stayed selectable and RSVP-able with nothing saying it was called off.
        // The fixture is a one-off event, whose only occurrence is the event
        // itself, so the banner names the event.
        await pumpWith(tester, {DateTime.utc(2026, 6, 20, 8)});
        expect(find.text('This event was cancelled.'), findsOneWidget);
        expect(find.text("I'm in"), findsNothing);
      },
    );

    realtimeWidgetTest('a live occurrence keeps the RSVP row', (tester) async {
      await pumpWith(tester, const {});
      expect(find.text('This event was cancelled.'), findsNothing);
      expect(find.text("I'm in"), findsOneWidget);
    });
  });

  group('EventDetailScreen — waitlisted RSVP', () {
    Future<void> pumpWith(WidgetTester tester, String? rsvp) async {
      final social = _EventSocial(club: _club('member'), viewerRsvp: rsvp);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'fake-slug',
            eventId: 'fake-event-id',
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    realtimeWidgetTest('a demoted RSVP reads as waitlisted, not as no answer', (
      tester,
    ) async {
      // enforce_event_capacity silently rewrites a full event's `going` to
      // `waitlisted`. That matches none of the three chips, so the row looked
      // exactly like it does for someone who never responded.
      await pumpWith(tester, 'waitlisted');
      expect(find.text('Waitlisted'), findsOneWidget);
    });

    realtimeWidgetTest('an ordinary RSVP shows no waitlist line', (
      tester,
    ) async {
      await pumpWith(tester, 'going');
      expect(find.text('Waitlisted'), findsNothing);
    });

    realtimeWidgetTest('no RSVP shows no waitlist line', (tester) async {
      await pumpWith(tester, null);
      expect(find.text('Waitlisted'), findsNothing);
    });
  });

  group('EventDetailScreen — RSVP failure', () {
    realtimeWidgetTest(
      'a failed RSVP surfaces a banner instead of silently reverting',
      (tester) async {
        final social = _RsvpFailSocial();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventDetailScreen(
              social: social,
              clubSlug: 'club-1',
              eventId: 'e1',
            ),
          ),
        );
        // Let _load resolve (two Future.wait batches).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final going = find.widgetWithText(OutlinedButton, "I'm in");
        expect(going, findsOneWidget);
        await tester.tap(going);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(social.rsvpCalls, 1);
        expect(
          find.textContaining("Couldn't update your RSVP"),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 4)); // drain banner timer
      },
    );
  });

  group('EventDisciplineLabel — slice E class display', () {
    Future<void> pumpLabel(WidgetTester tester, String discipline) {
      return tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: EventDisciplineLabel(discipline: discipline)),
        ),
      );
    }

    realtimeWidgetTest('shows the CLASS eyebrow and the free-text discipline', (
      tester,
    ) async {
      await pumpLabel(tester, 'Vinyasa Yoga');
      expect(find.text('CLASS'), findsOneWidget);
      expect(find.text('Vinyasa Yoga'), findsOneWidget);
    });

    realtimeWidgetTest('renders no athletic affordances', (tester) async {
      await pumpLabel(tester, 'Pilates');
      // A class label is attendance-only: no distance / target-pace metric,
      // no results leaderboard, no Submit-my-time button.
      expect(find.text('Target pace'), findsNothing);
      expect(find.text('Submit my time'), findsNothing);
      expect(find.byType(EventResultsSection), findsNothing);
    });

    realtimeWidgetTest(
      'a long discipline is bounded + ellipsised (no overflow)',
      (tester) async {
        const longDiscipline =
            'Restorative candlelit Vinyasa flow with breathwork and '
            'progressive myofascial release for deep recovery';
        await pumpLabel(tester, longDiscipline);
        final value = tester.widget<Text>(find.text(longDiscipline));
        expect(value.maxLines, 2);
        expect(value.overflow, TextOverflow.ellipsis);
      },
    );
  });

  group('slice E gating predicate', () {
    test('class / social hide the athletic surface; run / cycle show it', () {
      expect(isAthleticEventCategory('class'), isFalse);
      expect(isAthleticEventCategory('social'), isFalse);
      expect(isAthleticEventCategory('run'), isTrue);
      expect(isAthleticEventCategory('cycle'), isTrue);
    });
  });

  Future<void> pumpEvent(WidgetTester tester, _EventSocial social) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: EventDetailScreen(
          social: social,
          clubSlug: 'club-1',
          eventId: 'e1',
        ),
      ),
    );
    // Two Future.wait batches in _load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('EventDetailScreen — RSVP success', () {
    realtimeWidgetTest(
      'a successful RSVP calls rsvpEvent once + shows no banner',
      (tester) async {
        final social = _EventSocial(club: _club('member'));
        await pumpEvent(tester, social);

        final going = find.widgetWithText(OutlinedButton, "I'm in");
        expect(going, findsOneWidget);
        await tester.tap(going);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(social.rsvpCalls, 1);
        expect(social.lastRsvpStatus, 'going');
        expect(find.textContaining("Couldn't update your RSVP"), findsNothing);
      },
    );
  });

  group('EventDetailScreen — attendee rendering', () {
    realtimeWidgetTest('attendee names render in the attendees section', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        attendees: const [
          AttendeeView(userId: 'a', status: 'going', displayName: 'Jamie'),
          AttendeeView(userId: 'b', status: 'maybe', displayName: 'Riley'),
        ],
      );
      await pumpEvent(tester, social);
      expect(find.text('Jamie'), findsOneWidget);
      expect(find.text('Riley'), findsOneWidget);
      expect(find.byType(IdentityAvatar), findsNWidgets(2));
    });

    realtimeWidgetTest('an event with no RSVPs shows the no-RSVPs hint', (
      tester,
    ) async {
      final social = _EventSocial(club: _club('member'), attendees: const []);
      await pumpEvent(tester, social);
      // eventNoRsvps copy.
      expect(find.textContaining('No RSVPs'), findsOneWidget);
    });
  });

  group('EventDetailScreen — Race control permission gating', () {
    realtimeWidgetTest(
      'a race director sees the Race control panel on an athletic event',
      (tester) async {
        final social = _EventSocial(club: _club('owner'), category: 'run');
        await pumpEvent(tester, social);
        // The race-control status line shows "Not armed" for a fresh race.
        expect(find.text('Not armed'), findsOneWidget);
      },
    );

    realtimeWidgetTest('a plain member does NOT see the Race control panel', (
      tester,
    ) async {
      final social = _EventSocial(club: _club('member'), category: 'run');
      await pumpEvent(tester, social);
      expect(find.text('Not armed'), findsNothing);
    });

    realtimeWidgetTest('a running race offers End and no Cancel, as on web', (
      tester,
    ) async {
      // The server refuses running -> cancelled, so a Cancel here could
      // only ever fail.
      final social = _EventSocial(club: _club('owner'), raceStatus: 'running');
      await pumpEvent(tester, social);
      expect(find.text('End race'), findsOneWidget);
      expect(find.text('Cancel race'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    realtimeWidgetTest('an armed race offers Fire Go and Cancel', (
      tester,
    ) async {
      final social = _EventSocial(club: _club('owner'), raceStatus: 'armed');
      await pumpEvent(tester, social);
      expect(find.text('Cancel'), findsOneWidget);
    });

    realtimeWidgetTest('End states how many racers it will mark DNF', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('owner'),
        raceStatus: 'running',
        dnfCount: 2,
      );
      await pumpEvent(tester, social);
      await tester.ensureVisible(find.text('End race'));
      await tester.tap(find.text('End race'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(social.dnfPreviewCalls, 1);
      expect(
        find.text(
          "End the race? 2 racers who started have no result and will be "
          "marked DNF. This can't be undone.",
        ),
        findsOneWidget,
      );
    });

    realtimeWidgetTest('End with no count to state keeps the plain body', (
      tester,
    ) async {
      final social = _EventSocial(club: _club('owner'), raceStatus: 'running');
      await pumpEvent(tester, social);
      await tester.ensureVisible(find.text('End race'));
      await tester.tap(find.text('End race'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(
          "End the race? This finalizes the event for every runner and can't "
          'be undone.',
        ),
        findsOneWidget,
      );
    });

    realtimeWidgetTest('a class event hides Race control even for an organiser', (
      tester,
    ) async {
      // A class is attendance-only — no athletic affordances regardless of role.
      final social = _EventSocial(club: _club('owner'), category: 'class');
      await pumpEvent(tester, social);
      expect(find.text('Not armed'), findsNothing);
    });
  });

  group('logWorkoutSeed — session-derived Log-as-workout prefill', () {
    ExpandedSession sampleSession() => expandSessionSteps(
      SessionPlanInput(
        blocks: const [],
        items: const [
          SessionPlanItemInput(
            id: 'i1',
            blockId: null,
            position: 0,
            movementName: 'Downward Dog',
            kind: SessionItemKind.hold,
            durationS: 30,
          ),
          SessionPlanItemInput(
            id: 'i2',
            blockId: null,
            position: 1,
            movementName: 'Warrior II',
            kind: SessionItemKind.reps,
            reps: 10,
            perSide: true,
          ),
        ],
      ),
    );

    test('no expansion → title-only from the flat gym_template path', () {
      final seed = logWorkoutSeed(
        gymTemplate: null,
        eventTitle: 'Morning Class',
        discipline: null,
      );
      expect(seed.title, 'Morning Class');
      expect(seed.sets, isNull);
    });

    test('no expansion → title prefers the gym_template discipline', () {
      final seed = logWorkoutSeed(
        gymTemplate: parseGymTemplate(const {'discipline': 'HIIT'}),
        eventTitle: 'Morning Class',
        discipline: 'HIIT',
      );
      expect(seed.title, 'HIIT');
      expect(seed.sets, isNull);
    });

    test(
      'with an attached session plan → one seeded set per expanded step',
      () {
        final seed = logWorkoutSeed(
          gymTemplate: null,
          eventTitle: 'Morning Class',
          discipline: 'Vinyasa Yoga',
          expansion: sampleSession(),
          sessionPlanTitle: 'Flow',
        );
        // Title prefers the class discipline over the flat title.
        expect(seed.title, 'Vinyasa Yoga');
        // Hold + per-side reps (left + right) = 3 seeded sets.
        final sets = seed.sets;
        expect(sets, isNotNull);
        expect(sets!.length, 3);
        expect(sets[0].exerciseName, 'Downward Dog');
        expect(sets[0].durationS, 30); // timed hold carries through
        expect(sets[0].reps, isNull);
        // The per-side reps item expands to two rows carrying the reps target.
        expect(sets[1].exerciseName, 'Warrior II');
        expect(sets[1].reps, 10);
        expect(sets[2].exerciseName, 'Warrior II');
        expect(sets[2].reps, 10);
      },
    );

    test(
      'title falls back to the flat gym_template title when no discipline',
      () {
        final seed = logWorkoutSeed(
          gymTemplate: null,
          eventTitle: 'Morning Class',
          discipline: null,
          expansion: sampleSession(),
          sessionPlanTitle: null,
        );
        expect(seed.title, 'Morning Class');
        expect(seed.sets, isNotNull);
      },
    );

    test('with an attached gym routine → one seeded set per planned set', () {
      final seed = logWorkoutSeed(
        gymTemplate: null,
        eventTitle: 'Evening Class',
        discipline: null,
        routine: const PlannedRoutine(
          title: 'Lower Body',
          exercises: [
            PlannedExercise(
              exerciseName: 'Back Squat',
              position: 0,
              sets: [
                PlannedSet(
                  setIndex: 0,
                  targetRepsMin: 5,
                  targetWeightKg: 60,
                  targetRpe: 8,
                ),
                PlannedSet(setIndex: 1, targetRepsMin: 5, targetWeightKg: 60),
              ],
            ),
          ],
        ),
      );
      // No discipline: the routine title names the workout.
      expect(seed.title, 'Lower Body');
      final sets = seed.sets!;
      expect(sets.length, 2);
      expect(sets[0].exerciseName, 'Back Squat');
      expect(sets[0].reps, 5);
      expect(sets[0].weightKg, 60.0);
      expect(sets[0].rpe, 8.0);
      expect(sets[1].rpe, isNull);
    });
  });

  group('M6 attendance — host-gating predicate', () {
    test('an organiser of a class event may mark attendance', () {
      expect(canMarkEventAttendance(_club('owner'), 'class'), isTrue);
      expect(canMarkEventAttendance(_club('admin'), 'class'), isTrue);
      expect(canMarkEventAttendance(_club('event_organiser'), 'class'), isTrue);
    });

    test('a non-organiser viewer may NOT mark attendance', () {
      expect(canMarkEventAttendance(_club('member'), 'class'), isFalse);
      expect(canMarkEventAttendance(_club(null), 'class'), isFalse);
      expect(canMarkEventAttendance(null, 'class'), isFalse);
    });

    test('attendance marking is class-only — never on run/cycle/social', () {
      expect(canMarkEventAttendance(_club('owner'), 'run'), isFalse);
      expect(canMarkEventAttendance(_club('owner'), 'cycle'), isFalse);
      expect(canMarkEventAttendance(_club('owner'), 'social'), isFalse);
    });
  });

  group('Submit-time sheet — recent-runs load failure', () {
    realtimeWidgetTest(
      'a fetchRecentRuns failure shows the error + retry, not a stuck spinner',
      (tester) async {
        final social = _RecentRunsFailSocial(club: _club('member'));
        await pumpEvent(tester, social);

        final submit = find.widgetWithText(FilledButton, 'Submit my time');
        expect(submit, findsOneWidget);
        await tester.tap(submit);
        await tester.pump(); // start the bottom-sheet route transition
        await tester.pump(const Duration(milliseconds: 300));

        expect(social.fetchRecentRunsCalls, 1);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text("Couldn't load your recent runs."), findsOneWidget);

        final retry = find.widgetWithText(TextButton, 'Retry');
        expect(retry, findsOneWidget);
        await tester.tap(retry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(social.fetchRecentRunsCalls, 2);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text("Couldn't load your recent runs."), findsOneWidget);
      },
    );
  });

  group('EventDetailScreen — result submit failure retry (issue #666 U8)', () {
    realtimeWidgetTest(
      'a failed submit shows a Retry banner that re-sends the picked '
      'result without re-opening the sheet',
      (tester) async {
        final social = _SubmitFailSocial(club: _club('member'));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventDetailScreen(
              social: social,
              clubSlug: 'club-1',
              eventId: 'e1',
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final submit = find.widgetWithText(FilledButton, 'Submit my time');
        expect(submit, findsOneWidget);
        await tester.tap(submit);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Pick the DNF shortcut so the sheet pops with a concrete choice.
        await tester.tap(find.widgetWithText(TextButton, 'Record DNF'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(social.submitCalls, 1);
        expect(find.textContaining('Submit failed'), findsOneWidget);
        final retry = find.widgetWithText(TextButton, 'Retry');
        expect(retry, findsOneWidget);
        // The sheet must not have re-opened.
        expect(find.text('Submit your time'), findsNothing);

        await tester.tap(retry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(social.submitCalls, 2);
        expect(find.text('Submit your time'), findsNothing);
      },
    );
  });

  group('EventDetailScreen — narrow-width overflow (issue #666 V7)', () {
    realtimeWidgetTest(
      'renders at a narrow width with the RSVP buttons in a Wrap so '
      'long localized labels flow to a second line instead of striping',
      (tester) async {
        // 400, not 320: below ~400 the EventPhotos add-photo row (a separate
        // widget file outside this fix's scope) still overflows under the
        // test Ahem font and would fail this test for an unrelated reason.
        tester.view.physicalSize = const Size(400, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final social = _EventSocial(club: _club('member'));
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventDetailScreen(
              social: social,
              clubSlug: 'fake-slug',
              eventId: 'fake-event-id',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.ancestor(
            of: find.widgetWithText(OutlinedButton, "I'm in"),
            matching: find.byType(Wrap),
          ),
          findsWidgets,
        );
      },
    );
  });

  group('EventDetailScreen — the results rank lane', () {
    // The finishing position sat in a 28px box. "999" needs 36.1px in real
    // Roboto at titleMedium w700 once the OS text scale reaches 1.5x and 48.2
    // at 2x, and a rank has no break opportunity, so it painted over the
    // finisher's name beside it. A four-digit field clears the box at 1.0x.
    //
    // Pinned as a derivation, never as an absolute fit: flutter_test renders a
    // fixed-advance font 2-6x wider than Roboto, so a lane whose floor tracks
    // the scale here tracks it on a device too.
    Future<void> pumpResults(WidgetTester tester, {double scale = 1.0}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(children: [
              EventResultsSection(
                results: [
                  EventResultView(
                    id: 'r-1',
                    userId: 'u-1',
                    displayName: 'Backmarker',
                    runId: null,
                    durationS: 18000,
                    distanceM: 42195,
                    rank: 999,
                    finisherStatus: 'finished',
                    organiserApproved: true,
                    ageGradePct: null,
                    note: null,
                    createdAt: DateTime.utc(2026, 3, 28),
                  ),
                ],
                myUserId: null,
                submitting: false,
                onSubmit: () {},
                onRemove: () {},
                eventTitle: 'Spring Marathon',
                clubName: null,
                certificateDate: DateTime.utc(2026, 3, 28),
              ),
            ]),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the lane widens to the rank instead of overpainting',
        (tester) async {
      await pumpResults(tester);
      final lane = find.ancestor(
        of: find.text('999'),
        matching: find.byType(TextLane),
      );
      expect(lane, findsOneWidget);
      final rank = tester.renderObject<RenderParagraph>(find.text('999'));
      expect(
        tester.getSize(lane).width,
        greaterThanOrEqualTo(rank.getMaxIntrinsicWidth(double.infinity)),
      );
    });

    testWidgets('the lane floor grows with the OS text scale', (tester) async {
      await pumpResults(tester, scale: 2.0);
      final lane = find.byType(TextLane).first;
      expect(tester.getSize(lane).width,
          greaterThanOrEqualTo(tester.widget<TextLane>(lane).width * 2));
    });

    testWidgets('a finisher row states the distance in the runner\'s unit',
        (tester) async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);

      await pumpResults(tester);
      expect(find.text('26.22 mi'), findsOneWidget);
      expect(find.text('42.20 km'), findsNothing);
    });
  });

  group('EventDetailScreen — the event metrics row', () {
    realtimeWidgetTest('distance and target pace follow the unit pref', (
      tester,
    ) async {
      // The target-pace metric read through a second, km-hardcoded fmtPace
      // that lived in social_service.dart, so a mile-unit runner saw the
      // event's target as a per-kilometre pace beside a distance in miles.
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: _EventSocial(club: _club('member'), paceTargetSec: 300),
            clubSlug: 'fake-slug',
            eventId: 'fake-event-id',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('13.11 mi'), findsOneWidget);
      // 300 s/km -> 300 * 1.609344 = 482.8 s/mi -> rounds to 483 -> 8:03.
      expect(find.text('8:03 /mi'), findsOneWidget);
      expect(find.text('5:00 /km'), findsNothing);
    });
  });

  group('EventDetailScreen — race courses (decisions § 1843)', () {
    const fiveK = EventCourseView(
      id: 'c-5k',
      eventId: 'e1',
      routeId: 'r-5k',
      name: '5K loop',
      distanceM: 5000,
      sortOrder: 0,
    );
    const tenK = EventCourseView(
      id: 'c-10k',
      eventId: 'e1',
      routeId: 'r-10k',
      name: '10K out-and-back',
      distanceM: 10000,
      sortOrder: 1,
    );

    Future<void> pumpCourses(WidgetTester tester, _EventSocial social) async {
      await pumpEvent(tester, social);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    realtimeWidgetTest('the courses are listed under the RSVP row', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        courses: const [fiveK, tenK],
      );
      await pumpCourses(tester, social);
      expect(find.byKey(const Key('event-courses')), findsOneWidget);
      expect(find.text('5K loop'), findsOneWidget);
      expect(find.text('10K out-and-back'), findsOneWidget);
    });

    realtimeWidgetTest('a single-course race RSVPs onto it with no picker', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        courses: const [fiveK],
      );
      await pumpCourses(tester, social);

      await tester.tap(find.widgetWithText(OutlinedButton, "I'm in"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SimpleDialog), findsNothing);
      expect(social.rsvpCalls, 1);
      expect(social.lastRsvpCourseId, 'c-5k');
    });

    realtimeWidgetTest('a multi-course race asks which course on Going', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        courses: const [fiveK, tenK],
      );
      await pumpCourses(tester, social);

      await tester.tap(find.widgetWithText(OutlinedButton, "I'm in"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pick your course'), findsOneWidget);
      expect(social.rsvpCalls, 0, reason: 'nothing is written before a pick');

      await tester.tap(find.byKey(const Key('course-option-c-10k')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(social.rsvpCalls, 1);
      expect(social.lastRsvpStatus, 'going');
      expect(social.lastRsvpCourseId, 'c-10k');
    });

    realtimeWidgetTest('dismissing the course picker writes no RSVP', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        courses: const [fiveK, tenK],
      );
      await pumpCourses(tester, social);

      await tester.tap(find.widgetWithText(OutlinedButton, "I'm in"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SimpleDialog), findsNothing);
      expect(social.rsvpCalls, 0);
    });

    realtimeWidgetTest('Maybe on a multi-course race needs no course', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        courses: const [fiveK, tenK],
      );
      await pumpCourses(tester, social);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Maybe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(SimpleDialog), findsNothing);
      expect(social.lastRsvpCourseId, isNull);
    });

    realtimeWidgetTest('a going racer sees their course and can change it', (
      tester,
    ) async {
      final social = _EventSocial(
        club: _club('member'),
        courses: const [fiveK, tenK],
        viewerRsvp: 'going',
        attendees: const [
          AttendeeView(userId: 'u-viewer', status: 'going', courseId: 'c-5k'),
        ],
      );
      await pumpCourses(tester, social);

      expect(find.text('Your course'), findsOneWidget);
      await tester.tap(find.byKey(const Key('change-course')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('course-option-c-10k')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(social.lastRsvpStatus, 'going');
      expect(social.lastRsvpCourseId, 'c-10k');
    });
  });

  group('EventDetailScreen — class gym routine card (decisions § 1869)', () {
    Future<void> pumpClass(
      WidgetTester tester,
      _ClassRoutineSocial social, {
      _RoutineApi? api,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'club-1',
            eventId: 'e1',
            api: api ?? _RoutineApi(),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(FullBodyLoader).evaluate().isEmpty,
        describe: 'the event to load',
      );
    }

    Future<void> openSheetAndPick(WidgetTester tester, String label) async {
      final attach = find.byKey(const Key('class-routine-attach'));
      await tester.ensureVisible(attach);
      await tester.tap(attach);
      await pumpUntil(
        tester,
        () => find.byKey(const Key('class-routine-picker')).evaluate().isNotEmpty,
        describe: 'the routine attach sheet',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('class-routine-picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    realtimeWidgetTest('an attendee sees the routine with its set counts', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('member'),
        gymRoutineId: 'r-lower',
      );
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => find.text('Back Squat').evaluate().isNotEmpty,
        describe: 'the routine card',
      );
      final card = find.byKey(const Key('class-routine'));
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Class routine')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Lower Body')),
          findsOneWidget);
      expect(find.text('3 sets'), findsOneWidget);
      expect(find.text('Romanian Deadlift'), findsOneWidget);
      expect(find.text('1 set'), findsOneWidget);
      // Only the organiser can change it.
      expect(find.byKey(const Key('class-routine-attach')), findsNothing);
    });

    realtimeWidgetTest('a viewer who cannot read the routine sees no card', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('member'),
        gymRoutineId: 'r-lower',
      );
      await pumpClass(tester, social, api: _RoutineApi(readable: const {}));
      await tester.pump();
      expect(find.byKey(const Key('class-routine')), findsNothing);
      expect(find.text('Class routine'), findsNothing);
    });

    realtimeWidgetTest('the organiser changes the routine after creation', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('event_organiser'),
        gymRoutineId: 'r-lower',
      );
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => find.text('Back Squat').evaluate().isNotEmpty,
        describe: 'the routine card',
      );
      await openSheetAndPick(tester, 'Upper Body');
      await tester.tap(find.byKey(const Key('class-routine-save')));
      await pumpUntil(
        tester,
        () => find.text('Bench Press').evaluate().isNotEmpty,
        describe: 'the card to show the new routine',
      );
      expect(social.routineWrites, ['r-upper']);
      expect(find.text('Back Squat'), findsNothing);
      expect(find.text('2 sets'), findsOneWidget);
      expect(find.text('Class routine updated.'), findsOneWidget);
    });

    realtimeWidgetTest('the organiser clears the routine', (tester) async {
      final social = _ClassRoutineSocial(
        club: _club('event_organiser'),
        gymRoutineId: 'r-lower',
      );
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => find.text('Back Squat').evaluate().isNotEmpty,
        describe: 'the routine card',
      );
      await openSheetAndPick(tester, 'None');
      await tester.tap(find.byKey(const Key('class-routine-save')));
      await pumpUntil(
        tester,
        () => find.text('No routine attached.').evaluate().isNotEmpty,
        describe: 'the card to show no routine',
      );
      expect(social.routineWrites, [null]);
      expect(find.text('Back Squat'), findsNothing);
      // The organiser keeps the card, so a routine can be attached again.
      expect(find.byKey(const Key('class-routine-attach')), findsOneWidget);
    });

    realtimeWidgetTest(
      'attaching a routine to a class with a session plan says it replaces it',
      (tester) async {
        final social = _ClassRoutineSocial(
          club: _club('event_organiser'),
          sessionPlanId: 'plan-1',
        );
        await pumpClass(tester, social);
        expect(find.text('No routine attached.'), findsOneWidget);
        await openSheetAndPick(tester, 'Lower Body');
        expect(find.byKey(const Key('class-routine-replaces-plan')),
            findsOneWidget);
        await tester.tap(find.byKey(const Key('class-routine-save')));
        await pumpUntil(
          tester,
          () => find.text('Back Squat').evaluate().isNotEmpty,
          describe: 'the card to show the attached routine',
        );
        expect(social.routineWrites, ['r-lower']);
        expect(social.sessionPlanId, isNull);
      },
    );

    realtimeWidgetTest('a failed write says so and keeps the routine', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('event_organiser'),
        gymRoutineId: 'r-lower',
      )..failWrite = true;
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => find.text('Back Squat').evaluate().isNotEmpty,
        describe: 'the routine card',
      );
      await openSheetAndPick(tester, 'Upper Body');
      await tester.tap(find.byKey(const Key('class-routine-save')));
      await pumpUntil(
        tester,
        () => find
            .text("Couldn't update the class routine.")
            .evaluate()
            .isNotEmpty,
        describe: 'the failure banner',
      );
      expect(social.routineWrites, ['r-upper']);
      expect(find.text('Back Squat'), findsOneWidget);
    });
  });

  group('EventDetailScreen — class session-plan card (session_planner.md P1)', () {
    const plans = {'plan-flow', 'plan-core'};

    Future<void> pumpClass(
      WidgetTester tester,
      _ClassRoutineSocial social, {
      Set<String> readablePlans = plans,
    }) async {
      // Tall enough that the session card, below the routine card, is built
      // by the lazy ListView without a scroll.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: EventDetailScreen(
            social: social,
            clubSlug: 'club-1',
            eventId: 'e1',
            api: _RoutineApi(readablePlans: readablePlans),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(FullBodyLoader).evaluate().isEmpty,
        describe: 'the event to load',
      );
    }

    Future<void> openSheetAndPick(WidgetTester tester, String label) async {
      final attach = find.byKey(const Key('session-sequence-attach'));
      await tester.ensureVisible(attach);
      await tester.tap(attach);
      await pumpUntil(
        tester,
        () => find
            .byKey(const Key('session-sequence-picker'))
            .evaluate()
            .isNotEmpty,
        describe: 'the session plan attach sheet',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('session-sequence-picker')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Finder inCard(String text) => find.descendant(
      of: find.byKey(const Key('session-sequence')),
      matching: find.text(text),
    );

    realtimeWidgetTest('an attendee sees the sequence with its cues', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('member'),
        sessionPlanId: 'plan-flow',
      );
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => inCard('Cat-Cow · flow 30s').evaluate().isNotEmpty,
        describe: 'the session-plan card',
      );
      expect(inCard('Session sequence'), findsOneWidget);
      expect(inCard('Morning Flow'), findsOneWidget);
      expect(inCard('Breathe with the spine'), findsOneWidget);
      // A per-side item expands into a left and a right step.
      expect(inCard('Pigeon (Left) · hold 45s'), findsOneWidget);
      expect(inCard('Pigeon (Right) · hold 45s'), findsOneWidget);
      // Only the organiser can change it.
      expect(find.byKey(const Key('session-sequence-attach')), findsNothing);
    });

    realtimeWidgetTest('a viewer who cannot read the plan sees no card', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('member'),
        sessionPlanId: 'plan-flow',
      );
      await pumpClass(tester, social, readablePlans: const {});
      await tester.pump();
      expect(find.byKey(const Key('session-sequence')), findsNothing);
      expect(find.text('Session sequence'), findsNothing);
    });

    realtimeWidgetTest('the organiser changes the plan after creation', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('event_organiser'),
        sessionPlanId: 'plan-flow',
      );
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => inCard('Cat-Cow · flow 30s').evaluate().isNotEmpty,
        describe: 'the session-plan card',
      );
      await openSheetAndPick(tester, 'Core Pilates');
      // No routine is attached, so there is nothing to warn about replacing.
      expect(find.byKey(const Key('session-sequence-replaces-routine')),
          findsNothing);
      await tester.tap(find.byKey(const Key('session-sequence-save')));
      await pumpUntil(
        tester,
        () => inCard('Hundred · 100 reps').evaluate().isNotEmpty,
        describe: 'the card to show the new plan',
      );
      expect(social.planWrites, ['plan-core']);
      expect(inCard('Cat-Cow · flow 30s'), findsNothing);
      expect(inCard('Core Pilates'), findsOneWidget);
      expect(find.text('Session plan updated.'), findsOneWidget);
    });

    realtimeWidgetTest('the organiser clears the plan', (tester) async {
      final social = _ClassRoutineSocial(
        club: _club('event_organiser'),
        sessionPlanId: 'plan-flow',
      );
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => inCard('Cat-Cow · flow 30s').evaluate().isNotEmpty,
        describe: 'the session-plan card',
      );
      await openSheetAndPick(tester, 'None');
      await tester.tap(find.byKey(const Key('session-sequence-save')));
      await pumpUntil(
        tester,
        () => inCard('None').evaluate().isNotEmpty,
        describe: 'the card to show no plan',
      );
      expect(social.planWrites, [null]);
      expect(social.sessionPlanId, isNull);
      expect(inCard('Cat-Cow · flow 30s'), findsNothing);
      // The organiser keeps the card, so a plan can be attached again.
      expect(find.byKey(const Key('session-sequence-attach')), findsOneWidget);
    });

    realtimeWidgetTest(
      'attaching a plan to a class with a routine says it replaces it',
      (tester) async {
        final social = _ClassRoutineSocial(
          club: _club('event_organiser'),
          gymRoutineId: 'r-lower',
        );
        await pumpClass(tester, social);
        await pumpUntil(
          tester,
          () => find.text('Back Squat').evaluate().isNotEmpty,
          describe: 'the routine card',
        );
        expect(inCard('None'), findsOneWidget);
        await openSheetAndPick(tester, 'Morning Flow');
        expect(find.byKey(const Key('session-sequence-replaces-routine')),
            findsOneWidget);
        await tester.tap(find.byKey(const Key('session-sequence-save')));
        await pumpUntil(
          tester,
          () => inCard('Cat-Cow · flow 30s').evaluate().isNotEmpty,
          describe: 'the card to show the attached plan',
        );
        expect(social.planWrites, ['plan-flow']);
        expect(social.gymRoutineId, isNull);
        // The re-read follows the cleared routine, so its card empties too.
        expect(find.text('Back Squat'), findsNothing);
        expect(find.text('No routine attached.'), findsOneWidget);
      },
    );

    realtimeWidgetTest('a failed write says so and keeps the plan', (
      tester,
    ) async {
      final social = _ClassRoutineSocial(
        club: _club('event_organiser'),
        sessionPlanId: 'plan-flow',
      )..failPlanWrite = true;
      await pumpClass(tester, social);
      await pumpUntil(
        tester,
        () => inCard('Cat-Cow · flow 30s').evaluate().isNotEmpty,
        describe: 'the session-plan card',
      );
      await openSheetAndPick(tester, 'Core Pilates');
      await tester.tap(find.byKey(const Key('session-sequence-save')));
      await pumpUntil(
        tester,
        () => find
            .text("Couldn't update the session plan.")
            .evaluate()
            .isNotEmpty,
        describe: 'the failure banner',
      );
      expect(social.planWrites, ['plan-core']);
      expect(social.sessionPlanId, 'plan-flow');
      expect(inCard('Cat-Cow · flow 30s'), findsOneWidget);
    });
  });
}
