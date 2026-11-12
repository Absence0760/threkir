import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The phone's run delta keys on the server-stamped `runs.updated_at`
/// (migration 20270918000005, decisions § 2118), not the phone-only
/// `metadata.last_modified_at`, and hands back a cursor read off the rows the
/// server sent — never the device clock. The fake plays PostgREST at the http
/// boundary: it records each request and answers the first page with [pages]
/// in turn, then an empty page, which ends the keyset walk.
class _FakePostgrest extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final List<List<Map<String, dynamic>>> pages = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final reply = pages.isEmpty ? const <dynamic>[] : pages.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Map<String, dynamic> _row(String id, String updatedAt) => {
  'id': id,
  'user_id': 'user-1',
  'started_at': '2024-03-01T07:00:00+00:00',
  'duration_s': 1800,
  'distance_m': 5000,
  'source': 'app',
  'metadata': <String, dynamic>{},
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

  test(
    'filters on updated_at, behind the cursor by the overlap, owner-scoped',
    () async {
      final cursor = DateTime.utc(2025, 6, 18, 12);
      await api.getRunsModifiedSince(cursor);

      final first = fake.requests.first.url.queryParameters;
      expect(first['user_id'], 'eq.user-1');
      expect(
        first['updated_at'],
        'gt.${cursor.subtract(ApiClient.runsDeltaOverlap).toIso8601String()}',
        reason:
            'a write that commits after a later-starting one carries a stamp '
            'below the cursor; the overlap is what still reads it',
      );
      expect(
        first.containsKey('metadata->>last_modified_at'),
        isFalse,
        reason: 'the phone-only stamp misses every edit made off the phone',
      );
      expect(
        first['order'],
        startsWith('updated_at.asc'),
        reason: 'the cursor is the last row, so the walk must be oldest-first',
      );
    },
  );

  test(
    'the cursor is the newest server updated_at, not the device clock',
    () async {
      fake.pages.add([
        _row('a', '2025-06-18T09:00:00.000001+00:00'),
        _row('b', '2025-06-18T10:15:30.123456+00:00'),
      ]);
      final before = DateTime.now().toUtc();
      final delta = await api.getRunsModifiedSince(
        DateTime.utc(2025, 6, 18, 8),
      );

      expect(delta.runs.map((r) => r.id), ['a', 'b']);
      expect(delta.cursor, DateTime.utc(2025, 6, 18, 10, 15, 30, 123, 456));
      expect(
        delta.cursor!.isBefore(before),
        isTrue,
        reason:
            'a device-clock cursor would read as now, and a phone running '
            'fast would skip every write stamped before its own clock',
      );
    },
  );

  test(
    'pages past a tie by (updated_at, id), not by updated_at alone',
    () async {
      fake.pages.add([
        _row('a', '2025-06-18T10:00:00+00:00'),
        _row('b', '2025-06-18T10:00:00+00:00'),
      ]);
      await api.getRunsModifiedSince(DateTime.utc(2025, 6, 18, 8));

      expect(fake.requests, hasLength(greaterThanOrEqualTo(2)));
      final after = fake.requests[1].url.queryParameters['or'] ?? '';
      expect(after, contains('updated_at.gt.'));
      expect(
        after,
        contains('id.gt."b"'),
        reason:
            'one statement stamps all its rows with one now(); a plain '
            'updated_at > cursor would skip the rest of the tie',
      );
    },
  );

  test(
    'a null cursor walks every owned row, with no updated_at filter',
    () async {
      fake.pages.add([_row('a', '2025-06-18T09:00:00+00:00')]);
      final delta = await api.getRunsModifiedSince(null);

      final first = fake.requests.first.url.queryParameters;
      expect(first['user_id'], 'eq.user-1');
      expect(first.containsKey('updated_at'), isFalse);
      expect(delta.cursor, DateTime.utc(2025, 6, 18, 9));
    },
  );

  test('no rows leaves the cursor where it was', () async {
    final cursor = DateTime.utc(2025, 6, 18, 12);
    final delta = await api.getRunsModifiedSince(cursor);
    expect(delta.runs, isEmpty);
    expect(delta.cursor, cursor);
  });
}
