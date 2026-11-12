// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_calendar_feed_screen.dart';

final _token = '${'b' * 32}${'0123456789abcdef' * 4}';

class _FakeFeed {
  _FakeFeed({this.row, this.loadFails = false, this.rotateError});

  Map<String, dynamic>? row;
  final bool loadFails;
  final Object? rotateError;
  int rotations = 0;
  int revocations = 0;

  Future<Map<String, dynamic>?> load() async {
    if (loadFails) throw Exception('offline');
    return row;
  }

  Future<String> rotate() async {
    if (rotateError != null) throw rotateError!;
    rotations++;
    return _token;
  }

  Future<void> revoke() async {
    revocations++;
    row = null;
  }
}

Future<void> _pump(WidgetTester tester, _FakeFeed feed) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: PlanCalendarFeedScreen(
      loadStatus: feed.load,
      rotate: feed.rotate,
      revoke: feed.revoke,
      supabaseUrl: 'https://abc.supabase.co',
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('with no feed, creating one shows the link once with a subscribe action',
      (tester) async {
    final feed = _FakeFeed();
    await _pump(tester, feed);

    await tester.tap(find.byKey(const ValueKey('plan-calendar-feed-create')));
    await tester.pump();

    expect(feed.rotations, 1);
    expect(
      find.text('https://abc.supabase.co/functions/v1/plan-calendar/$_token.ics'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('plan-calendar-feed-subscribe')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('plan-calendar-feed-revoke')),
        findsOneWidget);
  });

  testWidgets('an existing feed shows its dates, never a link', (tester) async {
    final feed = _FakeFeed(row: {
      'created_at': '2031-01-01T00:00:00Z',
      'last_fetched_at': null,
    });
    await _pump(tester, feed);

    expect(find.byKey(const ValueKey('plan-calendar-feed-active')),
        findsOneWidget);
    expect(find.text('No calendar has read it yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-calendar-feed-url')), findsNothing);
  });

  testWidgets('replacing the link asks first, and cancelling keeps the old one',
      (tester) async {
    final feed = _FakeFeed(row: {'created_at': '2031-01-01T00:00:00Z'});
    await _pump(tester, feed);

    await tester.tap(find.byKey(const ValueKey('plan-calendar-feed-rotate')));
    await tester.pumpAndSettle();
    expect(find.text('Make a new calendar link?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(feed.rotations, 0);

    await tester.tap(find.byKey(const ValueKey('plan-calendar-feed-rotate')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Make a new link'),
    ));
    await tester.pumpAndSettle();
    expect(feed.rotations, 1);
    expect(find.byKey(const ValueKey('plan-calendar-feed-url')), findsOneWidget);
  });

  testWidgets('turning the link off asks first, then returns to the empty state',
      (tester) async {
    final feed = _FakeFeed(row: {'created_at': '2031-01-01T00:00:00Z'});
    await _pump(tester, feed);

    await tester.tap(find.byKey(const ValueKey('plan-calendar-feed-revoke')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Turn off'),
    ));
    await tester.pumpAndSettle();

    expect(feed.revocations, 1);
    expect(find.byKey(const ValueKey('plan-calendar-feed-create')),
        findsOneWidget);
  });

  testWidgets('a failed status read says so and offers a retry', (tester) async {
    await _pump(tester, _FakeFeed(loadFails: true));
    expect(find.byKey(const ValueKey('plan-calendar-feed-load-error')),
        findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a throttled create names the calendar link, not a generic error',
      (tester) async {
    final feed = _FakeFeed(
      rotateError: const PostgrestException(
        message: 'rate limit exceeded for plan_calendar_rotate, retry in 600s',
        code: 'P0001',
      ),
    );
    await _pump(tester, feed);
    await tester.tap(find.byKey(const ValueKey('plan-calendar-feed-create')));
    await tester.pump();

    expect(find.textContaining("You're making new calendar links too quickly"),
        findsOneWidget);
    expect(find.byKey(const ValueKey('plan-calendar-feed-url')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
  });
}
