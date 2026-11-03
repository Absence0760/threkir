// Share-link attribution on the phone (decisions § 2268): the ref a creator's
// own link carries, and the rows Your shares reads.

import 'package:flutter_test/flutter_test.dart';

import '../lib/share_ref.dart';

void main() {
  test('parseShareRef accepts exactly ten lowercase letters and digits', () {
    expect(parseShareRef('a1b2c3d4e5'), 'a1b2c3d4e5');
    for (final bad in ['A1B2C3D4E5', 'a1b2c3d4e', 'a1b2c3d4e5f', 'a1b2c3d4e_', '', null, 42]) {
      expect(parseShareRef(bad), isNull, reason: '$bad');
    }
  });

  test('withShareRef sets the ref and keeps the rest of the link', () {
    expect(withShareRef('https://threkir.com/share/challenge/c1', 'a1b2c3d4e5'),
        'https://threkir.com/share/challenge/c1?ref=a1b2c3d4e5');
    expect(withShareRef('https://threkir.com/share/challenge/c1?x=1', 'a1b2c3d4e5'),
        'https://threkir.com/share/challenge/c1?x=1&ref=a1b2c3d4e5');
    expect(withShareRef('https://threkir.com/share/challenge/c1', null),
        'https://threkir.com/share/challenge/c1');
    expect(withShareRef('https://threkir.com/share/challenge/c1', 'bad'),
        'https://threkir.com/share/challenge/c1');
  });

  test('withShareRef replaces a ref the link already carries', () {
    expect(
        withShareRef(
            'https://threkir.com/share/plan/x?ref=zzzzzzzzzz', 'a1b2c3d4e5'),
        'https://threkir.com/share/plan/x?ref=a1b2c3d4e5');
  });

  test('ShareStat.kinds names the five kinds the creator view counts', () {
    expect(ShareStat.kinds,
        {'plan', 'challenge', 'profile', 'session', 'workout'});
    for (final k in ['club', 'event', 'race', 'run', '']) {
      expect(ShareStat.fromRow({'kind': k, 'entity_id': 'x'}), isNull,
          reason: k);
    }
  });

  test('ShareStat.fromRow reads the counters and refuses an unknown kind', () {
    final s = ShareStat.fromRow({
      'kind': 'plan',
      'entity_id': 'p1',
      'title': 'Marathon block',
      'visits': 3,
      'ref_visits': 1,
      'bot_visits': 1,
      'signups': 1,
      'starts': 2,
      'ref_starts': 1,
      'joins': 0,
      'ref_joins': 0,
    })!;
    expect([s.visits, s.refVisits, s.botVisits, s.signups, s.starts, s.refStarts],
        [3, 1, 1, 1, 2, 1]);
    expect(ShareStat.fromRow({'kind': 'club', 'entity_id': 'x'}), isNull);
    expect(ShareStat.fromRow({'kind': 'plan'}), isNull);
  });
}
