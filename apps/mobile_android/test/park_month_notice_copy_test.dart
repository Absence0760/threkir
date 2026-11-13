import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/park_month_notice_copy.dart';

/// The month-close notice's inbox line (issue #1343): the course, the month
/// and the best time, never a rank, and the plain sentence whenever any part
/// is missing.
void main() {
  setUpAll(() => initializeDateFormatting());
  final l10n = AppLocalizationsEn();

  test('names the course, the month and the best time', () {
    expect(
      parkMonthNoticeText(
        l10n,
        courseName: 'Beaver Lake Trail',
        month: DateTime(2026, 10),
        timeS: 1471,
        localeTag: 'en',
      ),
      'Beaver Lake Trail: the October 2026 board has closed. Your best: 24:31',
    );
  });

  test('a missing course, month or time reads as the plain sentence', () {
    const plain = 'A month has closed on a park course you ran';
    expect(
      parkMonthNoticeText(l10n, courseName: null, month: DateTime(2026, 10), timeS: 1471, localeTag: 'en'),
      plain,
    );
    expect(
      parkMonthNoticeText(l10n, courseName: 'X', month: null, timeS: 1471, localeTag: 'en'),
      plain,
    );
    expect(
      parkMonthNoticeText(l10n, courseName: 'X', month: DateTime(2026, 10), timeS: null, localeTag: 'en'),
      plain,
    );
    expect(
      parkMonthNoticeText(l10n, courseName: 'X', month: DateTime(2026, 10), timeS: 0, localeTag: 'en'),
      plain,
    );
  });

  test('the line never carries a place', () {
    final text = parkMonthNoticeText(
      l10n,
      courseName: 'Beaver Lake Trail',
      month: DateTime(2026, 10),
      timeS: 1471,
      localeTag: 'en',
    );
    expect(text, isNot(contains('#')));
  });
}
