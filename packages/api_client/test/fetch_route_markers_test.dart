import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `fetchRouteMarkers` reports a failed read as a failure, never as "no
/// markers", and asks for them with a GET so the gateway may replay it
/// (decisions § 1703). The fake sits at the http boundary; the PostgREST
/// builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  int status = 200;
  Object body = const <dynamic>[];

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

Map<String, dynamic> _marker(String id, double positionM) => {
      'id': id,
      'route_id': 'route-1',
      'user_id': 'user-1',
      'kind': 'aid_station',
      'label': 'Aid $id',
      'lat': 51.5,
      'lng': -0.1,
      'position_m': positionM,
      'meta': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
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

  test('a 502 from the gateway throws instead of answering no markers',
      () async {
    fake.status = 502;
    fake.body = {
      'message': 'An invalid response was received from the upstream server',
    };
    await expectLater(
      api.fetchRouteMarkers('route-1'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('the read goes out as a GET carrying the route id', () async {
    await api.fetchRouteMarkers('route-1');
    expect(fake.requests, hasLength(1));
    final req = fake.requests.single;
    expect(req.method, 'GET');
    expect(req.url.path, endsWith('/rest/v1/rpc/route_markers_for_viewer'));
    expect(req.url.queryParameters['p_route_id'], 'route-1');
  });

  test('a successful read parses every marker row', () async {
    fake.body = [_marker('a', 100), _marker('b', 2500)];
    final markers = await api.fetchRouteMarkers('route-1');
    expect(markers.map((m) => m.id), ['a', 'b']);
    expect(markers.last.positionM, 2500);
  });

  test('a route with no markers is an empty list, not an error', () async {
    fake.body = const <dynamic>[];
    expect(await api.fetchRouteMarkers('route-1'), isEmpty);
  });

  test('a blank route id answers empty without a wire call', () async {
    expect(await api.fetchRouteMarkers(''), isEmpty);
    expect(fake.requests, isEmpty);
  });
}
