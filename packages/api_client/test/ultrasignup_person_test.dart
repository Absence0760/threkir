import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show IntegrationRow;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The UltraSignup person link (decisions § 1841): the pure readers that turn
/// the lookup's answer and the stored `integrations` row into values, and the
/// four wire calls Settings and the races sheet make. The fake sits at the
/// http boundary; the PostgREST / functions builders and ApiClient above it are
/// real, so what is asserted is the request that would leave the device.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];
  int status = 200;
  Object? body = const <dynamic>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(request is http.Request ? request.body : '');
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

/// A session GoTrue accepts without a network call: `recoverSession` saves an
/// unexpired session as-is, and an access token that is not a JWT has no
/// expiry to be past.
Future<void> _signIn(SupabaseClient client, {String userId = 'user-1'}) async {
  await client.auth.recoverSession(jsonEncode({
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'refresh_token': 'test-refresh-token',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00Z',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
    },
  }));
}

IntegrationRow _row({
  String provider = 'ultrasignup',
  String? externalId = '12345',
  String? first = 'Ada',
  String? last = 'Lovelace',
}) =>
    IntegrationRow(
      id: 'i1',
      userId: 'user-1',
      provider: provider,
      externalId: externalId,
      externalFirstName: first,
      externalLastName: last,
    );

