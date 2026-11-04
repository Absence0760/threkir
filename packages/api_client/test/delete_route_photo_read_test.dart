import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `deleteRoute` reads the route's photo paths only to sweep their bytes
/// afterwards. That read is auxiliary: when it fails the route row is still
/// deleted, and the sweep is what goes without. The fake plays PostgREST and
/// Storage at the http boundary.
class _Fake extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  final bool photoReadFails;
  _Fake({required this.photoReadFails});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final path = request.url.path;
    var status = 200;
    Object body = const <dynamic>[];
    if (path.endsWith('/rest/v1/route_photos')) {
      if (photoReadFails) {
        status = 500;
        body = {'message': 'boom', 'code': 'XX000'};
      } else {
        body = [
          {'storage_path': 'u1/r1/a.jpg', 'thumb_512_path': 'u1/r1/a_512.jpg'},
        ];
      }
    } else if (path.endsWith('/rest/v1/routes') && request.method == 'DELETE') {
      body = [
        {'id': 'r1'},
      ];
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Future<(ApiClient, _Fake, SupabaseClient)> _signedIn({
  required bool photoReadFails,
}) async {
  final fake = _Fake(photoReadFails: photoReadFails);
  final client = SupabaseClient(
    'http://127.0.0.1:24321',
    'test-anon-key',
    httpClient: fake,
  );
  await client.auth.setInitialSession(
    jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'u1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
  return (ApiClient.withClient(client), fake, client);
}

bool _isRouteDelete(http.BaseRequest r) =>
    r.method == 'DELETE' && r.url.path.endsWith('/rest/v1/routes');

bool _isStorage(http.BaseRequest r) => r.url.path.contains('/storage/v1/');

void main() {
  test('a failed photo path read still deletes the route', () async {
    final (api, fake, client) = await _signedIn(photoReadFails: true);
    addTearDown(client.dispose);
    await api.deleteRoute('r1');
    expect(fake.requests.where(_isRouteDelete), hasLength(1));
    expect(
      fake.requests.where(_isStorage),
      isEmpty,
      reason: 'with no paths read there is nothing to sweep',
    );
  });

  test('read paths are swept after the row delete', () async {
    final (api, fake, client) = await _signedIn(photoReadFails: false);
    addTearDown(client.dispose);
    await api.deleteRoute('r1');
    final deleteAt = fake.requests.indexWhere(_isRouteDelete);
    final sweepAt = fake.requests.indexWhere(_isStorage);
    expect(deleteAt, isNonNegative);
    expect(sweepAt, greaterThan(deleteAt));
  });
}
