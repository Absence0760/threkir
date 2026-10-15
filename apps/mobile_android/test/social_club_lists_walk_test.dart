import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "My clubs" and a club's pending join requests each read one unranged
/// select: PostgREST caps it at `db.max-rows` (1000) with a 200 and no flag,
/// and nothing in the product bounds how many clubs one user joins or how
/// many requests a request-to-join club accumulates, so past the cap the list
/// rendered as complete and was not. Both walk by keyset cursor now
/// (decisions § 1931); the walk itself is pinned in core_models'
/// `keyset_page_test.dart`. A source guard because the truncation is silent.
void main() {
  final src = File('lib/social_service.dart').readAsStringSync();

  String body(String signature, String endMarker) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(-1), reason: '$signature moved or was renamed');
    final end = src.indexOf(endMarker, start);
    expect(end, greaterThan(start), reason: 're-anchor this guard');
    return src.substring(start, end);
  }

  void expectWalk(String read, String order) {
    expect(read.contains('walkKeyset(\n      $order,'), isTrue,
        reason: 'an unranged select silently truncates at 1000 rows');
    expect(read.contains('q.or(after)'), isTrue,
        reason: 'each page must start after the last row of the previous one');
    expect(read.contains('for (final k in $order)'), isTrue,
        reason: 'the read must sort by the order its cursor is taken in');
    expect(read.contains('.range('), isFalse,
        reason: '.range() is an OFFSET walk, which skips or repeats a row');
  }

  test('fetchMyClubs walks the caller\'s memberships by keyset cursor', () {
    final read = body('Future<List<ClubView>> fetchMyClubs(', 'return _enrichClubs(');
    expectWalk(read, 'myClubMembershipOrder');
    expect(read.contains('joined_at, clubs!inner('), isTrue,
        reason: 'the cursor is read off joined_at, so the select must carry it');
  });

  test('fetchPendingRequests walks the request queue by keyset cursor', () {
    final read = body(
        'Future<List<ClubMemberRow>> fetchPendingRequests(', 'ClubMemberRow.fromJson');
    expectWalk(read, 'pendingRequestOrder');
  });

  test('both orders end on the column the primary key leaves unique', () {
    // club_members is keyed on (club_id, user_id): my clubs fix user_id, so
    // club_id is unique among them; one club's queue fixes club_id, so
    // user_id is.
    expect(
        RegExp(r"myClubMembershipOrder = \[\s*KeysetKey\('joined_at'[^\]]*KeysetKey\('club_id'")
            .hasMatch(src),
        isTrue);
    expect(
        RegExp(r"pendingRequestOrder = \[\s*KeysetKey\('joined_at'[^\]]*KeysetKey\('user_id'")
            .hasMatch(src),
        isTrue);
  });

  test('club enrichment reads the member_count cache and chunks its in filter',
      () {
    // The count was an unranged select over every listed club's roster, capped
    // at 1000 rows in total; the viewer's membership read is now chunked
    // because a walked fetchMyClubs can list more clubs than one in filter
    // carries.
    final read = body('Future<List<ClubView>> _enrichClubs(', 'return [');
    expect(read.contains("select('club_id')"), isFalse,
        reason: 'member counts come from clubs.member_count, not a recount');
    expect(read.contains('readChunked<'), isTrue);
    expect(read.contains(".inFilter('club_id', ids)"), isFalse,
        reason: 'an unchunked in filter past ~100 ids returns empty');
    expect(src.contains('memberCount: clubs[i].memberCount,'), isTrue);
  });
}