void main() {
  group('ultraSignUpNameReady', () {
    test('needs both halves, trimmed', () {
      expect(ultraSignUpNameReady('Ada', 'Lovelace'), isTrue);
      expect(ultraSignUpNameReady('  ', 'Lovelace'), isFalse);
      expect(ultraSignUpNameReady('Ada', ''), isFalse);
    });

    test('caps each half at the column limit, counted in code points', () {
      expect(ultraSignUpNameReady('a' * ultraSignUpNameMaxLen, 'b'), isTrue);
      expect(
          ultraSignUpNameReady('a' * (ultraSignUpNameMaxLen + 1), 'b'), isFalse);
      // 60 astral characters are 120 UTF-16 units and still one name.
      expect(ultraSignUpNameReady('\u{1D49C}' * ultraSignUpNameMaxLen, 'b'),
          isTrue);
    });
  });

  group('parseUltraSignUpCandidates', () {
    test('reads every field of a well-formed candidate', () {
      final out = parseUltraSignUpCandidates({
        'candidates': [
          {
            'id': '12345',
            'firstName': ' Ada ',
            'lastName': 'Lovelace',
            'age': 36,
            'resultCount': 4,
            'recentEvents': [
              {'name': 'Bear 100', 'date': '2026-09-26'},
              {'name': 'Wasatch', 'date': 'September'},
              {'name': '', 'date': '2025-09-05'},
            ],
          },
        ],
      });
      expect(out, hasLength(1));
      final c = out.single;
      expect(c.id, '12345');
      expect(c.firstName, 'Ada');
      expect(c.age, 36);
      expect(c.resultCount, 4);
      expect(c.recentEvents.map((e) => e.name), ['Bear 100', 'Wasatch']);
      expect(c.recentEvents.first.date, '2026-09-26');
      expect(c.recentEvents.last.date, isNull,
          reason: 'an unreadable date is no date, not the raw string');
    });

    test('drops a candidate that could never be stored', () {
      final out = parseUltraSignUpCandidates({
        'candidates': [
          {'id': '0', 'firstName': 'A', 'lastName': 'B'},
          {'id': '0123', 'firstName': 'A', 'lastName': 'B'},
          {'id': '42', 'firstName': '', 'lastName': 'B'},
          {'id': 42, 'firstName': 'A', 'lastName': 'B'},
          'not a row',
          {'id': '7', 'firstName': 'A', 'lastName': 'B'},
        ],
      });
      expect(out.map((c) => c.id), ['7']);
    });

    test('an unknown age or count is null / zero, never a guess', () {
      final c = parseUltraSignUpCandidates({
        'candidates': [
          {
            'id': '7',
            'firstName': 'A',
            'lastName': 'B',
            'age': 0,
            'resultCount': -1,
            'recentEvents': 'nope',
          },
        ],
      }).single;
      expect(c.age, isNull);
      expect(c.resultCount, 0);
      expect(c.recentEvents, isEmpty);
    });

    test('anything but the envelope is no candidates', () {
      expect(parseUltraSignUpCandidates(null), isEmpty);
      expect(parseUltraSignUpCandidates(const []), isEmpty);
      expect(parseUltraSignUpCandidates({'candidates': 'x'}), isEmpty);
    });
  });

  group('ultraSignUpLinkFromRow', () {
    test('a whole UltraSignup row is a link', () {
      expect(
        ultraSignUpLinkFromRow(_row()),
        const UltraSignUpPersonLink(
            personId: '12345', firstName: 'Ada', lastName: 'Lovelace'),
      );
    });

    test('a partial, foreign or absent row is no link', () {
      expect(ultraSignUpLinkFromRow(null), isNull);
      expect(ultraSignUpLinkFromRow(_row(provider: 'strava')), isNull);
      expect(ultraSignUpLinkFromRow(_row(externalId: null)), isNull);
      expect(ultraSignUpLinkFromRow(_row(externalId: '0')), isNull);
      expect(ultraSignUpLinkFromRow(_row(first: ' ')), isNull);
      expect(ultraSignUpLinkFromRow(_row(last: null)), isNull);
    });

    test('a picked candidate keeps UltraSignup\'s spelling of the name', () {
      const c = UltraSignUpCandidate(
        id: '9',
        firstName: 'José',
        lastName: 'García',
        age: null,
        resultCount: 0,
        recentEvents: [],
      );
      expect(
        linkFromCandidate(c),
        const UltraSignUpPersonLink(
            personId: '9', firstName: 'José', lastName: 'García'),
      );
    });
  });

  group('wire calls', () {
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

    test('signed out, the link read answers null without a request', () async {
      expect(await api.fetchUltraSignUpLink(), isNull);
      expect(fake.requests, isEmpty);
    });

    test('signed out, link and unlink refuse before any request', () async {
      await expectLater(
        api.linkUltraSignUpPerson(const UltraSignUpPersonLink(
            personId: '1', firstName: 'A', lastName: 'B')),
        throwsA(isA<Exception>()),
      );
      await expectLater(api.unlinkUltraSignUpPerson(), throwsA(isA<Exception>()));
      expect(fake.requests, isEmpty);
    });

    test('the link read is scoped to the caller and the provider', () async {
      await _signIn(client);
      fake.body = [
        {
          'id': 'i1',
          'user_id': 'user-1',
          'provider': 'ultrasignup',
          'external_id': '12345',
          'external_first_name': 'Ada',
          'external_last_name': 'Lovelace',
        },
      ];
      final link = await api.fetchUltraSignUpLink();
      expect(link?.personId, '12345');
      expect(link?.firstName, 'Ada');
      final req = fake.requests.single;
      expect(req.method, 'GET');
      expect(req.url.path, endsWith('/rest/v1/integrations'));
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
      expect(req.url.queryParameters['provider'], 'eq.ultrasignup');
      expect(req.url.queryParameters['select'], contains('external_first_name'));
    });

    test('no stored row reads as not linked', () async {
      await _signIn(client);
      fake.body = const <dynamic>[];
      expect(await api.fetchUltraSignUpLink(), isNull);
    });

    test('a failed read throws rather than reporting not linked', () async {
      await _signIn(client);
      fake.status = 500;
      fake.body = {'message': 'boom', 'code': 'XX000'};
      await expectLater(
          api.fetchUltraSignUpLink(), throwsA(isA<PostgrestException>()));
    });

    test('linking upserts one row per runner per provider', () async {
      await _signIn(client);
      fake.body = null;
      fake.status = 201;
      await api.linkUltraSignUpPerson(const UltraSignUpPersonLink(
          personId: '12345', firstName: 'Ada', lastName: 'Lovelace'));
      final req = fake.requests.single;
      expect(req.method, 'POST');
      expect(req.url.queryParameters['on_conflict'], 'user_id,provider');
      expect(req.headers['Prefer'], contains('resolution=merge-duplicates'));
      expect(jsonDecode(fake.bodies.single), {
        'user_id': 'user-1',
        'provider': 'ultrasignup',
        'external_id': '12345',
        'external_first_name': 'Ada',
        'external_last_name': 'Lovelace',
      });
    });

    test('unlinking deletes only the caller\'s UltraSignup row', () async {
      await _signIn(client);
      fake.body = null;
      fake.status = 204;
      await api.unlinkUltraSignUpPerson();
      final req = fake.requests.single;
      expect(req.method, 'DELETE');
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
      expect(req.url.queryParameters['provider'], 'eq.ultrasignup');
    });

    test('the lookup sends the trimmed name in lookup mode and parses the answer',
        () async {
      await _signIn(client);
      fake.body = {
        'candidates': [
          {'id': '12345', 'firstName': 'Ada', 'lastName': 'Lovelace'},
        ],
      };
      final out = await api.lookupUltraSignUpPeople(' Ada ', 'Lovelace ');
      expect(out.single.id, '12345');
      final req = fake.requests.single;
      expect(req.url.path, endsWith('/functions/v1/race-results-import'));
      expect(jsonDecode(fake.bodies.single), {
        'provider': 'ultrasignup',
        'lookup': true,
        'ultraSignUpFirstName': 'Ada',
        'ultraSignUpLastName': 'Lovelace',
      });
    });

    test('a lookup the function refuses surfaces its status', () async {
      await _signIn(client);
      fake.status = 503;
      fake.body = {'error': 'provider_not_configured'};
      await expectLater(
        api.lookupUltraSignUpPeople('Ada', 'Lovelace'),
        throwsA(isA<FunctionException>()
            .having((e) => e.status, 'status', 503)),
      );
    });
  });
}
