import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/event_host_cancel.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/social_service.dart';
import 'realtime_drain.dart';

ClubView _club(String role) => ClubView(
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
      viewerRole: role,
      viewerStatus: 'active',
      joinPolicy: 'open',
    );

/// A class event whose host-cancel calls are captured rather than sent.
class _CancelSocial extends SocialService {
  _CancelSocial({
    required this.startsAt,
    this.role = 'owner',
    this.freq,
    this.until,
    this.cancelled = const {},
    this.attendees = const [],
    this.refunds,
    this.refuseWith,
  });

  final DateTime startsAt;
  final String role;
  final String? freq;
  final DateTime? until;
  Set<DateTime> cancelled;
  final List<AttendeeView> attendees;
  final OccurrenceRefundSummary? refunds;
  final String? refuseWith;

  final List<DateTime> occurrenceCancels = [];
  int seriesCancels = 0;
  final List<DateTime> reinstates = [];

  @override
  String? get currentUserId => 'u-viewer';
  @override
  Future<ClubView?> fetchClubBySlug(String slug) async => _club(role);
  @override
  Future<EventView?> fetchEventById(String eventId) async => EventView(
        row: EventRow(
          id: 'e1',
          clubId: 'club-1',
          title: 'Reformer',
          startsAt: startsAt,
          authorId: 'host',
          category: 'class',
          recurrenceFreq: freq,
          recurrenceUntil: until,
          timezone: 'UTC',
          isPublic: true,
        ),
        byday: null,
        attendeeCount: 0,
        viewerRsvp: null,
        nextInstanceStart: startsAt,
      );
  @override
  Future<Set<DateTime>> fetchCancelledInstances(String eventId) async =>
      cancelled;
  @override
  Future<List<AttendeeView>> fetchAttendees(
          String eventId, DateTime instance) async =>
      attendees;
  @override
  Future<List<EventResultView>> fetchEventResults(
          String eventId, DateTime instance) async =>
      const [];
  @override
  Future<RaceSessionRow?> fetchRaceSession(
          String eventId, DateTime instance) async =>
      null;
  @override
  Future<({double lat, double lng})?> fetchEventMeetPoint(
          String eventId) async =>
      null;
  @override
  RealtimeChannel subscribeToEvent(
          String eventId, String clubId, void Function() onChange) =>
      Supabase.instance.client.channel('test-$eventId');

  @override
  Future<OccurrenceRefundSummary?> cancelEventOccurrence(
    String eventId,
    DateTime instance, {
    String? reason,
  }) async {
    occurrenceCancels.add(instance);
    if (refuseWith != null) throw EventCancelRefused(refuseWith!);
    cancelled = {...cancelled, instance.toUtc()};
    return refunds;
  }

  @override
  Future<OccurrenceRefundSummary> cancelEventSeries(
    String eventId, {
    String? reason,
  }) async {
    seriesCancels++;
    if (refuseWith != null) throw EventCancelRefused(refuseWith!);
    return refunds ??
        const OccurrenceRefundSummary(
          complete: true,
          initiated: 0,
          alreadyRefunded: 0,
          released: 0,
          failed: 0,
          failedOrderIds: [],
        );
  }

  @override
  Future<void> reinstateEventOccurrence(
      String eventId, DateTime instance) async {
    reinstates.add(instance);
    cancelled = {...cancelled}..remove(instance.toUtc());
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_ensureSupabase);

