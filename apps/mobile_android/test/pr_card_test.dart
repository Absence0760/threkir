// Mirrors apps/web/src/lib/share/pr_card.test.ts case for case.

import 'package:flutter_test/flutter_test.dart';

import '../lib/pr_card.dart';

void main() {
  group('prCardEntries', () {
    test('no rows → no entries', () {
      expect(prCardEntries(const [], const []), isEmpty);
    });

    test('an improvement carries the time it beat', () {
      final e = prCardEntries(const [PrImprovementRow('5k', 1440, 1500)], const []).single;
      expect(
        e,
        const PrCardEntry(distance: '5k', timeS: 1440, previousS: 1500, kind: PrCardKind.improved),
      );
    });

    test('an improvement with no previous time is a first', () {
      final e = prCardEntries(const [PrImprovementRow('10k', 2900, null)], const []).single;
      expect(e.kind, PrCardKind.first);
      expect(e.previousS, isNull);
    });

    test('a held record with no log row is held, with no previous time', () {
      final e = prCardEntries(const [], const [PrHeldRow('marathon', 12000)]).single;
      expect(
        e,
        const PrCardEntry(distance: 'marathon', timeS: 12000, previousS: null, kind: PrCardKind.held),
      );
    });

    test('the log wins over the cache row for the same bracket', () {
      final entries = prCardEntries(
        const [PrImprovementRow('5k', 1440, 1500)],
        const [PrHeldRow('5k', 1440)],
      );
      expect(entries, hasLength(1));
      expect(entries.single.kind, PrCardKind.improved);
    });

    test('brackets are ordered longest first', () {
      final entries = prCardEntries(
        const [PrImprovementRow('1_mile', 380, 400), PrImprovementRow('10k', 2900, null)],
        const [PrHeldRow('5k', 1400)],
      );
      expect(entries.map((e) => e.distance), ['10k', '5k', '1_mile']);
    });

    test('an unknown bracket and a non-positive time are dropped', () {
      final entries = prCardEntries(
        const [PrImprovementRow('50k', 18000, null), PrImprovementRow('5k', 0, null)],
        const [PrHeldRow('half_marathon', -1)],
      );
      expect(entries, isEmpty);
    });

    test('a previous time no slower than the new one is not an improvement', () {
      final e = prCardEntries(const [PrImprovementRow('5k', 1500, 1500)], const []).single;
      expect(e.kind, PrCardKind.first);
      expect(e.previousS, isNull);
    });
  });

  group('improvement', () {
    test('seconds faster and its printed form', () {
      final e = prCardEntries(const [PrImprovementRow('5k', 1440, 1482)], const []).single;
      expect(prImprovementSeconds(e), 42);
      expect(formatPrImprovement(e), '00:42');
    });

    test('an hour-long improvement prints hours', () {
      final e = prCardEntries(const [PrImprovementRow('marathon', 12000, 15700)], const []).single;
      expect(formatPrImprovement(e), '1:01:40');
    });

    test('nothing beaten → null', () {
      final e = prCardEntries(const [], const [PrHeldRow('5k', 1400)]).single;
      expect(prImprovementSeconds(e), isNull);
      expect(formatPrImprovement(e), isNull);
    });
  });

  group('brackets', () {
    test('every bracket has a distance, strictly increasing in declaration order', () {
      final metres = [for (final b in prBrackets) prBracketMetres[b]!];
      for (var i = 1; i < metres.length; i++) {
        expect(metres[i], greaterThan(metres[i - 1]));
      }
    });
  });
}
