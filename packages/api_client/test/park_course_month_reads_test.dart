import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The monthly park course reads (issue #1343) name their RPC arguments and
/// columns by hand, so a misspelled `p_month` reaches the server as an unknown
/// argument and a missing `park_month` leaves a course page with no month to
/// show. The fake sits at the http boundary and answers by path; the
/// PostgREST builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object> bodyByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final match = bodyByPath.entries
        .where((e) => request.url.path.endsWith(e.key))
        .map((e) => e.value);
    final body = match.isEmpty ? const <dynamic>[] : match.first;
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

const _leaderboardPath = '/rest/v1/rpc/global_segment_leaderboard';
const _completionsPath = '/rest/v1/rpc/global_segment_completions';
const _runnersPath = '/rest/v1/rpc/park_course_month_runners';
const _parksPath = '/rest/v1/parks';
const _coursesPath = '/rest/v1/park_courses';

Map<String, dynamic> _park() => {
      'id': 'p1',
      'slug': 'pocahontas',
      'name': 'Pocahontas State Park',
      'agency': 'state',
      'region_code': 'US-VA',
      'country_code': 'US',
      'timezone': 'America/New_York',
      'is_active': true,
      'created_at': '2026-01-01T00:00:00Z',
      'park_season': 2026,
      'park_month': 11,
    };

Map<String, dynamic> _course() => {
      'id': 'c1',
      'park_id': 'p1',
      'global_segment_id': 's1',
      'slug': 'beaver-lake-trail',
      'course_shape': 'loop',
      'status': 'open',
      'geometry_source': 'osm',
      'checkpoints': const <dynamic>[],
      'created_at': '2026-01-01T00:00:00Z',
      'global_segments': {
        'id': 's1',
        'name': 'Beaver Lake Trail',
        'waypoints': const <dynamic>[],
        'distance_m': 3595,
        'surface': 'trail',
        'is_active': true,
        'created_at': '2026-01-01T00:00:00Z',
      },
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

  test('the fastest board passes a month with its season, by name', () async {
    await api.fetchGlobalSegmentLeaderboard('s1', season: 2026, month: 10);
    final req = fake.to(_leaderboardPath).single;
    expect(req.method, 'GET');
    expect(req.url.queryParameters['p_season'], '2026');
    expect(req.url.queryParameters['p_month'], '10');
  });

  test('the year and all-time boards send no month', () async {
    await api.fetchGlobalSegmentLeaderboard('s1', season: 2026);
    await api.fetchGlobalSegmentCompletions('s1');
    expect(fake.to(_leaderboardPath).single.url.queryParameters.containsKey('p_month'), isFalse);
    final completions = fake.to(_completionsPath).single.url.queryParameters;
    expect(completions.containsKey('p_month'), isFalse);
    expect(completions.containsKey('p_season'), isFalse);
  });

  test('the completions board passes a month with its season, by name', () async {
    await api.fetchGlobalSegmentCompletions('s1', season: 2026, month: 3, limit: 20);
    final params = fake.to(_completionsPath).single.url.queryParameters;
    expect(params['p_season'], '2026');
    expect(params['p_month'], '3');
    expect(params['p_limit'], '20');
  });

  test('a park reads its month beside its season', () async {
    fake.bodyByPath[_parksPath] = [_park()];
    final parks = await api.fetchParks();
    expect(fake.to(_parksPath).single.url.queryParameters['select'], '*,park_season,park_month');
    expect(parks.single.season, 2026);
    expect(parks.single.month, 11);
  });

  test('runner counts are keyed by course, and a malformed row is dropped', () async {
    fake.bodyByPath[_runnersPath] = [
      {'course_id': 'c1', 'runners': 12},
      {'course_id': 'c2', 'runners': 1},
      {'course_id': 'c3'},
    ];
    final counts = await api.fetchParkCourseMonthRunners('p1');
    expect(fake.to(_runnersPath).single.url.queryParameters['p_park_id'], 'p1');
    expect(counts, {'c1': 12, 'c2': 1});
  });

  test('a course opens by its id with its park\'s season and month', () async {
    fake.bodyByPath[_coursesPath] = _course();
    fake.bodyByPath[_parksPath] = _park();
    final found = await api.fetchParkCourseById('c1');
    expect(fake.to(_coursesPath).single.url.queryParameters['id'], 'eq.c1');
    expect(found?.course.segment.name, 'Beaver Lake Trail');
    expect(found?.park.season, 2026);
    expect(found?.park.month, 11);
  });

  test('a course with no visible segment does not open', () async {
    fake.bodyByPath[_coursesPath] = {..._course(), 'global_segments': null};
    expect(await api.fetchParkCourseById('c1'), isNull);
    expect(fake.to(_parksPath), isEmpty);
  });
}
