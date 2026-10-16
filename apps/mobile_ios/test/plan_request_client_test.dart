import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../lib/payload_hash.dart';
import '../lib/plan_request_client.dart';
import '../lib/training.dart';

Map<String, dynamic> _inputs([Map<String, dynamic> overrides = const {}]) => {
      'goalEvent': 'distance_half',
      'raceDate': '2027-03-14',
      'goalTimeSec': 7200,
      'recent5kSec': 1590,
      'daysPerWeek': 4,
      'weeks': 12,
      'beginnerWalkRun': false,
      'planName': 'Spring half',
      'assumptions': <String>[],
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

PlanRequestHttpResponse _ok(Map<String, dynamic> inputs) =>
    PlanRequestHttpResponse(200, jsonEncode({'inputs': inputs}));

Future<PlanRequestInputs> _request(
  _Fake fake, {
  String? token = 'tok',
  Future<String?> Function()? refresh,
}) =>
    requestPlanInputs(
      'A sub-2 half on 14 March',
      '2026-10-15',
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
  group('requestPlanInputs', () {
    test('posts {request, today} with the auth and payload-hash headers',
        () async {
      final fake = _Fake([_ok(_inputs())]);
      final inputs = await _request(fake);

      expect(fake.calls, hasLength(1));
      final call = fake.calls.single;
      expect(call.url.toString(),
          'https://example.test/api/coach/plan-request');
      expect(jsonDecode(call.body),
          {'request': 'A sub-2 half on 14 March', 'today': '2026-10-15'});
      expect(call.headers['x-supabase-authorization'], 'Bearer tok');
      expect(call.headers['x-amz-content-sha256'], payloadSha256Hex(call.body));
      expect(call.headers['content-type'], 'application/json');

      expect(inputs.goalEvent, GoalEvent.distanceHalf);
      expect(inputs.raceDate, '2027-03-14');
      expect(inputs.goalTimeSec, 7200);
      expect(inputs.recent5kSec, 1590);
      expect(inputs.daysPerWeek, 4);
      expect(inputs.weeks, 12);
      expect(inputs.beginnerWalkRun, isFalse);
      expect(inputs.planName, 'Spring half');
      expect(inputs.assumptions, isEmpty);
    });

    test('no session is notAuthenticated, without a request', () async {
      final fake = _Fake([]);
      expect(await _kindOf(_request(fake, token: null)),
          PlanRequestErrorKind.notAuthenticated);
      expect(fake.calls, isEmpty);
    });

    test('a 401 refreshes once and replays with the new token', () async {
      final fake = _Fake([
        const PlanRequestHttpResponse(401, '{"error":"expired"}'),
        _ok(_inputs()),
      ]);
      await _request(fake);
      expect(fake.calls, hasLength(2));
      expect(fake.calls[1].headers['x-supabase-authorization'],
          'Bearer fresh');
    });

    test('a second 401 is notAuthenticated, not a retry loop', () async {
      final fake = _Fake([
        const PlanRequestHttpResponse(401, ''),
        const PlanRequestHttpResponse(401, ''),
      ]);
      expect(await _kindOf(_request(fake)),
          PlanRequestErrorKind.notAuthenticated);
      expect(fake.calls, hasLength(2));
    });

    test('a failed refresh surfaces the original 401', () async {
      final fake = _Fake([const PlanRequestHttpResponse(401, '')]);
      expect(
          await _kindOf(_request(fake, refresh: () async => throw 'offline')),
          PlanRequestErrorKind.notAuthenticated);
      expect(fake.calls, hasLength(1));
    });

    test('maps each failure status to its kind', () async {
      final cases = <PlanRequestHttpResponse, PlanRequestErrorKind>{
        const PlanRequestHttpResponse(403, '{"code":"ai_disclosure_required"}'):
            PlanRequestErrorKind.consent,
        const PlanRequestHttpResponse(403, '{"error":"upgrade required"}'):
            PlanRequestErrorKind.unavailable,
        const PlanRequestHttpResponse(429, '{"error":"limit"}'):
            PlanRequestErrorKind.dailyLimit,
        const PlanRequestHttpResponse(400, ''): PlanRequestErrorKind.invalid,
        const PlanRequestHttpResponse(422, '{}'):
            PlanRequestErrorKind.notUnderstood,
        const PlanRequestHttpResponse(500, 'oops'):
            PlanRequestErrorKind.unavailable,
        const PlanRequestHttpResponse(503, ''):
            PlanRequestErrorKind.unavailable,
      };
      for (final entry in cases.entries) {
        final fake = _Fake([entry.key]);
        expect(await _kindOf(_request(fake)), entry.value,
            reason: 'status ${entry.key.statusCode} ${entry.key.body}');
      }
    });

    test('a thrown request is unavailable', () async {
      Future<PlanRequestHttpResponse> boom(
              Uri u, Map<String, String> h, String b) async =>
          throw StateError('socket closed');
      expect(
          await _kindOf(requestPlanInputs('x', '2026-10-15',
              post: boom,
              currentToken: () async => 'tok',
              baseUrl: 'https://example.test')),
          PlanRequestErrorKind.unavailable);
    });

    test('a 200 without usable inputs is unavailable', () async {
      for (final body in [
        'not json',
        '{}',
        '{"inputs":null}',
        '{"inputs":[]}',
        jsonEncode({'inputs': _inputs({'goalEvent': 'custom'})}),
      ]) {
        final fake = _Fake([PlanRequestHttpResponse(200, body)]);
        expect(await _kindOf(_request(fake)), PlanRequestErrorKind.unavailable,
            reason: body);
      }
    });
  });

  group('parsePlanRequestInputs', () {
    test('reads nullable fields as null and every known assumption', () {
      final parsed = parsePlanRequestInputs(_inputs({
        'raceDate': null,
        'goalTimeSec': null,
        'recent5kSec': null,
        'weeks': null,
        'planName': null,
        'beginnerWalkRun': true,
        'goalEvent': 'distance_5k',
        'assumptions': [
          'goal_event_default',
          'days_per_week_default',
          'days_per_week_clamped',
          'weeks_clamped',
          'race_date_dropped',
          'goal_time_dropped',
          'recent_5k_dropped',
          'beginner_5k',
        ],
      }))!;
      expect(parsed.raceDate, isNull);
      expect(parsed.goalTimeSec, isNull);
      expect(parsed.recent5kSec, isNull);
      expect(parsed.weeks, isNull);
      expect(parsed.planName, isNull);
      expect(parsed.beginnerWalkRun, isTrue);
      expect(parsed.goalEvent, GoalEvent.distance5k);
      expect(parsed.assumptions, PlanRequestAssumption.values);
    });

    test('reads every goal event the wizard offers', () {
      expect(
          parsePlanRequestInputs(_inputs({'goalEvent': 'distance_10k'}))!
              .goalEvent,
          GoalEvent.distance10k);
      expect(
          parsePlanRequestInputs(_inputs({'goalEvent': 'distance_full'}))!
              .goalEvent,
          GoalEvent.distanceFull);
    });

    test('refuses the whole answer on any field outside the contract', () {
      final bad = <Map<String, dynamic>>[
        {'goalEvent': 'ultra'},
        {'goalEvent': null},
        {'raceDate': '14 March'},
        {'raceDate': 20270314},
        {'goalTimeSec': '7200'},
        {'goalTimeSec': 0},
        {'goalTimeSec': 36000},
        {'goalTimeSec': 7200.5},
        {'recent5kSec': 600},
        {'recent5kSec': 3600},
        {'daysPerWeek': null},
        {'daysPerWeek': 2},
        {'daysPerWeek': 8},
        {'weeks': 3},
        {'weeks': 25},
        {'beginnerWalkRun': 'false'},
        {'planName': 42},
        {'assumptions': null},
        {'assumptions': ['made_up_key']},
        {'assumptions': [1]},
      ];
      for (final override in bad) {
        expect(parsePlanRequestInputs(_inputs(override)), isNull,
            reason: '$override');
      }
      expect(parsePlanRequestInputs(null), isNull);
      expect(parsePlanRequestInputs('inputs'), isNull);
    });

    test('reads an ultra as a custom goal with its distance', () {
      final parsed = parsePlanRequestInputs(_inputs({
        'goalEvent': 'custom',
        'goalDistanceM': 56000,
        'goalTimeSec': 30 * 3600,
      }))!;
      expect(parsed.goalEvent, GoalEvent.custom);
      expect(parsed.goalDistanceM, 56000);
      expect(parsed.goalTimeSec, 30 * 3600);
      expect(parsePlanRequestInputs(_inputs({}))!.goalDistanceM, isNull);
    });

    test('refuses an ultra distance outside the band or on a road rung', () {
      for (final override in <Map<String, dynamic>>[
        {'goalEvent': 'custom'},
        {'goalEvent': 'custom', 'goalDistanceM': null},
        {'goalEvent': 'custom', 'goalDistanceM': '56000'},
        {'goalEvent': 'custom', 'goalDistanceM': 42195},
        {'goalEvent': 'custom', 'goalDistanceM': 400001},
        {'goalEvent': 'distance_full', 'goalDistanceM': 56000},
      ]) {
        expect(parsePlanRequestInputs(_inputs(override)), isNull,
            reason: '$override');
      }
    });

    test('accepts integral doubles as whole numbers', () {
      final parsed =
          parsePlanRequestInputs(_inputs({'daysPerWeek': 5.0, 'weeks': 10.0}))!;
      expect(parsed.daysPerWeek, 5);
      expect(parsed.weeks, 10);
    });
  });

  test('planRequestErrorKind mirrors the web mapping', () {
    expect(planRequestErrorKind(401, null),
        PlanRequestErrorKind.notAuthenticated);
    expect(planRequestErrorKind(403, 'ai_disclosure_required'),
        PlanRequestErrorKind.consent);
    expect(planRequestErrorKind(403, null), PlanRequestErrorKind.unavailable);
    expect(planRequestErrorKind(429, null), PlanRequestErrorKind.dailyLimit);
    expect(planRequestErrorKind(400, null), PlanRequestErrorKind.invalid);
    expect(planRequestErrorKind(422, null), PlanRequestErrorKind.notUnderstood);
    expect(planRequestErrorKind(502, null), PlanRequestErrorKind.unavailable);
  });

  test('a blank WEB_BASE_URL posts to production, never to a relative path',
      () async {
    dotenv.loadFromString(envString: 'WEB_BASE_URL=');
    addTearDown(dotenv.clean);
    final fake = _Fake([_ok(_inputs()), _ok(_inputs())]);
    for (final baseUrl in [null, ' ']) {
      await requestPlanInputs(
        'A sub-2 half on 14 March',
        '2026-10-15',
        post: fake.post,
        currentToken: () async => 'tok',
        baseUrl: baseUrl,
      );
    }
    expect(fake.calls.map((c) => '${c.url}'), [
      'https://threkir.com/api/coach/plan-request',
      'https://threkir.com/api/coach/plan-request',
    ]);
  });
}