  Future<void> pump(WidgetTester tester, _CancelSocial social) async {
    await tester.binding.setSurfaceSize(const Size(600, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.pumpAndSettle();
  }

  DateTime aheadBy(int days) {
    final now = DateTime.now().toUtc();
    return DateTime.utc(
        now.year, now.month, now.day + days, now.hour, now.minute, now.second);
  }

  Future<void> reveal(WidgetTester tester, Finder target) => tester
      .scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);

  Future<void> confirm(WidgetTester tester) async {
    expect(find.byKey(const Key('cancel-paid-note')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-confirm')));
    await tester.pumpAndSettle();
  }

  group('EventDetailScreen — host cancel', () {
    realtimeWidgetTest('a plain member is offered no cancel controls',
        (tester) async {
      await pump(tester, _CancelSocial(startsAt: aheadBy(7), role: 'member'));
      expect(find.byKey(const Key('cancel-occurrence')), findsNothing);
      expect(find.byKey(const Key('cancel-series')), findsNothing);
    });

    realtimeWidgetTest(
        'a one-off event is cancelled as its own occurrence, with no series '
        'control', (tester) async {
      final start = aheadBy(7);
      final social = _CancelSocial(startsAt: start);
      await pump(tester, social);
      expect(find.byKey(const Key('cancel-series')), findsNothing);
      await reveal(tester, find.byKey(const Key('cancel-occurrence')));
      expect(find.widgetWithText(OutlinedButton, 'Cancel event'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-occurrence')));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(social.occurrenceCancels, [start]);
      expect(find.text('Cancelled.'), findsOneWidget);
      expect(find.text('This event was cancelled.'), findsOneWidget);
    });

    realtimeWidgetTest('a cancelled one-off event can be reinstated',
        (tester) async {
      final start = aheadBy(7);
      final social = _CancelSocial(startsAt: start, cancelled: {start});
      await pump(tester, social);
      expect(find.text('This event was cancelled.'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('reinstate-occurrence')));
      await tester.tap(find.byKey(const Key('reinstate-occurrence')));
      await tester.pumpAndSettle();
      expect(social.reinstates, [start]);
      expect(find.text('This event was cancelled.'), findsNothing);
    });

    realtimeWidgetTest(
        'a series offers both cancels, and the series cancel reports its refunds',
        (tester) async {
      final social = _CancelSocial(
        startsAt: aheadBy(7),
        freq: 'weekly',
        refunds: const OccurrenceRefundSummary(
          complete: true,
          initiated: 2,
          alreadyRefunded: 0,
          released: 0,
          failed: 0,
          failedOrderIds: [],
        ),
      );
      await pump(tester, social);
      await reveal(tester, find.byKey(const Key('cancel-series')));
      expect(find.widgetWithText(OutlinedButton, 'Cancel this occurrence'),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('cancel-series')));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(social.seriesCancels, 1);
      expect(find.text('Cancelled. 2 registrants are being refunded in full.'),
          findsOneWidget);
    });

    realtimeWidgetTest(
        'a paid cancel the server cannot refund says so and changes nothing',
        (tester) async {
      final social = _CancelSocial(
          startsAt: aheadBy(7), refuseWith: 'stripe_not_configured');
      await pump(tester, social);
      await reveal(tester, find.byKey(const Key('cancel-occurrence')));
      await tester.tap(find.byKey(const Key('cancel-occurrence')));
      await tester.pumpAndSettle();
      await confirm(tester);

      expect(social.occurrenceCancels, hasLength(1));
      expect(find.textContaining("payments aren't available right now"),
          findsOneWidget);
      expect(find.text('This event was cancelled.'), findsNothing);
    });

    realtimeWidgetTest('backing out of the confirmation cancels nothing',
        (tester) async {
      final social = _CancelSocial(startsAt: aheadBy(7));
      await pump(tester, social);
      await reveal(tester, find.byKey(const Key('cancel-occurrence')));
      await tester.tap(find.byKey(const Key('cancel-occurrence')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(social.occurrenceCancels, isEmpty);
    });

    realtimeWidgetTest('a series its host cancelled says so', (tester) async {
      final start = aheadBy(-30);
      await pump(
        tester,
        _CancelSocial(
          startsAt: start,
          freq: 'weekly',
          until: aheadBy(-2),
          cancelled: {aheadBy(5)},
          role: 'member',
        ),
      );
      expect(find.byKey(const Key('series-cancelled')), findsOneWidget);
      expect(find.text('This series was cancelled.'), findsOneWidget);
    });
  });

  group('EventDetailScreen — waitlist offer', () {
    realtimeWidgetTest(
        'a held seat shows its deadline and a claim that opens the web',
        (tester) async {
      await pump(
        tester,
        _CancelSocial(
          startsAt: aheadBy(7),
          role: 'member',
          attendees: [
            AttendeeView(
              userId: 'u-viewer',
              status: 'waitlisted',
              offerExpiresAt: DateTime.now().add(const Duration(hours: 6)),
            ),
          ],
        ),
      );
      expect(find.byKey(const Key('waitlist-offer')), findsOneWidget);
      expect(find.textContaining('until'), findsWidgets);
      expect(find.byKey(const Key('waitlist-claim')), findsOneWidget);
    });

    realtimeWidgetTest('a lapsed offer, or a plain waitlist place, holds nothing',
        (tester) async {
      await pump(
        tester,
        _CancelSocial(
          startsAt: aheadBy(7),
          role: 'member',
          attendees: [
            AttendeeView(
              userId: 'u-viewer',
              status: 'waitlisted',
              offerExpiresAt:
                  DateTime.now().subtract(const Duration(minutes: 1)),
            ),
            const AttendeeView(userId: 'u-other', status: 'waitlisted'),
          ],
        ),
      );
      expect(find.byKey(const Key('waitlist-offer')), findsNothing);
    });

    test('the claim link is the event page on the web', () {
      expect(eventWebUrl('studio one', 'e1', webBase: 'https://preview.test/'),
          'https://preview.test/clubs/studio%20one/events/e1');
      expect(eventWebUrl('s', 'e1', webBase: ''),
          'https://threkir.com/clubs/s/events/e1');
    });
  });
}
