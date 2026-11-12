import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// fetchIncomingFollowRequests reads up to 200 requests, so its requester
/// profile join is longer than kInFilterChunk on a busy account. The fake
/// sits at the http boundary; the PostgREST builders above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object Function(http.BaseRequest)> bodyByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object body = const <dynamic>[];
    for (final e in bodyByPath.entries) {
      if (request.url.path.endsWith(e.key)) body = e.value(request);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  Iterable<http.BaseRequest> to(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix));
}

const _requestsPath = '/rest/v1/follow_requests';
const _profilesPath = '/rest/v1/user_profiles';

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
    await client.auth.setInitialSession(jsonEncode({
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
  });

  tearDown(() => client.dispose());

  test('more requesters than kInFilterChunk are joined in bounded chunks',
      () async {
    const total = 150;
    fake.bodyByPath[_requestsPath] = (_) => [
          for (var i = 0; i < total; i++)
            {
              'requester_id': 'r$i',
              'target_id': 'user-1',
              'requested_at': '2026-01-01T00:00:00Z',
            },
        ];
    fake.bodyByPath[_profilesPath] = (req) {
      final inList = req.url.queryParameters['id']!;
      final ids = inList
          .substring('in.('.length, inList.length - 1)
          .split(',')
          .map((s) => s.replaceAll('"', ''));
      return [
        for (final id in ids)
          {'id': id, 'display_name': 'Runner $id', 'avatar_url': null},
      ];
    };

    final requests = await api.fetchIncomingFollowRequests();

    final joins = fake.to(_profilesPath).toList();
    expect(
      [for (final r in joins) r.url.queryParameters['id']!.split(',').length],
      [kInFilterChunk, total - kInFilterChunk],
    );
    expect(requests, hasLength(total));
    expect(requests.first.requester.id, 'r0');
    expect(requests.last.requester.displayName, 'Runner r${total - 1}');
  });

  test('no requests makes no profile read', () async {
    expect(await api.fetchIncomingFollowRequests(), isEmpty);
    expect(fake.to(_profilesPath), isEmpty);
  });
}
