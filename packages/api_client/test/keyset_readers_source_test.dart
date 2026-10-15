import 'dart:io';

import 'package:test/test.dart';

/// Pins the mobile load-more readers to keyset (cursor) paging.
///
/// An offset is a position: a row deleted between two reads moves every later
/// row up one, and the next offset then starts a row late, so a row is never
/// shown. Each reader below takes the previous page's cursor (`after`), builds
/// its filter with `keysetAfter` and hands back `nextCursor` — the same shape
/// as web's `core/keyset_readers.test.ts`. A source guard rather than a wire
/// test because the regression is static; the paging property itself is pinned
/// against in-memory rows by core_models' `keyset_page_test.dart` and against
/// the live stack by `api_client_integration_test.dart`.
void main() {
  final src = File('lib/src/api_client.dart').readAsStringSync();

  /// The member from its declaration to the next member's doc comment.
  String body(String signature) {
    final start = src.indexOf(signature);
    if (start < 0) return '';
    final end = src.indexOf('\n  /// ', start);
    return src.substring(start, end == -1 ? src.length : end);
  }

  final followPage = body('Future<KeysetPage<UserProfileRow>> _followPage(');

  for (final reader in ['fetchFollowers(', 'fetchFollowing(']) {
    test('$reader takes a cursor and pages through _followPage', () {
      final fn = body('Future<KeysetPage<UserProfileRow>> $reader');
      expect(fn, isNotEmpty, reason: 'the reader moved or was renamed');
      expect(fn.contains('List<Object?>? after'), isTrue,
          reason: 'the reader must take the previous page\'s cursor');
      expect(fn.contains('_followPage('), isTrue);
      expect(fn.contains('offset'), isFalse,
          reason: 'the reader must not page by offset');
    });
  }

  test('searchPublicRoutes reads the view by cursor, not the offset RPC', () {
    final fn = body('Future<KeysetPage<Route>> searchPublicRoutes(');
    expect(fn, isNotEmpty, reason: 'the reader moved or was renamed');
    expect(fn.contains('List<Object?>? after'), isTrue);
    expect(fn.contains('keysetAfter(order, after)'), isTrue);
    expect(fn.contains('nextCursor(order, rows, limit)'), isTrue);
    expect(fn.contains('p_offset'), isFalse,
        reason: 'search_public_routes pages by offset; the view is read '
            'directly so the page can start after a cursor');
    expect(fn.contains('offset'), isFalse);
  });

  test('_followPage filters after the cursor and returns the next one', () {
    expect(followPage, isNotEmpty, reason: '_followPage moved or was renamed');
    expect(followPage.contains('keysetAfter(order, after)'), isTrue);
    expect(followPage.contains('nextCursor(order, edges, limit)'), isTrue,
        reason: 'the cursor must come from the last EDGE read');
    expect(followPage.contains('.range('), isFalse);
  });
}
