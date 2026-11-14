import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/feed_highlights.dart';

String _utcDay(DateTime t) => t.toUtc().toIso8601String().substring(0, 10);

BadgeAwardEntry _award(String id, String authorId, String earnedAt) =>
    BadgeAwardEntry(
      badge: AchievementRow(
        id: id,
        userId: authorId,
        badgeKey: 'streak',
        tier: 'gold',
        sourceKind: 'streak',
        earnedAt: DateTime.parse(earnedAt),
        isPublic: true,
      ),
      authorId: authorId,
    );

typedef _Entry = ({String id, DateTime startedAt});
_Entry _entry(String id, String startedAt) =>
    (id: id, startedAt: DateTime.parse(startedAt));
DateTime _at(_Entry e) => e.startedAt;

List<String> _ids(List<FeedRow<_Entry>> rows) => [
      for (final r in rows)
        switch (r) {
          FeedEntryRow(:final entry) => entry.id,
          FeedHighlightRow(:final highlight) => highlight.key,
        },
    ];

List<String> _kinds(List<FeedRow<_Entry>> rows) => [
      for (final r in rows) r is FeedEntryRow ? 'entry' : 'highlight',
    ];

void main() {
  test('groupHighlights: no awards, no highlights', () {
    expect(groupHighlights(const [], dayKey: _utcDay), isEmpty);
  });

  test('groupHighlights: one award is a highlight of one', () {
    final g = groupHighlights([_award('b1', 'u1', '2026-06-10T08:00:00Z')],
        dayKey: _utcDay);
    expect(g, hasLength(1));
    expect(g[0].key, 'u1|2026-06-10');
    expect(g[0].awards, hasLength(1));
    expect(g[0].at, DateTime.parse('2026-06-10T08:00:00Z'));
  });

  test(
      'groupHighlights: one person, one day, several awards collapse, newest first',
      () {
    final g = groupHighlights([
      _award('b1', 'u1', '2026-06-10T08:00:00Z'),
      _award('b2', 'u1', '2026-06-10T19:00:00Z'),
      _award('b3', 'u1', '2026-06-10T12:00:00Z'),
    ], dayKey: _utcDay);
    expect(g, hasLength(1));
    expect(g[0].awards.map((a) => a.badge.id), ['b2', 'b3', 'b1']);
    expect(g[0].at, DateTime.parse('2026-06-10T19:00:00Z'));
  });

  test('groupHighlights: the same person on two days stays two rows', () {
    final g = groupHighlights([
      _award('b1', 'u1', '2026-06-10T08:00:00Z'),
      _award('b2', 'u1', '2026-06-11T08:00:00Z'),
    ], dayKey: _utcDay);
    expect(g.map((h) => h.key), ['u1|2026-06-11', 'u1|2026-06-10']);
  });

  test(
      'groupHighlights: two people on one day stay two rows, ordered by newest award',
      () {
    final g = groupHighlights([
      _award('b1', 'u1', '2026-06-10T08:00:00Z'),
      _award('b2', 'u2', '2026-06-10T09:00:00Z'),
    ], dayKey: _utcDay);
    expect(g.map((h) => h.authorId), ['u2', 'u1']);
  });

  test('groupHighlights: the day is the one the key function names', () {
    // 23:30 UTC on the 10th is the 11th at UTC+1.
    String plusOne(DateTime t) => _utcDay(t.add(const Duration(hours: 1)));
    final g = groupHighlights([
      _award('b1', 'u1', '2026-06-10T23:30:00Z'),
      _award('b2', 'u1', '2026-06-11T08:00:00Z'),
    ], dayKey: plusOne);
    expect(g, hasLength(1));
    expect(g[0].awards, hasLength(2));
  });

  test('groupHighlights: an award read twice counts once', () {
    final a = _award('b1', 'u1', '2026-06-10T08:00:00Z');
    final g = groupHighlights(
        [a, a, _award('b2', 'u1', '2026-06-10T09:00:00Z')],
        dayKey: _utcDay);
    expect(g[0].awards, hasLength(2));
  });

  test('groupHighlights: an equal instant orders by id, descending', () {
    final g = groupHighlights([
      _award('a', 'u1', '2026-06-10T08:00:00Z'),
      _award('c', 'u1', '2026-06-10T08:00:00Z'),
    ], dayKey: _utcDay);
    expect(g[0].awards.map((x) => x.badge.id), ['c', 'a']);
  });

  test('interleaveHighlights: highlights sit between entries by time', () {
    final hs = groupHighlights([
      _award('b1', 'u1', '2026-06-10T12:00:00Z'),
      _award('b2', 'u2', '2026-06-12T12:00:00Z'),
    ], dayKey: _utcDay);
    final rows = interleaveHighlights([
      _entry('r1', '2026-06-13T07:00:00Z'),
      _entry('r2', '2026-06-11T07:00:00Z'),
      _entry('r3', '2026-06-09T07:00:00Z'),
    ], _at, hs, true);
    expect(_ids(rows), ['r1', 'u2|2026-06-12', 'r2', 'u1|2026-06-10', 'r3']);
  });

  test(
      'interleaveHighlights: one older than the last entry waits while more activity can load',
      () {
    final hs = groupHighlights([_award('b1', 'u1', '2026-06-01T12:00:00Z')],
        dayKey: _utcDay);
    final rows = interleaveHighlights(
        [_entry('r1', '2026-06-10T07:00:00Z')], _at, hs, false);
    expect(_kinds(rows), ['entry']);
  });

  test(
      'interleaveHighlights: once the activity has run out, older highlights trail it',
      () {
    final hs = groupHighlights([_award('b1', 'u1', '2026-06-01T12:00:00Z')],
        dayKey: _utcDay);
    final rows = interleaveHighlights(
        [_entry('r1', '2026-06-10T07:00:00Z')], _at, hs, true);
    expect(_kinds(rows), ['entry', 'highlight']);
  });

  test('interleaveHighlights: no activity at all still shows the highlights',
      () {
    final hs = groupHighlights([_award('b1', 'u1', '2026-06-01T12:00:00Z')],
        dayKey: _utcDay);
    final rows = interleaveHighlights(<_Entry>[], _at, hs, true);
    expect(_kinds(rows), ['highlight']);
  });

  test(
      'interleaveHighlights: nothing while the first activity page has not loaded',
      () {
    final hs = groupHighlights([_award('b1', 'u1', '2026-06-01T12:00:00Z')],
        dayKey: _utcDay);
    expect(interleaveHighlights(<_Entry>[], _at, hs, false), isEmpty);
  });

  test(
      'interleaveHighlights: at an equal instant the activity entry comes first',
      () {
    final hs = groupHighlights([_award('b1', 'u1', '2026-06-10T07:00:00Z')],
        dayKey: _utcDay);
    final rows = interleaveHighlights(
        [_entry('r1', '2026-06-10T07:00:00Z')], _at, hs, false);
    expect(_kinds(rows), ['entry', 'highlight']);
  });

  test('interleaveHighlights: no highlights leaves the entries untouched', () {
    final rows = interleaveHighlights(
        [_entry('r1', '2026-06-10T07:00:00Z')], _at, const [], false);
    expect(_ids(rows), ['r1']);
  });

  test('needsMoreHighlights: an unread stream needs its first page', () {
    expect(
      needsMoreHighlights(
        oldestAwardAt: null,
        awardsExhausted: false,
        oldestEntryAt: null,
        feedExhausted: false,
      ),
      isTrue,
    );
  });

  test('needsMoreHighlights: an exhausted stream never does', () {
    expect(
      needsMoreHighlights(
        oldestAwardAt: null,
        awardsExhausted: true,
        oldestEntryAt: null,
        feedExhausted: true,
      ),
      isFalse,
    );
  });

  test(
      'needsMoreHighlights: awards reaching no further back than the activity read on',
      () {
    expect(
      needsMoreHighlights(
        oldestAwardAt: DateTime.parse('2026-06-10T00:00:00Z'),
        awardsExhausted: false,
        oldestEntryAt: DateTime.parse('2026-06-05T00:00:00Z'),
        feedExhausted: false,
      ),
      isTrue,
    );
  });

  test('needsMoreHighlights: awards reaching past the activity wait for it',
      () {
    expect(
      needsMoreHighlights(
        oldestAwardAt: DateTime.parse('2026-06-01T00:00:00Z'),
        awardsExhausted: false,
        oldestEntryAt: DateTime.parse('2026-06-05T00:00:00Z'),
        feedExhausted: false,
      ),
      isFalse,
    );
  });

  test(
      'needsMoreHighlights: once the activity has run out the awards read to their end',
      () {
    expect(
      needsMoreHighlights(
        oldestAwardAt: DateTime.parse('2026-06-01T00:00:00Z'),
        awardsExhausted: false,
        oldestEntryAt: DateTime.parse('2026-06-05T00:00:00Z'),
        feedExhausted: true,
      ),
      isTrue,
    );
  });

  test('highlightsShowFor: only the All chip shows highlights', () {
    expect(highlightsShowFor('all'), isTrue);
    for (final f in ['run', 'walk', 'cycle', 'hike', 'lift']) {
      expect(highlightsShowFor(f), isFalse);
    }
  });
}
