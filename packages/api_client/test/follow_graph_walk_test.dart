import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The pickers that filter the viewer's follow graph on the client (New
/// message, Send route, group people, share audience, the feed's author
/// filter) read it whole: one page hid everyone past it from the list and
/// from its search (decisions § 2507). The fake plays PostgREST at the http
/// boundary. `user_follows` answers each direction from its own queue of
/// pages; `user_profiles` answers every id it is asked for.
class _FakePostgrest extends http.BaseClient {
  final requests = <http.BaseRequest>[];

  /// Pages of edge rows, keyed by the anchor filter (`follower_id` for the
  /// people the viewer follows, `followee_id` for their followers).
  final Map<String, List<List<Map<String, dynamic>>>> pages = {
    'follower_id': [],
    'followee_id': [],
  };

  /// A direction whose every page answers this one forever (a server that
  /// ignores the cursor).
  final Map<String, List<Map<String, dynamic>>> stuck = {};

  /// A direction whose next page fails.
  final Set<String> failing = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final url = request.url;
    Object reply = const <dynamic>[];
    var status = 200;
    if (url.path.endsWith('/user_follows')) {
      final anchor = url.queryParameters.containsKey('follower_id')
          ? 'follower_id'
          : 'followee_id';
      if (failing.contains(anchor)) {
        status = 500;
        reply = {'message': 'boom', 'code': 'XX000'};
      } else if (stuck[anchor] != null) {
        reply = stuck[anchor]!;
      } else {
        final queue = pages[anchor]!;
        reply = queue.isEmpty ? const <dynamic>[] : queue.removeAt(0);
      }
    } else if (url.path.endsWith('/user_profiles')) {
      final ids = RegExp(r'[\w-]+')
          .allMatches(url.queryParameters['id']!.replaceFirst('in.', ''))
          .map((m) => m.group(0)!);
      reply = [
        for (final id in ids)
          {
            'id': id,
            'display_name': 'Name $id',
            'avatar_url': null,
            'created_at': '2026-01-01T00:00:00Z',
          },
      ];
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Map<String, dynamic> _edge(String column, String id, int minute) => {
  column: id,
  'followed_at': '2026-03-01T07:${minute.toString().padLeft(2, '0')}:00+00:00',
};

/// Edge rows [from] .. [from] + [count] - 1, newest first, ids `<prefix><n>`.
List<Map<String, dynamic>> _page(
  String column,
  String prefix,
  int from,
  int count,
) => [
  for (var i = from; i < from + count; i++)
    {
      column: '$prefix$i',
      'followed_at': DateTime.utc(2026, 3, 1)
          .subtract(Duration(minutes: i))
          .toIso8601String(),
    },
];

UserProfileRow _profile(String id) => UserProfileRow.fromJson({
  'id': id,
  'display_name': id,
  'avatar_url': null,
  'created_at': '2026-01-01T00:00:00Z',
});

/// The shape of a widget-test fake: the page methods overridden, nothing
/// else. Followers come in two pages joined by a cursor.
class _PagedApi extends ApiClient {
  _PagedApi(SupabaseClient client) : super.withClient(client);

  final followerAfters = <List<Object?>?>[];
  final followingAfters = <List<Object?>?>[];

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 100,
    List<Object?>? after,
  }) async {
    followerAfters.add(after);
    return after == null
        ? KeysetPage([_profile('a'), _profile('b')], const ['b'])
        : KeysetPage([_profile('c')], null);
  }

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 100,
    List<Object?>? after,
  }) async {
    followingAfters.add(after);
    return KeysetPage([_profile('x')], null);
  }
}

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

  List<http.BaseRequest> edgeReads(String anchor) => [
    for (final r in fake.requests)
      if (r.url.path.endsWith('/user_follows') &&
          r.url.queryParameters.containsKey(anchor))
        r,
  ];

  test('walks both directions past the first page, in edge order', () async {
    // A full page hands back a cursor and the walk asks for the rows after
    // it; a short page is the end.
    fake.pages['followee_id']!.addAll([
      _page('follower_id', 'f', 0, 100),
      _page('follower_id', 'f', 100, 3),
    ]);
    fake.pages['follower_id']!.addAll([
      _page('followee_id', 'g', 0, 100),
      _page('followee_id', 'g', 100, 1),
    ]);

    final graph = await api.fetchFollowGraph('me');

    expect(graph.followers.map((p) => p.id), [
      for (var i = 0; i < 103; i++) 'f$i',
    ]);
    expect(graph.following.map((p) => p.id), [
      for (var i = 0; i < 101; i++) 'g$i',
    ]);

    final inbound = edgeReads('followee_id');
    expect(inbound, hasLength(2));
    expect(inbound.first.url.queryParameters['followee_id'], 'eq.me');
    expect(inbound.first.url.queryParameters['limit'], '100');
    expect(inbound.first.url.queryParameters.containsKey('or'), isFalse);
    expect(
      inbound[1].url.queryParameters['or'],
      contains('f99'),
      reason: 'each page must start strictly after the last edge read',
    );
    expect(
      inbound.first.url.queryParameters['order'],
      startsWith('followed_at.desc'),
    );
    expect(edgeReads('follower_id'), hasLength(2));
    expect(
      edgeReads('follower_id').first.url.queryParameters['follower_id'],
      'eq.me',
    );
  });

  test('a short first page is the whole list, read once', () async {
    fake.pages['follower_id']!.add(_page('followee_id', 'g', 0, 2));
    final following = await api.fetchAllFollowing('me');
    expect(following.map((p) => p.id), ['g0', 'g1']);
    expect(edgeReads('follower_id'), hasLength(1));
  });

  test('fetchAllFollowing walks only the outbound direction', () async {
    fake.pages['follower_id']!.addAll([
      _page('followee_id', 'g', 0, 100),
      _page('followee_id', 'g', 100, 1),
    ]);
    final following = await api.fetchAllFollowing('me');
    expect(following, hasLength(101));
    expect(edgeReads('followee_id'), isEmpty);
  });

  test('the walk reads through the public page methods, so a fake of them '
      'fakes the graph', () async {
    // A widget test fakes fetchFollowers / fetchFollowing; the graph must
    // come from those pages and never reach the network behind them.
    final paged = _PagedApi(client);
    final graph = await paged.fetchFollowGraph('me');
    expect(graph.followers.map((p) => p.id), ['a', 'b', 'c']);
    expect(graph.following.map((p) => p.id), ['x']);
    expect(paged.followerAfters, [
      null,
      ['b'],
    ]);
    expect(paged.followingAfters, [null]);
    expect(fake.requests, isEmpty);
  });

  test('a page that fails mid-walk fails the graph, not shortens it', () async {
    fake.pages['follower_id']!.add([_edge('followee_id', 'g1', 50)]);
    fake.failing.add('followee_id');
    await expectLater(api.fetchFollowGraph('me'), throwsA(anything));
  });

  test(
    'a server that stops advancing fails the walk instead of looping',
    () async {
      fake.stuck['follower_id'] = _page('followee_id', 'g', 0, 100);
      await expectLater(api.fetchAllFollowing('me'), throwsStateError);
    },
  );
}
