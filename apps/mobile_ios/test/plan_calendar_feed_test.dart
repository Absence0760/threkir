// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_calendar_feed.dart';

final _token = '${'a' * 32}${'0123456789abcdef' * 4}';

void main() {
  test('a token is exactly the 96 lowercase hex characters the RPC mints', () {
    expect(isPlanCalendarFeedToken(_token), isTrue);
    expect(isPlanCalendarFeedToken(_token.substring(1)), isFalse);
    expect(isPlanCalendarFeedToken(_token.toUpperCase()), isFalse);
  });

  test('the feed URL is the plan-calendar function under the project URL', () {
    expect(
      planCalendarFeedUrl('https://abc.supabase.co', _token),
      'https://abc.supabase.co/functions/v1/plan-calendar/$_token.ics',
    );
    expect(
      planCalendarFeedUrl('https://abc.supabase.co/', _token),
      'https://abc.supabase.co/functions/v1/plan-calendar/$_token.ics',
    );
    expect(
      planCalendarFeedUrl('http://127.0.0.1:24321', _token),
      'http://127.0.0.1:24321/functions/v1/plan-calendar/$_token.ics',
    );
  });

  test('nothing that is not a minted token, or no project URL, becomes a link',
      () {
    expect(planCalendarFeedUrl('https://abc.supabase.co', '../rest/v1/runs'),
        isNull);
    expect(planCalendarFeedUrl(null, _token), isNull);
    expect(planCalendarFeedUrl('ftp://abc.supabase.co', _token), isNull);
    expect(planCalendarFeedUrl('not a url', _token), isNull);
  });

  test('only an https feed becomes a webcal subscribe link', () {
    expect(webcalUrl('https://abc.supabase.co/x.ics'),
        'webcal://abc.supabase.co/x.ics');
    expect(webcalUrl('http://127.0.0.1:24321/x.ics'), isNull);
  });

  test('status reads the two timestamps and refuses a row without a date', () {
    final s = PlanCalendarFeedStatus.fromRow({
      'created_at': '2031-01-01T00:00:00Z',
      'last_fetched_at': null,
    });
    expect(s?.createdAt, DateTime.utc(2031));
    expect(s?.lastFetchedAt, isNull);
    expect(PlanCalendarFeedStatus.fromRow(null), isNull);
    expect(PlanCalendarFeedStatus.fromRow({'created_at': 'nope'}), isNull);
  });
}
