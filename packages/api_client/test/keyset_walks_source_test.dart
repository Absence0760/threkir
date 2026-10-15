import 'dart:io';

import 'package:test/test.dart';

/// Pins the reads whose contract is "every row" to a keyset walk.
///
/// PostgREST caps an unranged SELECT at `db.max-rows` with a 200 and no flag,
/// so these reads have to walk — `fetchRunRowsRaw` once archived 1,000 runs of
/// a 1,400-run history (decisions § 668). They walked by `.range()`, i.e.
/// LIMIT/OFFSET, and an OFFSET names a position: a run synced or deleted while
/// the backup is between two pages moves every later row, so one run is
/// archived twice and another not at all (§ 1927). Each read now goes through
/// `_walk`, which pages by keyset cursor (`walkKeyset` in core_models, whose
/// paging is pinned against in-memory rows by `keyset_page_test.dart`). A
/// source guard because the regression is static and the failure it prevents
/// is silent.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();

  /// The member from its declaration to the next member's doc comment.
  String body(String signature) {
    final start = src.indexOf(signature);
    if (start < 0) return '';
    final end = src.indexOf('\n  /// ', start + signature.length);
    return src.substring(start, end == -1 ? src.length : end);
  }

  /// The columns of `static const List<KeysetKey> <name> = [ ... ];`.
  List<String> orderColumns(String name) {
    final m = RegExp(
      'static const List<KeysetKey> ${RegExp.escape(name)} = \\[([^\\]]*)\\]',
    ).firstMatch(src);
    if (m == null) return const [];
    return RegExp(r'KeysetKey\(\s*([\w.]+|' "'" r'\w+' "'" r')')
        .allMatches(m.group(1)!)
        .map((k) => k.group(1)!)
        .toList();
  }

  test('no read in the client pages by offset', () {
    expect(src.contains('.range('), isFalse,
        reason: '.range() is LIMIT/OFFSET; walk with _walk instead');
    expect(src.contains('readAllPages'), isFalse);
  });

  test('_walk filters after the cursor and sorts by the cursor\'s own order',
      () {
    final walk = body('Future<List<Map<String, dynamic>>> _walk(');
    expect(walk, isNotEmpty, reason: '_walk moved or was renamed');
    expect(walk.contains('walkKeyset(order,'), isTrue);
    expect(walk.contains('q.or(after)'), isTrue);
    expect(walk.contains('_orderBy(q, order).limit(limit)'), isTrue,
        reason: 'a cursor taken in one order and applied in another skips '
            'rows');
  });

  for (final (signature, order) in const [
    ('Future<List<Map<String, dynamic>>> fetchRunRowsRaw()', '_runRowsOrder'),
    ('Future<List<Map<String, dynamic>>> fetchRouteRowsRaw()', '_routeRowsOrder'),
    ('Future<List<RouteReviewRow>> getRouteReviews(', '_routeReviewOrder'),
    ('Future<List<EventAttendeeRow>> fetchEventAttendees(', 'eventAttendeeOrder'),
    (
      'Future<List<CheckpointCrossingRow>> fetchCheckpointCrossings(',
      '_checkpointCrossingOrder'
    ),
    ('Future<List<ExerciseRow>> fetchExerciseCatalogue()', '_exerciseCatalogueOrder'),
    ('Future<Set<String>> fetchOwnedRunIds()', '_runRowsOrder'),
    ('Future<Set<String>> fetchOwnedRouteIds()', '_routeRowsOrder'),
  ]) {
    test('$signature walks $order by keyset cursor', () {
      final b = body(signature);
      expect(b, isNotEmpty, reason: '$signature moved or was renamed');
      expect(b.contains('_walk(\n      $order,') || b.contains('_walk($order,'),
          isTrue,
          reason: '$signature is consumed as a complete list; it must walk '
              'by cursor, not by offset');
      final columns = orderColumns(order);
      expect(columns, isNotEmpty, reason: '$order is not a KeysetKey list');
      // The order must be total, or two rows sharing a sort value straddle a
      // page boundary and the cursor names neither.
      expect(
        RegExp(r"(\.colId|\.colUserId|'id')$").hasMatch(columns.last),
        isTrue,
        reason: '$order ends on ${columns.last}, which is not unique',
      );
    });
  }

  // The foreign-row reconcile (decisions § 1929) deletes a synced local row
  // these sets lack, so each must be the caller's OWN rows, whole: RLS alone
  // also admits club routes and a coach's athletes' runs, and a capped read
  // would delete owned rows past the cap.
  for (final (signature, filter) in const [
    ('Future<Set<String>> fetchOwnedRunIds()', '.eq(RunRow.colUserId, userId)'),
    (
      'Future<Set<String>> fetchOwnedRouteIds()',
      '.eq(RouteRow.colUserId, userId)'
    ),
    (
      'Future<Set<String>> fetchSavedRouteIds()',
      '.eq(SavedRouteRow.colUserId, userId)'
    ),
  ]) {
    test('$signature filters by the caller explicitly', () {
      final b = body(signature);
      expect(b, isNotEmpty, reason: '$signature moved or was renamed');
      expect(b.contains(filter), isTrue,
          reason: 'the owner filter must be explicit, not left to RLS');
      expect(b.contains('.limit('), isFalse,
          reason: 'a capped id set reads as complete and deletes owned rows');
    });
  }

  test('fetchSavedRouteIds walks the bookmark key by cursor', () {
    final b = body('Future<Set<String>> fetchSavedRouteIds()');
    expect(b.contains('_walk(\n      _savedRouteIdOrder,'), isTrue,
        reason: 'fetchBookmarkedRoutes caps at 200; the reconcile needs '
            'every bookmark');
    expect(orderColumns('_savedRouteIdOrder'),
        ['SavedRouteRow.colRouteId'],
        reason: 'route_id is total only under the user_id filter, as the '
            'primary key (user_id, route_id)');
  });
}
