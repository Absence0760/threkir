import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The athlete's coach-assistant consent (issue #1215 Phase 4) names its RPC,
/// parameters and refusal codes by hand, and the roster reads carry the
/// consent column by name, so a renamed parameter or a dropped column reaches
/// the coaching screen as a switch that never says what the server holds.
/// Same http-boundary fake as coach_share_test.dart.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object?> bodyByPath = {};
  final Map<String, int> statusByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object? body = const <dynamic>[];
    var status = 200;
    for (final e in bodyByPath.entries) {
      if (request.url.path.endsWith(e.key)) body = e.value;
    }
    for (final e in statusByPath.entries) {
      if (request.url.path.endsWith(e.key)) status = e.value;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  Iterable<http.BaseRequest> to(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix));
}

const _consentPath = '/rest/v1/rpc/set_coach_ai_assist_consent';
const _linksPath = '/rest/v1/coach_athletes';
const _profilesPath = '/rest/v1/user_profiles';

Future<void> _signIn(SupabaseClient client) => client.auth.setInitialSession(
  jsonEncode({
    'access_token': 'fake-token',
    'token_type': 'bearer',
    'user': {
      'id': 'user-1',
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  }),
);

Map<String, Object?> _link({Object? version}) => {
  'id': 'link-1',
  'status': 'active',
  'note': null,
  'created_at': '2026-11-01T08:00:00Z',
  'accepted_at': '2026-11-02T08:00:00Z',
  'coach_id': 'coach-1',
  'athlete_id': 'athlete-1',
  'ai_assist_consent_version': version,
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

  void refuse(int status, String code, String message) {
    fake.statusByPath[_consentPath] = status;
    fake.bodyByPath[_consentPath] = {'code': code, 'message': message};
  }

  group('setCoachAiAssistConsent', () {
    test('posts the link and the version, returns the stored version',
        () async {
      fake.bodyByPath[_consentPath] = _link(version: 1);

      expect(await api.setCoachAiAssistConsent('link-1', 1), 1);

      final req = fake.to(_consentPath).single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'p_link_id': 'link-1', 'p_version': 1});
    });

    test('withdrawing sends a null version and returns null', () async {
      fake.bodyByPath[_consentPath] = _link();

      expect(await api.setCoachAiAssistConsent('link-1', null), isNull);

      final req = fake.to(_consentPath).single as http.Request;
      expect(jsonDecode(req.body), {'p_link_id': 'link-1', 'p_version': null});
    });

    test('a link that is not yours or not active is CoachAssistConsentRefused',
        () async {
      refuse(404, 'P0002', 'set_coach_ai_assist_consent: link not found');
      expect(
        api.setCoachAiAssistConsent('link-9', 1),
        throwsA(isA<CoachAssistConsentRefused>()),
      );
    });

    test('an unknown version is CoachAssistConsentRefused', () async {
      refuse(400, '22023', 'set_coach_ai_assist_consent: unknown version');
      expect(
        api.setCoachAiAssistConsent('link-1', 9),
        throwsA(isA<CoachAssistConsentRefused>()),
      );
    });

    test('anything else stays the PostgrestException it is', () async {
      refuse(401, '42501', 'set_coach_ai_assist_consent: not authorized');
      expect(
        api.setCoachAiAssistConsent('link-1', 1),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
    });
  });

  group('roster reads carry the consent', () {
    setUp(() async {
      await _signIn(client);
      fake.bodyByPath[_profilesPath] = [
        {'id': 'coach-1', 'display_name': 'Kim', 'avatar_url': null},
        {'id': 'athlete-1', 'display_name': 'Ari', 'avatar_url': null},
      ];
    });

    test('fetchMyCoaches selects and reads ai_assist_consent_version',
        () async {
      fake.bodyByPath[_linksPath] = [_link(version: 1)];

      final links = await api.fetchMyCoaches();

      final select =
          fake.to(_linksPath).single.url.queryParameters['select'] ?? '';
      expect(select.split(',').map((c) => c.trim()),
          contains('ai_assist_consent_version'));
      expect(links.single.userId, 'coach-1');
      expect(links.single.aiAssistConsentVersion, 1);
    });

    test('fetchMyAthletes reads it too', () async {
      fake.bodyByPath[_linksPath] = [_link(version: 1)];

      final links = await api.fetchMyAthletes();

      expect(links.single.userId, 'athlete-1');
      expect(links.single.aiAssistConsentVersion, 1);
    });

    test('null, zero and non-integer versions read as no consent', () async {
      for (final raw in <Object?>[null, 0, '1', 1.5, true]) {
        fake.requests.clear();
        fake.bodyByPath[_linksPath] = [_link(version: raw)];
        final links = await api.fetchMyCoaches();
        expect(links.single.aiAssistConsentVersion, isNull, reason: '$raw');
      }
    });
  });

  test('withAiAssistConsentVersion changes only the consent', () {
    final link = CoachAthleteLink(
      id: 'l1',
      status: 'active',
      note: 'n',
      createdAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
      userId: 'coach-1',
      displayName: 'Kim',
      avatarUrl: null,
    );
    expect(link.aiAssistConsentVersion, isNull);
    final on = link.withAiAssistConsentVersion(1);
    expect(on.aiAssistConsentVersion, 1);
    expect(on.id, 'l1');
    expect(on.note, 'n');
    expect(on.userId, 'coach-1');
    expect(on.displayName, 'Kim');
    expect(on.acceptedAt, DateTime.utc(2026, 1, 2));
    expect(on.withAiAssistConsentVersion(null).aiAssistConsentVersion, isNull);
  });
}
