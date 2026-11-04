import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `completeStravaOAuth` turns a refusal the function codes into
/// [StravaConnectFailure] so the screen words it, and lets every other
/// failure through as it came for `friendlyError`. The fake sits at the http
/// boundary; the functions client and ApiClient are real. Mirrors web
/// `completeStravaOAuth` + `stravaConnectAppError`.
class _FakeHttp extends http.BaseClient {
  final List<http.Request> requests = [];
  (int, String, String) answer = (200, '{}', 'application/json');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    final (status, body, type) = answer;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': type},
      request: request,
    );
  }
}

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

  Future<StravaSyncResult> connect() => api.completeStravaOAuth(
      code: 'c', scope: 'read', redirectUri: 'threkir://strava-callback');

  test('posts the connect action and grades a success', () async {
    fake.answer = (200, jsonEncode({'imported': 3, 'complete': true}),
        'application/json');
    final r = await connect();
    expect(jsonDecode(fake.requests.single.body), {
      'action': 'connect',
      'code': 'c',
      'scope': 'read',
      'redirect_uri': 'threkir://strava-callback',
    });
    expect(r.imported, 3);
    expect(r.complete, isTrue);
  });

  test('a worded refusal throws its reason and keeps the code', () async {
    fake.answer =
        (400, jsonEncode({'error': 'missing_scope'}), 'application/json');
    await expectLater(
      connect(),
      throwsA(isA<StravaConnectFailure>()
          .having((f) => f.reason, 'reason', StravaConnectError.missingScope)
          .having((f) => f.code, 'code', 'missing_scope')),
    );
  });

  test('an unworded refusal passes through as the transport raised it',
      () async {
    fake.answer =
        (500, jsonEncode({'error': 'store_tokens_failed'}), 'application/json');
    await expectLater(connect(), throwsA(isA<FunctionException>()));
  });

  test('a prose body from an older deployment is not a code', () async {
    fake.answer = (
      400,
      'Strava connection is missing the activity:read_all scope.',
      'text/plain'
    );
    await expectLater(connect(), throwsA(isA<FunctionException>()));
  });

  test('a sync Strava refuses for a revoked grant throws the reconnect reason',
      () async {
    fake.answer = (
      401,
      jsonEncode({'error': 'refresh_failed', 'reconnect_required': true}),
      'application/json'
    );
    await expectLater(
      api.syncStrava(),
      throwsA(isA<StravaConnectFailure>()
          .having((f) => f.reason, 'reason', StravaConnectError.reconnect)
          .having((f) => f.code, 'code', 'refresh_failed')),
    );
    expect(jsonDecode(fake.requests.single.body),
        {'action': 'sync', 'lookbackDays': 90});
  });

  test('an unworded sync refusal passes through as the transport raised it',
      () async {
    fake.answer =
        (400, jsonEncode({'error': 'strava_not_connected'}), 'application/json');
    await expectLater(api.syncStrava(), throwsA(isA<FunctionException>()));
  });
}
