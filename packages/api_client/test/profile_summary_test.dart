import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// fetchProfileSummary starts the profile read and the follow-summary RPC
/// together. When the RPC fails, the profile read must not be left as an
/// unhandled future: on a screen that is an uncaught zone error beside the
/// one the caller already handles.
class _FakeHttp extends http.BaseClient {
  final Map<String, (int, Object)> byPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var reply = (200, const <dynamic>[] as Object);
    for (final e in byPath.entries) {
      if (request.url.path.endsWith(e.key)) reply = e.value;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(reply.$2))),
      reply.$1,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

const _rpcPath = '/rest/v1/rpc/profile_follow_summary';
const _profilesPath = '/rest/v1/user_profiles';
const _refusal = {
  'code': '42501',
  'message': 'permission denied',
  'details': null,
  'hint': null,
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

  test('a failed follow summary throws once and leaves no stray error',
      () async {
    fake.byPath[_rpcPath] = (403, _refusal);
    fake.byPath[_profilesPath] = (403, _refusal);

    final stray = <Object>[];
    await runZonedGuarded(() async {
      await expectLater(
        api.fetchProfileSummary('user-2'),
        throwsA(isA<PostgrestException>()),
      );
      // Let the profile read settle after the RPC has already thrown.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, (e, _) => stray.add(e));

    expect(stray, isEmpty);
  });

  test('an uninitialised client throws once and leaves no stray error',
      () async {
    final stray = <Object>[];
    await runZonedGuarded(() async {
      await expectLater(
        ApiClient().fetchProfileSummary('user-2'),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, (e, _) => stray.add(e));

    expect(stray, isEmpty);
  });

  test('both reads answering builds the summary', () async {
    fake.byPath[_rpcPath] = (
      200,
      [
        {
          'follower_count': 3,
          'following_count': 1,
          'viewer_follows': true,
          'profile_private': false,
        },
      ],
    );
    fake.byPath[_profilesPath] = (
      200,
      {
        'id': 'user-2',
        'display_name': 'Ana',
        'avatar_url': null,
        'created_at': '2026-01-01T00:00:00Z',
      },
    );

    final summary = await api.fetchProfileSummary('user-2');

    expect(summary?.displayName, 'Ana');
    expect(summary?.followerCount, 3);
    expect(summary?.viewerFollows, isTrue);
  });
}
