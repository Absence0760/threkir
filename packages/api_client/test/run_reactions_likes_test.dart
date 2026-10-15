import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The reaction, comment-like and mention wrappers (decisions § 1971) name
/// their tables, RPCs and filters by hand. The fake sits at the http boundary
/// and answers by path; the PostgREST builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object> bodyByPath = {};
  final Map<String, int> statusByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object body = const <dynamic>[];
    var status = 200;
    for (final e in bodyByPath.entries) {
      if (request.url.path.endsWith(e.key)) body = e.value;
    }
    for (final e in statusByPath.entries) {
      if (request.url.path.endsWith(e.key)) status = e.value;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  Iterable<http.BaseRequest> to(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix));
}

const _reactionSummaryPath = '/rest/v1/rpc/run_reaction_summary';
const _likeSummaryPath = '/rest/v1/rpc/run_comment_like_summary';
const _reactionsPath = '/rest/v1/run_reactions';
const _likesPath = '/rest/v1/run_comment_likes';
const _profilesPath = '/rest/v1/user_profiles';

Future<void> _signIn(SupabaseClient client) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'user-1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

void main() {
  late _FakeHttp fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() async {
    fake = _FakeHttp();
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
    await _signIn(client);
  });

  tearDown(() => client.dispose());

  group('reactions', () {
    test('the summary is read as a GET with the run id and returned row for row',
        () async {
      fake.bodyByPath[_reactionSummaryPath] = [
        {'reaction': 'fire', 'reaction_count': 2, 'viewer_reacted': true},
        {'reaction': 'wave', 'reaction_count': 1, 'viewer_reacted': false},
      ];

      final rows = await api.fetchRunReactionSummary('run-1');

      final req = fake.to(_reactionSummaryPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, {'p_run_id': 'run-1'});
      expect(rows.map((r) => r['reaction']), ['fire', 'wave']);
      expect(rows.first['reaction_count'], 2);
      expect(rows.first['viewer_reacted'], isTrue);
    });

    test('adding a reaction inserts the viewer, run and key and reports a new row',
        () async {
      final added = await api.addRunReaction('run-1', 'fire');

      final req = fake.to(_reactionsPath).single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {
        'user_id': 'user-1',
        'run_id': 'run-1',
        'reaction': 'fire',
      });
      expect(added, isTrue);
    });

    test('adding a reaction the viewer already left is a no-op, not an error',
        () async {
      fake.statusByPath[_reactionsPath] = 409;
      fake.bodyByPath[_reactionsPath] = {
        'code': '23505',
        'message': 'duplicate key value violates unique constraint',
        'details': null,
        'hint': null,
      };

      expect(await api.addRunReaction('run-1', 'fire'), isFalse);
    });

    test('removing a reaction deletes only the viewer\'s row for that key',
        () async {
      fake.bodyByPath[_reactionsPath] = [
        {'user_id': 'user-1'},
      ];

      final removed = await api.removeRunReaction('run-1', 'strong');

      final req = fake.to(_reactionsPath).single;
      expect(req.method, 'DELETE');
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
      expect(req.url.queryParameters['run_id'], 'eq.run-1');
      expect(req.url.queryParameters['reaction'], 'eq.strong');
      expect(removed, isTrue);
    });

    test('removing a reaction that was not there reports nothing removed',
        () async {
      expect(await api.removeRunReaction('run-1', 'strong'), isFalse);
    });
  });

  group('comment likes', () {
    test('the summary is read as a GET and keyed by comment id', () async {
      fake.bodyByPath[_likeSummaryPath] = [
        {'comment_id': 'c1', 'like_count': 3, 'viewer_liked': true},
        {'comment_id': 'c2', 'like_count': 1, 'viewer_liked': false},
      ];

      final likes = await api.fetchRunCommentLikeSummary('run-1');

      final req = fake.to(_likeSummaryPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, {'p_run_id': 'run-1'});
      expect(likes.keys, ['c1', 'c2']);
      expect(likes['c1'], (count: 3, viewerLiked: true));
      expect(likes['c2'], (count: 1, viewerLiked: false));
    });

    test('liking inserts the viewer and comment and reports a new like',
        () async {
      final liked = await api.likeRunComment('c1');

      final req = fake.to(_likesPath).single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'user_id': 'user-1', 'comment_id': 'c1'});
      expect(liked, isTrue);
    });

    test('unliking deletes only the viewer\'s like on that comment', () async {
      fake.bodyByPath[_likesPath] = [
        {'user_id': 'user-1'},
      ];

      final removed = await api.unlikeRunComment('c1');

      final req = fake.to(_likesPath).single;
      expect(req.method, 'DELETE');
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
      expect(req.url.queryParameters['comment_id'], 'eq.c1');
      expect(removed, isTrue);
    });
  });

  group('resolveMentionHandles', () {
    test('looks the handles up lowercased and de-duplicated and maps them to ids',
        () async {
      fake.bodyByPath[_profilesPath] = [
        {'id': 'ana-id', 'handle': 'ana_k'},
        {'id': 'bo-id', 'handle': 'bo_runs'},
      ];

      final ids = await api.resolveMentionHandles(['Ana_K', 'bo_runs', 'ana_k']);

      final req = fake.to(_profilesPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters['handle'], 'in.("ana_k","bo_runs")');
      expect(ids, {'ana_k': 'ana-id', 'bo_runs': 'bo-id'});
    });

    test('no handles makes no request', () async {
      expect(await api.resolveMentionHandles(const []), isEmpty);
      expect(fake.to(_profilesPath), isEmpty);
    });
  });
}
