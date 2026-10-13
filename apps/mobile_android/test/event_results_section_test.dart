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
      id: 'r-${userId ?? 'bib'}',
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
          id: 'r-$user',
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

    testWidgets('a raced result shows gun time and chip time', (tester) async {
      await pumpTimed(tester, [timed('a', 'c-5k')], const []);
      expect(find.text('25:04'), findsOneWidget);
      expect(find.text('Chip 24:50'), findsOneWidget);
    });

    testWidgets('a device finish wears no badge, as on web (§ 1862)',
        (tester) async {
      // The badge flags a time the finish rule did not measure; an
      // unbadged time is a measured one.
      await pumpTimed(tester, [timed('a', 'c-5k', method: 'auto')], const []);
      expect(find.text('Auto'), findsNothing);
      expect(find.text('Manual'), findsNothing);
      expect(find.text('Host'), findsNothing);
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

  group('EventResultsSection — pending results and race-director moderation',
      () {
    EventResultView row(String? user,
            {bool approved = false, int rank = 1, String? name}) =>
        EventResultView(
          id: 'r-${user ?? 'bib'}',
          userId: user,
          displayName: name ?? user ?? 'Bib 42',
          runId: null,
          durationS: 1500,
          distanceM: 5000,
          rank: rank,
          finisherStatus: 'finished',
          organiserApproved: approved,
          ageGradePct: null,
          note: null,
          createdAt: DateTime(2026, 1, 1),
          gunTimeS: 1500,
        );

    Future<List<String>> pumpModerated(
      WidgetTester tester,
      List<EventResultView> results, {
      String? me,
      bool director = true,
      bool busy = false,
    }) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventResultsSection(
              results: results,
              myUserId: me,
              submitting: false,
              onSubmit: () {},
              onRemove: () {},
              eventTitle: 'Club race',
              clubName: null,
              certificateDate: DateTime(2026, 6, 12),
              moderation: director
                  ? ResultModeration(
                      busy: busy,
                      onApprove: (r, a) =>
                          calls.add('${a ? 'approve' : 'unverify'}:${r.id}'),
                      onEdit: (r) => calls.add('edit:${r.id}'),
                    )
                  : null,
            ),
          ),
        ),
      ));
      return calls;
    }

    Finder menuFor(String name) =>
        find.byTooltip('Result actions for $name');

    testWidgets('a pending result holds no place and says so', (tester) async {
      await pumpModerated(tester, [row('a', rank: 1)], director: false);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('an approved result shows its place and no pending mark',
        (tester) async {
      await pumpModerated(tester, [row('a', approved: true, rank: 3)],
          director: false);
      expect(find.text('Pending'), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('a racer who is not a director gets no actions', (tester) async {
      await pumpModerated(tester, [row('a')], director: false);
      expect(menuFor('a'), findsNothing);
    });

    testWidgets('a director approves a pending account result', (tester) async {
      final calls = await pumpModerated(tester, [row('a')]);
      await tester.tap(menuFor('a'));
      await tester.pumpAndSettle();
      expect(find.text('Unverify'), findsNothing);
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(calls, ['approve:r-a']);
    });

    testWidgets('a director unverifies an approved bib-only result',
        (tester) async {
      final calls = await pumpModerated(tester, [row(null, approved: true)]);
      await tester.tap(menuFor('Bib 42'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unverify'));
      await tester.pumpAndSettle();
      expect(calls, ['unverify:r-bib']);
    });

    testWidgets("a director's own approved result offers edit, not unverify",
        (tester) async {
      final calls =
          await pumpModerated(tester, [row('me', approved: true)], me: 'me');
      await tester.tap(menuFor('me'));
      await tester.pumpAndSettle();
      expect(find.text('Unverify'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(calls, ['edit:r-me']);
    });

    testWidgets('the actions are disabled while a write is in flight',
        (tester) async {
      await pumpModerated(tester, [row('a')], busy: true);
      final menu = tester.widget<PopupMenuButton<String>>(
          find.byType(PopupMenuButton<String>));
      expect(menu.enabled, isFalse);
    });

    test('resultApprovalAction matches the web results card', () {
      expect(resultApprovalAction(row('a'), myUserId: 'me'), isTrue);
      expect(resultApprovalAction(row('me'), myUserId: 'me'), isTrue,
          reason: 'a director approves their own pending result');
      expect(
          resultApprovalAction(row('a', approved: true), myUserId: 'me'), isFalse);
      expect(
          resultApprovalAction(row('me', approved: true), myUserId: 'me'), isNull);
      expect(resultApprovalAction(row(null, approved: true), myUserId: null),
          isFalse);
    });
  });

  group('ResultEditDialog', () {
    EventResultView finisher() => EventResultView(
          id: 'r-1',
          userId: 'u1',
          displayName: 'Sam',
          runId: null,
          durationS: 2500,
          distanceM: 10000,
          rank: 1,
          finisherStatus: 'finished',
          organiserApproved: true,
          ageGradePct: null,
          note: null,
          createdAt: DateTime(2026, 1, 1),
        );

    ResultEdit? edited;
    var closed = false;

    Future<void> open(WidgetTester tester) async {
      edited = null;
      closed = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                edited = await showDialog<ResultEdit>(
                  context: context,
                  builder: (_) =>
                      ResultEditDialog(result: finisher(), name: 'Sam'),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a new time and status come back as typed', (tester) async {
      await open(tester);
      expect(find.text('Edit result: Sam'), findsOneWidget);
      expect(find.text('41:40'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '45:00');
      await tester.tap(find.text('Save result'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(edited, (durationS: 2700, finisherStatus: 'finished'));
    });

    testWidgets('a finished result needs a valid time', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '40:90');
      await tester.tap(find.text('Save result'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a finish time like 42:10 or 1:02:03.'),
          findsOneWidget);
      expect(closed, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(edited, isNull);
    });

    testWidgets("a DNF with no time keeps the row's time", (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Finished'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DNF').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save result'));
      await tester.pumpAndSettle();
      expect(edited, (durationS: 2500, finisherStatus: 'dnf'));
    });
  });

  group('parseResultTimeS (web parseDurationToSeconds)', () {
    test('reads h:mm:ss, m:ss and plain seconds', () {
      expect(parseResultTimeS('1:02:03'), 3723);
      expect(parseResultTimeS(' 42:10 '), 2530);
      expect(parseResultTimeS('95'), 95);
      expect(parseResultTimeS('90:05'), 5405,
          reason: 'the leading field is unbounded');
    });

    test('refuses malformed times', () {
      for (final bad in ['', ':', '::', '1:', '40:90', '1:60:00', '1:2:3:4',
          '+5', '1e3', '0x10', 'abc']) {
        expect(parseResultTimeS(bad), isNull, reason: bad);
      }
    });
  });
}
