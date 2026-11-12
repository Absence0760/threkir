import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/payload_hash.dart';
import '../lib/plan_request_client.dart';
import '../lib/season_request_client.dart';
import '../lib/season_types.dart';

Map<String, dynamic> _race([Map<String, dynamic> overrides = const {}]) => {
      'name': 'Comrades',
      'date': '2027-06-13',
      'distanceM': 89000,
      'priority': 'A',
      'goalTimeSec': null,
      ...overrides,
    };

class _Call {
  final Uri url;
  final Map<String, String> headers;
  final String body;
  _Call(this.url, this.headers, this.body);
}

/// Replays canned responses in order and records every request.
class _Fake {
  final List<PlanRequestHttpResponse> responses;
  final calls = <_Call>[];
  _Fake(this.responses);

  Future<PlanRequestHttpResponse> post(
      Uri url, Map<String, String> headers, String body) async {
    calls.add(_Call(url, headers, body));
    return responses[calls.length - 1];
  }
}

PlanRequestHttpResponse _ok(Object body) =>
    PlanRequestHttpResponse(200, jsonEncode(body));

Future<SeasonRequestResult> _request(
  _Fake fake, {
  String? token = 'tok',
  Future<String?> Function()? refresh,
}) =>
    requestSeasonRaces(
      'Richmond Nov 14, Two Oceans Apr 4, Comrades Jun 13',
      '2026-10-16',
      post: fake.post,
      currentToken: () async => token,
      refreshToken: refresh ?? () async => 'fresh',
      baseUrl: 'https://example.test',
    );

Future<PlanRequestErrorKind> _kindOf(Future<Object?> f) async {
  try {
    await f;
  } on PlanRequestError catch (e) {
    return e.kind;
  }
  fail('expected a PlanRequestError');
}

