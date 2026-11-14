import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The feed, lift and badge reads scope themselves to everyone the viewer
/// follows. They read that set in one unranged select, which PostgREST stops
/// at `db.max-rows` with a 200 and no flag: a runner following more people
/// than the cap lost everyone past it from all three feeds. They now walk the
/// outbound edges by keyset cursor (`_walkFolloweeIds`, mirroring web
/// `walkFollowEdges`). The fake plays PostgREST at the http boundary:
/// `user_follows` answers from a queue of pages, every other table answers
/// empty, and each request is recorded so the tests can read which author ids
/// reached the feed queries.
class _FakePostgrest extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final followPages = <List<Map<String, dynamic>>>[];

  /// The follow page at this index (0-based) fails with a 500.
  int? failAt;
  var _followReads = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object reply = const <dynamic>[];
    var status = 200;
    if (request.url.path.endsWith('/user_follows')) {
      final index = _followReads++;
      if (index == failAt) {
        status = 500;
        reply = {'message': 'boom', 'code': 'XX000'};
      } else if (followPages.isNotEmpty) {
        reply = followPages.removeAt(0);
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// Followee edges `g<from>` .. `g<from + count - 1>`, newest follow first.
List<Map<String, dynamic>> _edges(int from, int count) => [
  for (var i = from; i < from + count; i++)
    {
      'followee_id': 'g$i',
      'followed_at': DateTime.utc(
        2026,
        3,
        1,
      ).subtract(Duration(seconds: i)).toIso8601String(),
    },
];

void main() {
  late _FakePostgrest fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() async {
    fake = _FakePostgrest();
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'fake-token',
        'token_type': 'bearer',
        'user': {
          'id': 'me',
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  List<http.BaseRequest> followReads() => [
    for (final r in fake.requests)
      if (r.url.path.endsWith('/user_follows')) r,
  ];

  /// Every author id the requests to [table] were scoped to, across chunks.
  List<String> authorsQueried(String table) => [
    for (final r in fake.requests)
      if (r.url.path.endsWith('/$table'))
        ...RegExp(r'[\w-]+')
            .allMatches(
              r.url.queryParameters['user_id']!.replaceFirst('in.', ''),
            )
            .map((m) => m.group(0)!),
  ];

  final all = [for (var i = 0; i < 1003; i++) 'g$i'];

  group('the badge feed walks the follow list', () {
    test('past the first page, cursor after the last edge read', () async {
      fake.followPages.addAll([_edges(0, 1000), _edges(1000, 3)]);

      await api.fetchFollowingBadgeAwards();

      final reads = followReads();
      expect(reads, hasLength(2));
      final first = reads.first.url.queryParameters;
      expect(first['follower_id'], 'eq.me');
      expect(first['limit'], '$kKeysetWalkPageSize');
      expect(
        first['order'],
        'followed_at.desc.nullsfirst,'
        'followee_id.desc.nullsfirst',
      );
      expect(first.containsKey('or'), isFalse);
      expect(
        reads[1].url.queryParameters['or'],
        contains('g999'),
        reason: 'the next page starts strictly after the last edge read',
      );
      expect(
        authorsQueried('achievements')..sort(),
        [...all]..sort(),
        reason: 'everyone past the first page must reach the badge read',
      );
    });

    test('an exact multiple of the page size ends on the empty page', () async {
      fake.followPages.addAll([_edges(0, 1000), const []]);
      await api.fetchFollowingBadgeAwards();
      expect(followReads(), hasLength(2));
      expect(authorsQueried('achievements'), hasLength(1000));
    });

    test('a viewer who follows nobody gets nothing, in one read', () async {
      expect(await api.fetchFollowingBadgeAwards(), isEmpty);
      expect(followReads(), hasLength(1));
      expect(authorsQueried('achievements'), isEmpty);
    });

    test('a follow list shorter than the cap is read whole in one request',
        () async {
      // The server returns min(ask, db.max-rows) rows while it has them, and
      // the declared cap is the ask, so a short page is the end of the list.
      fake.followPages.addAll([_edges(0, 3), _edges(3, 3)]);
      await api.fetchFollowingBadgeAwards();
      expect(followReads(), hasLength(1));
      expect(authorsQueried('achievements'), hasLength(3));
    });

    test(
      'a page that fails mid-walk fails the read, not shortens it',
      () async {
        fake.followPages.add(_edges(0, 1000));
        fake.failAt = 1;
        await expectLater(api.fetchFollowingBadgeAwards(), throwsA(anything));
        expect(
          authorsQueried('achievements'),
          isEmpty,
          reason: 'a partial follow set must not be read as the whole one',
        );
      },
    );

    test('the author filter finds a followee past the first page', () async {
      fake.followPages.addAll([_edges(0, 1000), _edges(1000, 3)]);
      await api.fetchFollowingBadgeAwards(authorId: 'g1002');
      expect(authorsQueried('achievements'), ['g1002']);
    });
  });

  test('no follow-list read in the client is a single unranged select', () {
    // Every `user_follows` chain is a write, a count, a one-edge probe, a
    // chunked membership check, a cursor page, or the walk. A new list read
    // written as one select is the bug this file pins, back again.
    final src = File('lib/src/api_client.dart').readAsStringSync();
    String body(String signature) {
      final start = src.indexOf(signature);
      expect(start, greaterThanOrEqualTo(0), reason: '$signature moved');
      return src.substring(start, src.indexOf('\n  }\n', start));
    }

    final walk = body('Future<List<String>> _walkFolloweeIds(');
    expect(walk, contains('_walk(\n      _followingOrder,'));
    final paged = [
      walk,
      body('Future<KeysetPage<UserProfileRow>> _followPage('),
    ];
    final unranged = <String>[];
    for (final m in RegExp(r'\.from\(UserFollowRow\.table\)').allMatches(src)) {
      final end = src.indexOf(';', m.start);
      final chain = src.substring(m.start, end);
      if (paged.any((b) => b.contains(chain))) continue;
      if (RegExp(r'\.(delete|count|maybeSingle|inFilter)\(').hasMatch(chain)) {
        continue;
      }
      unranged.add(chain);
    }
    expect(
      unranged,
      isEmpty,
      reason:
          'read the follow list with _walkFolloweeIds or the paged '
          'readers; one select stops at db.max-rows without saying so',
    );
  });

  group('the activity feed walks the follow list', () {
    test('once per page, and both branches see every followee', () async {
      fake.followPages.addAll([_edges(0, 1000), _edges(1000, 3)]);

      await api.fetchFollowingActivityFeed();

      expect(
        followReads(),
        hasLength(2),
        reason: 'the runs and lifts branches share one resolved set',
      );
      expect(authorsQueried('public_runs')..sort(), [...all]..sort());
      expect(authorsQueried('public_gym_workouts')..sort(), [...all]..sort());
    });

    test('the run feed alone walks it too', () async {
      fake.followPages.addAll([_edges(0, 1000), _edges(1000, 3)]);
      await api.fetchFollowingFeed();
      expect(followReads(), hasLength(2));
      expect(authorsQueried('public_runs'), hasLength(1003));
    });

    test('a failed page fails the feed instead of thinning it', () async {
      fake.followPages.add(_edges(0, 1000));
      fake.failAt = 1;
      await expectLater(api.fetchFollowingActivityFeed(), throwsA(anything));
      expect(authorsQueried('public_runs'), isEmpty);
      expect(authorsQueried('public_gym_workouts'), isEmpty);
    });

    test('an author past the first page narrows the feed to them', () async {
      fake.followPages.addAll([_edges(0, 1000), _edges(1000, 3)]);
      await api.fetchFollowingActivityFeed(authorId: 'g1001');
      expect(authorsQueried('public_runs'), ['g1001']);
      expect(authorsQueried('public_gym_workouts'), ['g1001']);
    });

    test('a stranger as the author filter reads no feed at all', () async {
      fake.followPages.add(_edges(0, 3));
      expect(
        await api.fetchFollowingActivityFeed(authorId: 'stranger'),
        isEmpty,
      );
      expect(authorsQueried('public_runs'), isEmpty);
    });
  });
}
