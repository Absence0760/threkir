import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The park catalogue reads feed lists that are searched, ordered and counted
/// on the device, so a read PostgREST cut at `db.max-rows` (a 200 with no
/// flag) silently lost courses from Races & courses and the park index
/// (issue #1374). Each read must walk the whole set by keyset cursor. The
/// fake sits at the http boundary and plays a server capping every response
/// at [_FakeHttp.cap] rows, far below the 1000 the client asks for; the
/// PostgREST builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  _FakeHttp(this.cap);

  final int cap;
  final List<http.BaseRequest> requests = [];
  final Map<String, List<Map<String, dynamic>>> rowsByPath = {};

  /// The 1-based request to [failPath] that answers 500.
  String? failPath;
  int failOn = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final path = request.url.path;
    final entry = rowsByPath.entries.where((e) => path.endsWith(e.key)).first;
    final page = to(entry.key).length - 1;
    if (failPath != null && path.endsWith(failPath!) && page + 1 == failOn) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"message":"boom"}')),
        500,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }
    final limit = int.parse(request.url.queryParameters['limit']!);
    final body = entry.value.skip(page * cap).take(limit < cap ? limit : cap).toList();
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  List<http.BaseRequest> to(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix)).toList();
}

const _parksPath = '/rest/v1/parks';
const _coursesPath = '/rest/v1/park_courses';
const _recordsPath = '/rest/v1/rpc/park_course_records';
const _runnersPath = '/rest/v1/rpc/park_course_month_runners';

Map<String, dynamic> _park(int i) => {
      'id': 'p$i',
      'slug': 'park-$i',
      'name': 'Park $i',
      'agency': 'state',
      'region_code': 'US-VA',
      'country_code': 'US',
      'timezone': 'America/New_York',
      'is_active': true,
      'created_at': '2026-01-01T00:00:00Z',
      'park_season': 2026,
      'park_month': 11,
    };

Map<String, dynamic> _course(int i) => {
      'id': 'c$i',
      'park_id': 'p1',
      'global_segment_id': 's$i',
      'slug': 'course-$i',
      'course_shape': 'loop',
      'status': 'open',
      'geometry_source': 'osm',
      'checkpoints': const <dynamic>[],
      'created_at': '2026-01-01T00:00:00Z',
      'global_segments': {
        'id': 's$i',
        'name': 'Course $i',
        'waypoints': const <dynamic>[],
        'distance_m': 5000,
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
    fake = _FakeHttp(3);
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  test('every park course arrives from a server that caps each page', () async {
    fake.rowsByPath[_coursesPath] = [for (var i = 1; i <= 7; i++) _course(i)];
    final courses = await api.fetchAllParkCourses();
    expect(courses.map((c) => c.course.id), [for (var i = 1; i <= 7; i++) 'c$i']);
    final reqs = fake.to(_coursesPath);
    expect(reqs, hasLength(3));
    expect(reqs.first.url.queryParameters['order'], 'id.asc.nullslast');
    expect(reqs.first.url.queryParameters['limit'], '1000');
    expect(reqs.first.url.queryParameters.containsKey('or'), isFalse);
    expect(reqs[1].url.queryParameters['or'], contains('id.gt."c3"'));
    expect(reqs[2].url.queryParameters['or'], contains('id.gt."c6"'));
  });

  test('a page that fails fails the course read rather than listing part of it', () async {
    fake.rowsByPath[_coursesPath] = [for (var i = 1; i <= 7; i++) _course(i)];
    fake
      ..failPath = _coursesPath
      ..failOn = 2;
    await expectLater(api.fetchAllParkCourses(), throwsA(isA<PostgrestException>()));
  });

  test('every park arrives, walked in region, name, id order', () async {
    fake.rowsByPath[_parksPath] = [for (var i = 1; i <= 5; i++) _park(i)];
    final parks = await api.fetchParks();
    expect(parks.map((p) => p.park.id), ['p1', 'p2', 'p3', 'p4', 'p5']);
    final reqs = fake.to(_parksPath);
    expect(reqs.first.url.queryParameters['order'],
        'region_code.asc.nullslast,name.asc.nullslast,id.asc.nullslast');
    expect(reqs.first.url.queryParameters['select'], '*,park_season,park_month');
    expect(reqs[1].url.queryParameters['or'], contains('id.gt."p3"'));
  });

  test('a park\'s own courses are walked too, by slug', () async {
    fake.rowsByPath[_coursesPath] = [for (var i = 1; i <= 4; i++) _course(i)];
    final courses = await api.fetchParkCourses('p1');
    expect(courses, hasLength(4));
    final reqs = fake.to(_coursesPath);
    expect(reqs.first.url.queryParameters['park_id'], 'eq.p1');
    expect(reqs.first.url.queryParameters['order'], 'slug.asc.nullslast,id.asc.nullslast');
  });

  test('every course\'s season record arrives from the capped RPC', () async {
    fake.rowsByPath[_recordsPath] = [
      for (var i = 1; i <= 5; i++)
        {'course_id': 'c$i', 'season': 2026, 'user_id': 'u$i', 'display_name': null, 'time_seconds': 600 + i},
    ];
    final records = await api.fetchParkCourseRecords();
    expect(records.keys, ['c1', 'c2', 'c3', 'c4', 'c5']);
    expect(records['c5']!.timeSeconds, 605);
    final reqs = fake.to(_recordsPath);
    expect(reqs.first.method, 'GET');
    expect(reqs.first.url.queryParameters['order'], 'course_id.asc.nullslast');
    expect(reqs[1].url.queryParameters['or'], contains('course_id.gt."c3"'));
  });

  test('every course\'s runner count arrives from the capped RPC', () async {
    fake.rowsByPath[_runnersPath] = [
      for (var i = 1; i <= 4; i++) {'course_id': 'c$i', 'runners': i},
    ];
    final counts = await api.fetchParkCourseMonthRunners('p1');
    expect(counts, {'c1': 1, 'c2': 2, 'c3': 3, 'c4': 4});
    expect(fake.to(_runnersPath).first.url.queryParameters['p_park_id'], 'p1');
  });
}
