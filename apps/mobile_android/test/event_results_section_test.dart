import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/event_detail_screen.dart';
import '../lib/social_service.dart';

EventResultView _result({
  required String? userId,
  String finisherStatus = 'finished',
  bool organiserApproved = false,
}) =>
    EventResultView(
      userId: userId,
      displayName: 'Me',
      runId: null,
      durationS: 1500,
      distanceM: 5000,
      rank: 1,
      finisherStatus: finisherStatus,
      organiserApproved: organiserApproved,
      ageGradePct: null,
      note: null,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<EventResultView> results,
  required String? myUserId,
  required bool submitting,
  required VoidCallback onRemove,
  required VoidCallback onSubmit,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EventResultsSection(
          results: results,
          myUserId: myUserId,
          submitting: submitting,
          onSubmit: onSubmit,
          onRemove: onRemove,
          eventTitle: 'Riverside 10K',
          clubName: 'Richmond Run Club',
          certificateDate: DateTime(2026, 6, 12),
        ),
      ),
    ),
  );
}

void main() {
  group('EventResultsSection — remove my result', () {
    testWidgets('shows Remove mine when the viewer has a result', (tester) async {
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(find.text('Remove mine'), findsOneWidget);
      expect(find.text('Submit my time'), findsNothing);
    });

    testWidgets('shows Submit my time when the viewer has no result',
        (tester) async {
      await _pump(
        tester,
        results: [_result(userId: 'someone-else')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(find.text('Submit my time'), findsOneWidget);
      expect(find.text('Remove mine'), findsNothing);
    });

    testWidgets('Remove mine asks to confirm; Cancel does not fire onRemove',
        (tester) async {
      var removed = false;
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () => removed = true,
        onSubmit: () {},
      );

      await tester.tap(find.text('Remove mine'));
      await tester.pumpAndSettle();
      expect(find.text('Remove your result?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(removed, isFalse);
    });

    testWidgets('Remove mine → confirm fires onRemove', (tester) async {
      var removed = false;
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: false,
        onRemove: () => removed = true,
        onSubmit: () {},
      );

      await tester.tap(find.text('Remove mine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove result'));
      await tester.pumpAndSettle();
      expect(removed, isTrue);
    });

    testWidgets('Remove mine is disabled while a removal is in flight',
        (tester) async {
      var removed = false;
      await _pump(
        tester,
        results: [_result(userId: 'u1')],
        myUserId: 'u1',
        submitting: true,
        onRemove: () => removed = true,
        onSubmit: () {},
      );

      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Remove mine'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Remove mine'));
      await tester.pumpAndSettle();
      expect(find.text('Remove your result?'), findsNothing);
      expect(removed, isFalse);
    });
  });

  group('EventResultsSection — finisher certificate', () {
    Finder certButton() =>
        find.byIcon(Icons.workspace_premium_outlined);

    testWidgets('shows the certificate action for an approved finisher',
        (tester) async {
      await _pump(
        tester,
        results: [
          _result(
            userId: 'u1',
            finisherStatus: 'finished',
            organiserApproved: true,
          )
        ],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(certButton(), findsOneWidget);
    });

    testWidgets('hides the certificate action until the result is approved',
        (tester) async {
      await _pump(
        tester,
        results: [
          _result(
            userId: 'someone-else',
            finisherStatus: 'finished',
            organiserApproved: false,
          )
        ],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(certButton(), findsNothing);
    });

    testWidgets('hides the certificate action for a DNF', (tester) async {
      await _pump(
        tester,
        results: [
          _result(
            userId: 'someone-else',
            finisherStatus: 'dnf',
            organiserApproved: true,
          )
        ],
        myUserId: 'u1',
        submitting: false,
        onRemove: () {},
        onSubmit: () {},
      );
      expect(certButton(), findsNothing);
    });
  });

  group('EventResultsSection — live-race courses and timing (decisions § 1843)',
      () {
    const fiveK = EventCourseView(
        id: 'c-5k',
        eventId: 'e',
        routeId: null,
        name: '5K loop',
        distanceM: 5000,
        sortOrder: 0);
    const tenK = EventCourseView(
        id: 'c-10k',
        eventId: 'e',
        routeId: null,
        name: '10K',
        distanceM: 10000,
        sortOrder: 1);

    EventResultView timed(String user, String? course,
            {int duration = 1504,
            int? gun = 1504,
            int? chip = 1490,
            String? method = 'auto'}) =>
        EventResultView(
          userId: user,
          displayName: user,
          runId: null,
          durationS: duration,
          distanceM: 5000,
          rank: 1,
          finisherStatus: 'finished',
          organiserApproved: false,
          ageGradePct: null,
          note: null,
          createdAt: DateTime(2026, 1, 1),
          courseId: course,
          gunTimeS: gun,
          chipTimeS: chip,
          finishMethod: method,
        );

    Future<void> pumpTimed(WidgetTester tester, List<EventResultView> results,
        List<EventCourseView> courses) {
      return tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventResultsSection(
              results: results,
              myUserId: null,
              submitting: false,
              onSubmit: () {},
              onRemove: () {},
              eventTitle: 'Club race',
              clubName: null,
              certificateDate: DateTime(2026, 6, 12),
              courses: courses,
            ),
          ),
        ),
      ));
    }

    test('groupResultsByCourse follows the course order and keeps strays last',
        () {
      final groups = groupResultsByCourse([
        timed('a', 'c-10k'),
        timed('b', 'c-5k'),
        timed('c', null),
        timed('d', 'c-10k'),
        timed('e', 'c-gone'),
      ], const [fiveK, tenK]);
      expect(groups.map((g) => g.course?.id), ['c-5k', 'c-10k', null]);
      expect(groups[1].results.map((r) => r.userId), ['a', 'd']);
      expect(groups[2].results.map((r) => r.userId), ['c', 'e']);
    });

    test('a course with no results is dropped', () {
      final groups = groupResultsByCourse([timed('a', 'c-5k')], const [fiveK, tenK]);
      expect(groups.map((g) => g.course?.id), ['c-5k']);
    });

    testWidgets('several courses render one heading each', (tester) async {
      await pumpTimed(tester, [timed('a', 'c-5k'), timed('b', 'c-10k')],
          const [fiveK, tenK]);
      expect(find.text('5K loop'), findsOneWidget);
      expect(find.text('10K'), findsOneWidget);
    });

    testWidgets('a single course renders no headings', (tester) async {
      await pumpTimed(tester, [timed('a', 'c-5k')], const [fiveK]);
      expect(find.text('5K loop'), findsNothing);
    });

    testWidgets('a raced result shows gun time, chip time and its method',
        (tester) async {
      await pumpTimed(tester, [timed('a', 'c-5k')], const []);
      expect(find.text('25:04'), findsOneWidget);
      expect(find.text('Chip 24:50'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
    });

    testWidgets('a hand-submitted result shows neither chip nor method',
        (tester) async {
      await pumpTimed(tester,
          [timed('a', null, gun: null, chip: null, method: null)], const []);
      expect(find.textContaining('Chip'), findsNothing);
      expect(find.text('Auto'), findsNothing);
      expect(find.text('Manual'), findsNothing);
    });

    testWidgets('manual and host results carry their own badge',
        (tester) async {
      await pumpTimed(tester,
          [timed('a', null, method: 'manual'), timed('b', null, method: 'host')],
          const []);
      expect(find.text('Manual'), findsOneWidget);
      expect(find.text('Host'), findsOneWidget);
    });
  });
}
