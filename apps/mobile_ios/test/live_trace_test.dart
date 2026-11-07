import 'package:flutter_test/flutter_test.dart';

import '../lib/live_trace.dart';

TracePing _ping(int? atMs, double lat,
        {bool weakGps = false, bool coarse = false}) =>
    TracePing(
      lat: lat,
      lng: 0,
      distanceM: lat * 10,
      elapsedS: lat.toInt(),
      atMs: atMs,
      weakGps: weakGps,
      coarse: coarse,
    );

List<double> _lats(LiveTrace t) => [for (final p in t.pings) p.lat];

void main() {
  test('insertPing: in-order arrivals each become the newest', () {
    final t = LiveTrace();
    expect(t.insertPing(_ping(1000, 1)), InsertResult.newest);
    expect(t.insertPing(_ping(2000, 2)), InsertResult.newest);
    expect(_lats(t), [1, 2]);
  });

  test('insertPing: a late arrival lands in time order, not at the end', () {
    final t = LiveTrace();
    t.insertPing(_ping(1000, 1));
    t.insertPing(_ping(3000, 3));
    expect(t.insertPing(_ping(2000, 2)), InsertResult.older);
    expect(_lats(t), [1, 2, 3]);
  });

  test('insertPing: the backlog overlapping the stream is not drawn twice',
      () {
    final t = LiveTrace();
    t.insertPing(_ping(2000, 2));
    t.insertPing(_ping(3000, 3));
    for (final p in [_ping(1000, 1), _ping(2000, 2), _ping(3000, 3)]) {
      t.insertPing(p);
    }
    expect(_lats(t), [1, 2, 3]);
  });

  test('insertPing: a duplicate reports itself and changes nothing', () {
    final t = LiveTrace();
    t.insertPing(_ping(1000, 1));
    expect(t.insertPing(_ping(1000, 1)), InsertResult.duplicate);
    expect(t.pings, hasLength(1));
  });

  test(
      'insertPing: two different pings sharing a clock are both kept, in '
      'arrival order', () {
    final t = LiveTrace();
    t.insertPing(_ping(1000, 1));
    expect(t.insertPing(_ping(1000, 2)), InsertResult.newest);
    expect(_lats(t), [1, 2]);
  });

  test(
      'insertPing: a ping without a clock goes last, and a replay of it is '
      'dropped', () {
    final t = LiveTrace();
    t.insertPing(_ping(5000, 1));
    expect(t.insertPing(_ping(null, 2)), InsertResult.newest);
    expect(t.insertPing(_ping(null, 2)), InsertResult.duplicate);
    expect(t.insertPing(_ping(null, 3)), InsertResult.newest);
    expect(_lats(t), [1, 2, 3]);
  });

  test('insertPing: an old ping arriving after the newest does not take its '
      'place', () {
    final t = LiveTrace();
    t.insertPing(_ping(9000, 9));
    expect(t.insertPing(_ping(1000, 1)), InsertResult.older);
    expect(t.newest!.lat, 9);
  });

  test('lineFixes: only precise fixes join the line', () {
    final t = LiveTrace();
    t.insertPing(_ping(1000, 1));
    t.insertPing(_ping(2000, 2, weakGps: true));
    t.insertPing(_ping(3000, 3, coarse: true));
    t.insertPing(_ping(4000, 4));
    expect([for (final p in t.lineFixes()) p.lat], [1, 4]);
  });

  test('pingTimeMs: a parseable instant is epoch ms, anything else is null',
      () {
    expect(pingTimeMs('2026-11-06T10:00:00Z'),
        DateTime.utc(2026, 11, 6, 10).millisecondsSinceEpoch);
    expect(pingTimeMs('1970-01-01T00:00:00Z'), isNull);
    expect(pingTimeMs('not a date'), isNull);
    expect(pingTimeMs(null), isNull);
    expect(pingTimeMs('2026-11-06 10:00:00.5+00'),
        DateTime.utc(2026, 11, 6, 10, 0, 0, 500).millisecondsSinceEpoch);
    for (final bad in [
      '2026-11-06',
      '2026-11-06T10:00:00',
      'Nov 6 2026 10:00 UTC',
      '2026-13-40T10:00:00Z',
    ]) {
      expect(pingTimeMs(bad), isNull, reason: bad);
    }
  });
}
