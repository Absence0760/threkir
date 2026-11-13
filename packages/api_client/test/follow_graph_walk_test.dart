import 'dart:convert';

import 'package:api_client/api_client.dart';
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
    // A server capping every page below the ask answers short pages that are
    // not the end; the walk keeps going until a page is shorter than the one
    // before it.
    fake.pages['followee_id']!.addAll([
      [_edge('follower_id', 'f1', 59), _edge('follower_id', 'f2', 58)],
      [_edge('follower_id', 'f3', 57), _edge('follower_id', 'f4', 56)],
      [_edge('follower_id', 'f5', 55)],
    ]);
    fake.pages['follower_id']!.addAll([
      [_edge('followee_id', 'g1', 50), _edge('followee_id', 'g2', 49)],
      [_edge('followee_id', 'g3', 48)],
    ]);

    final graph = await api.fetchFollowGraph('me');

    expect(graph.followers.map((p) => p.id), ['f1', 'f2', 'f3', 'f4', 'f5']);
    expect(graph.following.map((p) => p.id), ['g1', 'g2', 'g3']);

    final inbound = edgeReads('followee_id');
    expect(inbound, hasLength(3));
    expect(inbound.first.url.queryParameters['followee_id'], 'eq.me');
    expect(inbound.first.url.queryParameters.containsKey('or'), isFalse);
    expect(
      inbound[1].url.queryParameters['or'],
      contains('f2'),
      reason: 'each page must start strictly after the last edge read',
    );
    expect(
      inbound.first.url.queryParameters['order'],
      startsWith('followed_at.desc'),
    );
    expect(
      edgeReads('follower_id').first.url.queryParameters['follower_id'],
      'eq.me',
    );
  });

  test('fetchAllFollowing walks only the outbound direction', () async {
    fake.pages['follower_id']!.addAll([
      [_edge('followee_id', 'g1', 50), _edge('followee_id', 'g2', 49)],
      [_edge('followee_id', 'g3', 48)],
    ]);
    final following = await api.fetchAllFollowing('me');
    expect(following.map((p) => p.id), ['g1', 'g2', 'g3']);
    expect(edgeReads('followee_id'), isEmpty);
  });

  test('a page that fails mid-walk fails the graph, not shortens it', () async {
    fake.pages['follower_id']!.add([_edge('followee_id', 'g1', 50)]);
    fake.failing.add('followee_id');
    await expectLater(api.fetchFollowGraph('me'), throwsA(anything));
  });

  test(
    'a server that stops advancing fails the walk instead of looping',
    () async {
      fake.stuck['follower_id'] = [
        _edge('followee_id', 'g1', 50),
        _edge('followee_id', 'g2', 49),
      ];
      await expectLater(api.fetchAllFollowing('me'), throwsStateError);
    },
  );
}
