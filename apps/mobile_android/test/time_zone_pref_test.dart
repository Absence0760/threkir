// Mirrors apps/web/src/lib/settings/time_zone.test.ts case for case.
import 'package:flutter_test/flutter_test.dart';

import '../lib/time_zone_pref.dart';

void main() {
  test('timeZoneToWrite writes a zone the bag does not hold yet', () {
    expect(timeZoneToWrite(null, 'Europe/Berlin'), 'Europe/Berlin');
    expect(timeZoneToWrite('Australia/Sydney', 'Europe/Berlin'), 'Europe/Berlin');
  });

  test('timeZoneToWrite writes nothing when the zone is unchanged or unknown',
      () {
    expect(timeZoneToWrite('Europe/Berlin', 'Europe/Berlin'), isNull);
    expect(timeZoneToWrite('Europe/Berlin', null), isNull);
    expect(timeZoneToWrite(null, null), isNull);
  });

  test('timeZoneToWrite treats a blank device zone as unknown', () {
    expect(timeZoneToWrite(null, ''), isNull);
    expect(timeZoneToWrite('Europe/Berlin', '  '), isNull);
    expect(timeZoneToWrite(null, ' Asia/Tokyo '), 'Asia/Tokyo');
  });
}
