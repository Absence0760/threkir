import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// A pending run edit is pushed as a compare-and-swap on the server
/// `updated_at` it was made on (decisions § 2147): only the changed columns,
/// filtered on the id AND the base, which travels back to the server exactly
/// as the server sent it. The fake plays PostgREST at the http boundary.
class _FakePostgrest extends http.BaseClient {
  final requests = <http.Request>[];
  final List<List<Map<String, dynamic>>> replies = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) requests.add(request);
    final reply = replies.isEmpty ? const <dynamic>[] : replies.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

const _base = '2026-09-02T08:15:30.123456+00:00';

Map<String, dynamic> _row({
  String updatedAt = _base,
  Map<String, dynamic> metadata = const {'title': 'Tempo'},
}) => {
  'id': 'run-1',
  'user_id': 'user-1',
  'started_at': '2026-09-01T07:00:00+00:00',
  'duration_s': 1800,
  'distance_m': 5000,
  'source': 'app',
  'metadata': metadata,
  'activity_type': 'run',
  'is_dnf': false,
  'updated_at': updatedAt,
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
          'id': 'user-1',
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

  Run edited() => ApiClient.debugRunFromRow(
    _row(metadata: {'title': 'Phone title', 'notes': 'kept'}),
  );

  test('a read keeps the server updated_at string, microseconds and all', () {
    final run = ApiClient.debugRunFromRow(_row());
    expect(
      serverUpdatedAtOf(run),
      _base,
      reason:
          'the base is sent back for an equality match, so it must be '
          'the server\'s own string, not a re-formatted DateTime',
    );
  });

  test('filters on id, owner and the exact base; sends only the changed '
      'columns', () async {
    fake.replies.add([_row(updatedAt: '2026-09-02T08:20:00.000001+00:00')]);
    await api.updateRunFieldsIfUnchanged(
      edited(),
      fields: {RunEditField.metadata('title')},
      baseUpdatedAt: _base,
    );

    final req = fake.requests.single;
    expect(req.method, 'PATCH');
    final q = req.url.queryParameters;
    expect(q['id'], 'eq.run-1');
    expect(q['user_id'], 'eq.user-1');
    expect(q['updated_at'], 'eq.$_base');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(
      body.keys,
      ['metadata'],
      reason:
          'a title edit must not write duration, distance or any '
          'other column another device may have changed',
    );
    expect(body['metadata'], {
      'title': 'Phone title',
      'notes': 'kept',
    }, reason: 'the base stash never reaches the persisted bag');
  });

  test(
    'a returned row is the landed edit, with the server\'s new stamp',
    () async {
      fake.replies.add([_row(updatedAt: '2026-09-02T08:20:00.000001+00:00')]);
      final landed = await api.updateRunFieldsIfUnchanged(
        edited(),
        fields: {RunEditField.metadata('title')},
        baseUpdatedAt: _base,
      );
      expect(landed, isNotNull);
      expect(serverUpdatedAtOf(landed!), '2026-09-02T08:20:00.000001+00:00');
    },
  );

  test('zero rows means the row moved: null, nothing adopted', () async {
    fake.replies.add([]);
    final landed = await api.updateRunFieldsIfUnchanged(
      edited(),
      fields: {RunEditField.metadata('title')},
      baseUpdatedAt: _base,
    );
    expect(landed, isNull);
  });

  test('a null base matches only a row with no stamp', () async {
    fake.replies.add([]);
    await api.updateRunFieldsIfUnchanged(
      edited(),
      fields: {RunEditField.metadata('title')},
      baseUpdatedAt: null,
    );
    expect(fake.requests.single.url.queryParameters['updated_at'], 'is.null');
  });
}
