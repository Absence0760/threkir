import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `fetchParkCourseForRoute` finds the park course whose route the recorder
/// is following, for live course timing (#1446): one row by `route_id`, with
/// its catalogue segment embedded, null when no course uses the route, and a
/// failed read thrown rather than read as "no course". The fake sits at the
/// http boundary; the PostgREST builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  int status = 200;
  Object? body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Map<String, dynamic> _course({Object? segment = const {}}) => {
      'id': 'course-1',
      'park_id': 'park-1',
      'global_segment_id': 'seg-1',
      'route_id': 'route-1',
      'slug': 'lake-loop',
      'course_shape': 'loop',
      'status': 'open',
      'geometry_source': 'osm',
      'checkpoints': [
        {'lat': 37.5, 'lng': -77.5},
      ],
      'created_at': '2026-11-20T00:00:00Z',
      'global_segments': segment,
    };

final _segment = {
  'id': 'seg-1',
  'name': 'Lake loop',
  'waypoints': [
    {'lat': 37.5, 'lng': -77.5},
    {'lat': 37.51, 'lng': -77.5},
  ],
  'distance_m': 1112,
  'surface': 'trail',
  'is_active': true,
  'created_at': '2026-11-20T00:00:00Z',
  'start_gate_lat': 37.5,
  'start_gate_lng': -77.5,
  'start_gate_bearing_deg': 0,
  'start_gate_half_width_m': 15,
};

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

  test('reads one course by its route, with the segment embedded', () async {
    fake.body = _course(segment: _segment);
    final listing = await api.fetchParkCourseForRoute('route-1');
    expect(listing, isNotNull);
    expect(listing!.course.routeId, 'route-1');
    expect(listing.segment.distanceM, 1112);
    expect(listing.segment.startGateBearingDeg, 0);

    final req = fake.requests.single;
    expect(req.method, 'GET');
    expect(req.url.path, endsWith('/rest/v1/park_courses'));
    expect(req.url.queryParameters['route_id'], 'eq.route-1');
    expect(req.url.queryParameters['select'], '*,global_segments(*)');
    expect(req.url.queryParameters['limit'], '1');
  });

  test('no course on the route is null', () async {
    fake.body = null;
    expect(await api.fetchParkCourseForRoute('route-9'), isNull);
  });

  test('a course whose segment RLS hides is null', () async {
    fake.body = _course(segment: null);
    expect(await api.fetchParkCourseForRoute('route-1'), isNull);
  });

  test('a failed read throws instead of answering no course', () async {
    fake.status = 502;
    fake.body = {'message': 'bad gateway'};
    await expectLater(
      api.fetchParkCourseForRoute('route-1'),
      throwsA(isA<PostgrestException>()),
    );
  });
}
