import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `assignPlanToAthlete` types the overlap refusal `assign_plan_to_athlete`
/// raises as 23P01 (migration 20270830000008), so the coaching screen can say
/// which dates to pick; every other refusal stays the raw raise text.
/// `fetchAthletePlanOverview` hands back every active plan beside the one it
/// picked, which is what the screen names as the dates to clear.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object> bodyByPath = {};
  int status = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final match = bodyByPath.entries
        .where((e) => request.url.path.endsWith(e.key))
        .map((e) => e.value);
    final body = match.isEmpty ? const <dynamic>[] : match.first;
    final isRpc = request.url.path.contains('/rpc/');
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      isRpc ? status : 200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

Map<String, dynamic> _plan(String id, String start, String end) => {
      'id': id,
      'user_id': 'athlete-1',
      'name': 'Plan $id',
      'goal_event': 'distance_10k',
      'goal_distance_m': 10000,
      'start_date': start,
      'end_date': end,
      'days_per_week': 4,
      'status': 'active',
      'source': 'generated',
      'is_template': false,
      'is_public_template': false,
    };

void main() {
  late _FakeHttp fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() async {
    fake = _FakeHttp();
    client = SupabaseClient('http://127.0.0.1:24321', 'test-anon-key',
        httpClient: fake);
    await client.auth.setInitialSession(jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'coach-1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  Future<String> assign() => api.assignPlanToAthlete(
        sourcePlanId: 'src-1',
        athleteId: 'athlete-1',
        startDate: DateTime(2031, 3, 2),
      );

  test('an overlap refusal (23P01) is a PlanAssignOverlapException carrying '
      'the server text', () async {
    fake.status = 409;
    fake.bodyByPath['/rpc/assign_plan_to_athlete'] = {
      'code': '23P01',
      'message': 'assign_plan_to_athlete: these dates overlap the athlete\'s '
          'active plan "Spring" (2031-03-01 to 2031-04-01)',
    };
    await expectLater(
      assign(),
      throwsA(isA<PlanAssignOverlapException>()
          .having((e) => e.message, 'message', contains('"Spring"'))),
    );
  });

  test('any other refusal stays an Exception with the raise text', () async {
    fake.status = 400;
    fake.bodyByPath['/rpc/assign_plan_to_athlete'] = {
      'code': 'P0001',
      'message': 'assign_plan_to_athlete: not an active coach of athlete x',
    };
    await expectLater(
      assign(),
      throwsA(isA<Exception>()
          .having((e) => e, 'type', isNot(isA<PlanAssignOverlapException>()))
          .having((e) => '$e', 'text', contains('not an active coach'))),
    );
  });

  test('fetchAthletePlanOverview carries every active plan beside the pick',
      () async {
    fake.bodyByPath['/training_plans'] = [
      _plan('a', '2031-01-01', '2031-02-01'),
      _plan('b', '2031-03-01', '2031-04-01'),
    ];
    final o = await api.fetchAthletePlanOverview('athlete-1',
        pick: (active) => active.first);
    expect(o?.plan.id, 'a');
    expect(o?.activePlans.map((p) => p.id), ['a', 'b']);
  });

  test('fetchMyPlans reads only the coach\'s own non-template plans', () async {
    await api.fetchMyPlans();
    final q = fake.requests.single.url.queryParameters;
    expect(q['user_id'], 'eq.coach-1');
    expect(q['is_template'], 'eq.false');
  });
}