void main() {
  group('requestSeasonRaces', () {
    test('posts {request, today} with the auth and payload-hash headers',
        () async {
      final fake = _Fake([
        _ok({
          'races': [
            _race({
              'name': 'Richmond Marathon',
              'date': '2026-11-14',
              'distanceM': 42195,
              'priority': 'B',
              'goalTimeSec': 10800,
            }),
            _race(),
          ],
          'assumptions': ['priority_default'],
        }),
      ]);
      final result = await _request(fake);

      final call = fake.calls.single;
      expect(call.url.toString(),
          'https://example.test/api/coach/season-request');
      expect(jsonDecode(call.body), {
        'request': 'Richmond Nov 14, Two Oceans Apr 4, Comrades Jun 13',
        'today': '2026-10-16',
      });
      expect(call.headers['x-supabase-authorization'], 'Bearer tok');
      expect(call.headers['x-amz-content-sha256'], payloadSha256Hex(call.body));

      expect(result.races, hasLength(2));
      final richmond = result.races.first;
      expect(richmond.name, 'Richmond Marathon');
      expect(richmond.date, '2026-11-14');
      expect(richmond.distanceM, 42195);
      expect(richmond.priority, SeasonRacePriority.b);
      expect(richmond.goalTimeSec, 10800);
      expect(result.races.last.priority, SeasonRacePriority.a);
      expect(result.races.last.goalTimeSec, isNull);
      expect(result.assumptions, ['priority_default']);
    });

    test('a fractional distance (a half marathon) parses', () async {
      final fake = _Fake([
        _ok({
          'races': [_race({'distanceM': 21097.5})],
          'assumptions': <String>[],
        }),
      ]);
      expect((await _request(fake)).races.single.distanceM, 21097.5);
    });

    test('no session is notAuthenticated, and nothing is posted', () async {
      final fake = _Fake([]);
      expect(await _kindOf(_request(fake, token: null)),
          PlanRequestErrorKind.notAuthenticated);
      expect(fake.calls, isEmpty);
    });

    test('a 401 refreshes once and replays with the new token', () async {
      final fake = _Fake([
        const PlanRequestHttpResponse(401, '{}'),
        _ok({'races': [_race()], 'assumptions': <String>[]}),
      ]);
      final result = await _request(fake);
      expect(result.races, hasLength(1));
      expect(fake.calls, hasLength(2));
      expect(fake.calls.last.headers['x-supabase-authorization'],
          'Bearer fresh');
    });

    test('a refresh that fails or yields nothing keeps the 401', () async {
      for (final refresh in <Future<String?> Function()>[
        () async => null,
        () async => throw StateError('refresh failed'),
      ]) {
        final fake = _Fake([const PlanRequestHttpResponse(401, '{}')]);
        expect(await _kindOf(_request(fake, refresh: refresh)),
            PlanRequestErrorKind.notAuthenticated);
        expect(fake.calls, hasLength(1));
      }
    });

    test('statuses map to the plan assistant error kinds', () async {
      final cases = <int, (String, PlanRequestErrorKind)>{
        403: ('{"code":"ai_disclosure_required"}', PlanRequestErrorKind.consent),
        429: ('{"error":"daily_limit"}', PlanRequestErrorKind.dailyLimit),
        400: ('{"error":"invalid season request"}',
            PlanRequestErrorKind.invalid),
        422: ('{"error":"could not understand request"}',
            PlanRequestErrorKind.notUnderstood),
        503: ('not json', PlanRequestErrorKind.unavailable),
      };
      for (final MapEntry(key: status, value: (body, kind))
          in cases.entries) {
        final fake = _Fake([PlanRequestHttpResponse(status, body)]);
        expect(await _kindOf(_request(fake)), kind, reason: '$status');
      }
    });

    test('a thrown post is unavailable', () async {
      expect(
        await _kindOf(requestSeasonRaces('x', '2026-10-16',
            post: (_, _, _) async => throw StateError('offline'),
            currentToken: () async => 'tok',
            baseUrl: 'https://example.test')),
        PlanRequestErrorKind.unavailable,
      );
    });

    test('a 200 outside the contract is unavailable, never partly shown',
        () async {
      for (final body in <Object>[
        {'races': [_race({'priority': 'Z'})], 'assumptions': <String>[]},
        {'races': <Object>[], 'assumptions': ['made_up']},
        'not an object',
      ]) {
        final fake = _Fake([_ok(body)]);
        expect(await _kindOf(_request(fake)), PlanRequestErrorKind.unavailable,
            reason: '$body');
      }
    });
  });

  group('parseSeasonRequestResult', () {
    test('accepts an empty list with its reasons', () {
      final r = parseSeasonRequestResult({
        'races': <Object>[],
        'assumptions': ['race_dropped_date'],
      })!;
      expect(r.races, isEmpty);
      expect(r.assumptions, ['race_dropped_date']);
    });

    test('refuses every out-of-contract race field', () {
      final withoutGoal = _race()..remove('goalTimeSec');
      final bad = <Object?>[
        null,
        'race',
        <Object>[],
        _race({'name': ''}),
        _race({'name': 7}),
        _race({'date': '13 June'}),
        _race({'date': null}),
        _race({'distanceM': 4999}),
        _race({'distanceM': 400001}),
        _race({'distanceM': '89000'}),
        _race({'priority': 'a'}),
        _race({'priority': null}),
        _race({'goalTimeSec': 0}),
        _race({'goalTimeSec': 1.5}),
        _race({'goalTimeSec': '3600'}),
        withoutGoal,
      ];
      for (final race in bad) {
        expect(
            parseSeasonRequestResult({
              'races': [race],
              'assumptions': <String>[],
            }),
            isNull,
            reason: '$race');
      }
    });

    test('refuses a malformed envelope and more than 12 races', () {
      for (final raw in <Object?>[
        null,
        <Object>[],
        {'races': <Object>[]},
        {'assumptions': <Object>[]},
        {'races': <String, Object>{}, 'assumptions': <Object>[]},
        {'races': <Object>[], 'assumptions': [3]},
      ]) {
        expect(parseSeasonRequestResult(raw), isNull, reason: '$raw');
      }
      expect(
          parseSeasonRequestResult({
            'races': List.filled(13, _race()),
            'assumptions': <String>[],
          }),
          isNull);
      expect(
          parseSeasonRequestResult({
            'races': List.filled(12, _race()),
            'assumptions': <String>[],
          }),
          isNotNull);
    });
  });

  group('seasonAssumptionLabel', () {
    test('every key the server can send has a line in every locale', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        final lines = <String>{};
        for (final key in kSeasonRequestAssumptions) {
          final line = seasonAssumptionLabel(l10n, key);
          expect(line, isNotNull, reason: '$locale $key');
          expect(line, isNotEmpty, reason: '$locale $key');
          lines.add(line!);
        }
        expect(lines, hasLength(kSeasonRequestAssumptions.length),
            reason: '$locale: two keys share one line');
      }
    });

    test('an unknown key has no line', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(seasonAssumptionLabel(l10n, 'made_up'), isNull);
    });
  });
}
