import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// A run's `event_id` is an L4 link on an L1 write. When the event is deleted
/// between a watch's Arm and the run's sync, `runs_event_id_fkey` refuses the
/// whole row with 23503; the run must still land, without the link, and a
/// refusal of anything else must not cost the run its link.
///
/// The fake sits at the http boundary and plays Postgres: a `runs` write whose
/// body names an event in [deadEvents] is refused with the real PostgREST
/// error shape, which is everything above it (PostgREST builders, ApiClient)
/// running as real code.
class _FakePostgrest extends http.BaseClient {
  final Set<String> deadEvents = {};
  Map<String, dynamic>? otherError;
  final List<List<Map<String, dynamic>>> runWrites = [];
  final List<List<Map<String, dynamic>>> landed = [];

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
    runWrites.add(rows);
    if (otherError != null) return _json(otherError!, 400, request);
    final dead = rows
        .map((r) => r['event_id'])
        .whereType<String>()
        .where(deadEvents.contains)
        .toList();
    if (dead.isNotEmpty) {
      return _json({
        'code': '23503',
        'details': 'Key (event_id)=(${dead.first}) is not present in table '
            '"events".',
        'hint': null,
        'message': 'insert or update on table "runs" violates foreign key '
            'constraint "runs_event_id_fkey"',
      }, 409, request);
    }
    landed.add(rows);
    return _json(const <dynamic>[], 201, request);
  }

  List<Map<String, dynamic>> get landedRows => landed.expand((c) => c).toList();

  static http.StreamedResponse _json(
          Object payload, int status, http.BaseRequest request) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload))),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
}

Run _run(String id, {String? eventId}) => Run(
      id: id,
      startedAt: DateTime.utc(2026, 9, 20, 7),
      duration: const Duration(minutes: 30),
      distanceMetres: 5000,
      source: RunSource.watch,
      metadata: {
        if (eventId != null) MetadataKeys.eventId: eventId,
      },
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

  group('saveRun', () {
    test('a run whose event was deleted lands once, without the link',
        () async {
      fake.deadEvents.add('event-gone');

      await api.saveRun(_run('run-1', eventId: 'event-gone'));

      expect(fake.runWrites, hasLength(2));
      expect(fake.runWrites.first.single['event_id'], 'event-gone');
      expect(fake.landedRows, hasLength(1));
      expect(fake.landedRows.single['id'], 'run-1');
      expect(fake.landedRows.single.containsKey('event_id'), isFalse);
    });

    test('a live event keeps its link and costs one request', () async {
      await api.saveRun(_run('run-1', eventId: 'event-live'));

      expect(fake.runWrites, hasLength(1));
      expect(fake.landedRows.single['event_id'], 'event-live');
    });

    test('a refusal of anything else propagates and never drops the link',
        () async {
      fake.otherError = {
        'code': '23514',
        'details': null,
        'hint': null,
        'message': 'new row for relation "runs" violates check constraint '
            '"runs_distance_m_check"',
      };

      await expectLater(
        api.saveRun(_run('run-1', eventId: 'event-live')),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', '23514')),
      );
      expect(fake.runWrites, hasLength(1));
      expect(fake.runWrites.single.single['event_id'], 'event-live');
    });

    test('a 23503 on another foreign key propagates and keeps the link',
        () async {
      fake.otherError = {
        'code': '23503',
        'details': 'Key (route_id)=(route-gone) is not present in table '
            '"routes".',
        'hint': null,
        'message': 'insert or update on table "runs" violates foreign key '
            'constraint "runs_route_id_fkey"',
      };

      await expectLater(
        api.saveRun(_run('run-1', eventId: 'event-live')),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', '23503')),
      );
      expect(fake.runWrites, hasLength(1));
      expect(fake.landedRows, isEmpty);
    });
  });

  group('saveRunsBatch', () {
    test('only the run whose event is gone loses its link', () async {
      fake.deadEvents.add('event-gone');

      await api.saveRunsBatch([
        _run('run-plain'),
        _run('run-live', eventId: 'event-live'),
        _run('run-dead', eventId: 'event-gone'),
      ]);

      final byId = {for (final r in fake.landedRows) r['id']: r};
      expect(byId.keys, unorderedEquals(['run-plain', 'run-live', 'run-dead']));
      expect(byId['run-plain']!.containsKey('event_id'), isFalse);
      expect(byId['run-live']!['event_id'], 'event-live');
      expect(byId['run-dead']!.containsKey('event_id'), isFalse);
    });

    test('a refusal of anything else fails the batch with every link intact',
        () async {
      fake.otherError = {
        'code': '42501',
        'details': null,
        'hint': null,
        'message': 'new row violates row-level security policy for table '
            '"runs"',
      };

      await expectLater(
        api.saveRunsBatch([
          _run('run-live', eventId: 'event-live'),
          _run('run-plain'),
        ]),
        throwsA(isA<PostgrestException>()),
      );
      expect(fake.runWrites, hasLength(1));
      expect(fake.runWrites.single.first['event_id'], 'event-live');
    });
  });
}
