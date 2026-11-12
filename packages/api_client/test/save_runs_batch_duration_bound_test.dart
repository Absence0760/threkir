import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `runs_duration_s_max_check` (20271112000020, decisions § 2359) refuses a
/// run past ten days, and Postgres refuses a multi-row upsert as a whole. A
/// run of 12,333 hours sent in a chunk would fail every run beside it, on every
/// cycle. The batch push parks it before anything is sent, and the rest land.
class _FakePostgrest extends http.BaseClient {
  final List<Map<String, dynamic>> landed = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final isRunWrite = request.url.path.endsWith('/rest/v1/runs') &&
        request.method == 'POST';
    if (!isRunWrite) return _json(const <dynamic>[], 200, request);
    final decoded = jsonDecode((request as http.Request).body);
    final rows = [
      for (final r in decoded is List ? decoded : [decoded])
        Map<String, dynamic>.from(r as Map),
    ];
    if (rows.any((r) => (r['duration_s'] as int) > 864000)) {
      return _json({
        'code': '23514',
        'details': null,
        'hint': null,
        'message': 'new row for relation "runs" violates check constraint '
            '"runs_duration_s_max_check"',
      }, 400, request);
    }
    landed.addAll(rows);
    return _json(const <dynamic>[], 201, request);
  }

  static http.StreamedResponse _json(
          Object payload, int status, http.BaseRequest request) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload))),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
}

Run _run(String id, Duration duration) => Run(
      id: id,
      startedAt: DateTime.utc(2026, 11, 5, 9),
      duration: duration,
      distanceMetres: 2000,
      source: RunSource.app,
    );

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
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  test('an out-of-bound run is parked and the rest of its chunk lands',
      () async {
    final outcome = await api.saveRunsBatch([
      _run('ok-1', const Duration(minutes: 21, seconds: 34)),
      _run('bad', const Duration(hours: 12333, minutes: 21, seconds: 34)),
      _run('ok-2', const Duration(seconds: kMaxRunDurationS - 1)),
    ]);

    expect(outcome.blocked, {'bad': RunPushBlockReason.durationOutOfRange});
    expect(outcome.retryable, isEmpty);
    expect(fake.landed.map((r) => r['id']), unorderedEquals(['ok-1', 'ok-2']));
  });

  test('a batch of only out-of-bound runs sends nothing', () async {
    final outcome = await api.saveRunsBatch([
      _run('bad', const Duration(hours: 241)),
    ]);

    expect(outcome.blocked, {'bad': RunPushBlockReason.durationOutOfRange});
    expect(fake.landed, isEmpty);
  });
}
