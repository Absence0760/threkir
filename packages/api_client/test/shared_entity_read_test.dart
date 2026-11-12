import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The phone's recipient read of a run or route shared through an audience
/// (decisions § 1874): public first, then the `shared_*` view for a signed-in
/// caller only, never the base table, and the route polyline always from
/// `clip_route_for_viewer`. The fake sits at the http boundary and answers per
/// relation; the PostgREST builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object> bodies = {};
  final Map<String, int> statuses = {};

  List<String> get paths => [for (final r in requests) r.url.path];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final path = request.url.path;
    final key = bodies.keys.firstWhere(path.endsWith, orElse: () => '');
    final body = key.isEmpty ? const <dynamic>[] : bodies[key]!;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      statuses[key] ?? 200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Map<String, dynamic> _runRow() => {
      'id': 'run-1',
      'user_id': 'owner-1',
      'started_at': '2026-10-01T07:00:00Z',
      'duration_s': 1800,
      'distance_m': 5000,
      'source': 'app',
      'activity_type': 'run',
      'is_dnf': false,
      'is_public': false,
      'has_track': true,
      'metadata': <String, dynamic>{},
      'created_at': '2026-10-01T07:31:00Z',
    };

Map<String, dynamic> _routeRow() => {
      'id': 'route-1',
      'user_id': 'owner-1',
      'name': 'River loop',
      'distance_m': 8000,
      'elevation_m': 40,
      'is_public': false,
      'created_at': '2026-10-01T07:00:00Z',
    };

Future<void> _signIn(SupabaseClient client) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'viewer-1',
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

  setUp(() {
    fake = _FakeHttp();
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  group('fetchViewableRunById', () {
    test('a public run is returned unshared and shared_runs is not asked',
        () async {
      await _signIn(client);
      fake.bodies['/rest/v1/public_runs'] = [
        {..._runRow(), 'is_public': true},
      ];

      final res = await api.fetchViewableRunById('run-1');

      expect(res.row?.id, 'run-1');
      expect(res.shared, isFalse);
      expect(fake.paths.any((p) => p.endsWith('/shared_runs')), isFalse);
    });

    test('a run shared with the signed-in caller comes from shared_runs',
        () async {
      await _signIn(client);
      fake.bodies['/rest/v1/shared_runs'] = [_runRow()];

      final res = await api.fetchViewableRunById('run-1');

      expect(res.row?.id, 'run-1');
      expect(res.row?.userId, 'owner-1');
      expect(res.shared, isTrue);
      expect(fake.paths.where((p) => p.endsWith('/rest/v1/runs')), isEmpty,
          reason: 'a non-owner never reads the base runs table');
    });

    test('a signed-out caller stops at public', () async {
      fake.bodies['/rest/v1/shared_runs'] = [_runRow()];

      final res = await api.fetchViewableRunById('run-1');

      expect(res.row, isNull);
      expect(res.shared, isFalse);
      expect(fake.paths.any((p) => p.endsWith('/shared_runs')), isFalse);
    });

    test('nothing shared (or the gate closed) answers no run', () async {
      await _signIn(client);

      final res = await api.fetchViewableRunById('run-1');

      expect(res.row, isNull);
      expect(res.shared, isFalse);
    });

    test('a failed shared read throws instead of answering not shared',
        () async {
      await _signIn(client);
      fake.bodies['/rest/v1/shared_runs'] = {
        'code': 'XX000',
        'message': 'upstream failed',
      };
      fake.statuses['/rest/v1/shared_runs'] = 502;

      expect(api.fetchViewableRunById('run-1'), throwsA(anything));
    });
  });

  group('fetchRouteById for a shared route', () {
    test('falls back to shared_routes and clips the polyline', () async {
      await _signIn(client);
      fake.bodies['/rest/v1/shared_routes'] = [_routeRow()];
      fake.bodies['/rest/v1/rpc/clip_route_for_viewer'] = [
        {'lat': 51.5, 'lng': -0.1},
        {'lat': 51.6, 'lng': -0.2},
      ];

      final res = await api.fetchRouteById('route-1');

      expect(res.route?.id, 'route-1');
      expect(res.ownerId, 'owner-1');
      expect(res.route?.isPublic, isFalse);
      expect(res.route?.waypoints, hasLength(2));
      final clip = fake.requests
          .firstWhere((r) => r.url.path.endsWith('/clip_route_for_viewer'));
      expect(clip.method, 'GET');
    });

    test('a signed-out caller never asks shared_routes', () async {
      fake.bodies['/rest/v1/shared_routes'] = [_routeRow()];

      final res = await api.fetchRouteById('route-1');

      expect(res.route, isNull);
      expect(fake.paths.any((p) => p.endsWith('/shared_routes')), isFalse);
    });
  });
}
