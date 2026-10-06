import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// An Apple sign-in hands its one-time authorization code to
/// `apple-token-exchange` so `delete-account` can later revoke the grant
/// (App Store Guideline 5.1.1(v)), and a failure there never undoes the
/// sign-in that already succeeded. The fake sits at the http boundary; the
/// GoTrue and functions clients above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.Request> requests = [];
  int exchangeStatus = 204;
  bool exchangeThrows = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    requests.add(r);
    if (r.url.path.endsWith('/functions/v1/apple-token-exchange')) {
      if (exchangeThrows) throw http.ClientException('offline', r.url);
      return _json(r, exchangeStatus,
          exchangeStatus == 204 ? null : {'error': 'apple_not_configured'});
    }
    if (r.url.path.endsWith('/auth/v1/token')) {
      return _json(r, 200, {
        'access_token': 'a.b.c',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'refresh',
        'user': {
          'id': 'u-apple',
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': {
            'provider': 'apple',
            'providers': ['apple'],
          },
          'user_metadata': <String, dynamic>{},
        },
      });
    }
    return _json(r, 404, {'error': 'unexpected ${r.url.path}'});
  }

  http.StreamedResponse _json(http.Request r, int status, Object? body) =>
      http.StreamedResponse(
        Stream.value(body == null ? <int>[] : utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
        request: r,
      );

  Iterable<http.Request> get exchanges => requests
      .where((r) => r.url.path.endsWith('/functions/v1/apple-token-exchange'));
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
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
        autoRefreshToken: false,
      ),
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  test('an Apple sign-in with a code hands it to apple-token-exchange',
      () async {
    final id = await api.signInWithAppleIdToken(
      idToken: 'id.tok',
      authorizationCode: 'c0de',
    );
    expect(id, 'u-apple');
    final posted = fake.exchanges.toList();
    expect(posted, hasLength(1));
    expect(posted.single.method, 'POST');
    expect(jsonDecode(posted.single.body), {'authorization_code': 'c0de'});
  });

  test('without a code nothing is sent', () async {
    await api.signInWithAppleIdToken(idToken: 'id.tok');
    await api.signInWithAppleIdToken(idToken: 'id.tok', authorizationCode: '');
    expect(fake.exchanges, isEmpty);
  });

  test('a refused exchange does not undo the sign-in', () async {
    fake.exchangeStatus = 503;
    final id = await api.signInWithAppleIdToken(
      idToken: 'id.tok',
      authorizationCode: 'c0de',
    );
    expect(id, 'u-apple');
    expect(await api.keepAppleRevocationCredential('c0de'), isFalse);
  });

  test('a network failure answers false rather than throwing', () async {
    fake.exchangeThrows = true;
    expect(await api.keepAppleRevocationCredential('c0de'), isFalse);
  });
}
