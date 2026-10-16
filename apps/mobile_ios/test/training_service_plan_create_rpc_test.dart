/// Pins how `TrainingService` creates and clones plans (decisions § 2050):
/// one RPC that resolves overlapping active plans and writes the plan, its
/// weeks and its workouts in a single transaction, carrying the runner's
/// overlap choice. Before it the client completed or trimmed the overlapped
/// plans first and inserted afterwards, so a failed insert left the old plan
/// changed with no new plan to show for it.
///
/// The fixture is a loopback PostgREST stand-in that records every request,
/// so the test can assert that no table write happens beside the RPC.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show TrainingPlanRow;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/training.dart';
import '../lib/training_service.dart';

class _Request {
  _Request(this.method, this.path, this.body);
  final String method;
  final String path;
  final Object? body;
}

class _FakePostgrest {
  _FakePostgrest(this._server) {
    _server.listen(_handle);
  }

  static Future<_FakePostgrest> start() async =>
      _FakePostgrest(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<_Request> requests = [];

  /// When set, every RPC answers with this SQLSTATE instead of an id.
  String? rpcErrorCode;

  /// What a list read of `training_plans` (the active-plan lookup) returns.
  List<Map<String, Object?>> activePlans = const [];

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final path = req.uri.path;
    requests.add(_Request(req.method, path, raw.isEmpty ? null : jsonDecode(raw)));
    final res = req.response..headers.contentType = ContentType.json;
    if (path.startsWith('/rest/v1/rpc/')) {
      if (rpcErrorCode != null) {
        res.statusCode = HttpStatus.conflict;
        res.write(jsonEncode({
          'code': rpcErrorCode,
          'message': 'these dates overlap an active training plan',
        }));
      } else {
        res.write(jsonEncode('new-plan-id'));
      }
    } else if (req.method == 'GET' &&
        path == '/rest/v1/training_plans' &&
        !(req.headers.value('accept') ?? '').contains('vnd.pgrst.object')) {
      res.write(jsonEncode(activePlans));
    } else if (req.method == 'GET' && path == '/rest/v1/training_plans') {
      res.write(jsonEncode({
        'id': 'new-plan-id',
        'user_id': 'viewer-1',
        'name': 'Spring 10k',
        'goal_event': 'distance_10k',
        'goal_distance_m': 10000,
        'start_date': '2031-03-02',
        'end_date': '2031-04-26',
        'days_per_week': 4,
        'status': 'active',
        'source': 'generated',
        'is_template': false,
        'is_public_template': false,
      }));
    } else {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode({'message': 'unexpected request', 'code': 'XX000'}));
    }
    await res.close();
  }
}

void main() {
  late _FakePostgrest fake;
  late SupabaseClient client;
  late TrainingService training;

  setUp(() async {
    fake = await _FakePostgrest.start();
    client = SupabaseClient('http://127.0.0.1:${fake.port}', 'eyJ.local.test');
    training = TrainingService.withClient(client);
    await client.auth.recoverSession(jsonEncode({
      'access_token': 'eyJ.local.test',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000,
      'refresh_token': 'local-refresh',
      'user': {
        'id': 'viewer-1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
  });

  tearDown(() async {
    client.dispose();
    await fake.close();
  });

  final start = DateTime(2031, 3, 2);
  GeneratedPlan plan() => generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance10k,
        startDate: start,
        daysPerWeek: 4,
      ));

  Future<TrainingPlanRow> create(GeneratedPlan generated,
          {PlanOverlapAction? onOverlap}) =>
      onOverlap == null
          ? training.createPlan(
              name: '  Spring 10k  ',
              goalEvent: GoalEvent.distance10k,
              goalDistanceM: 10000,
              startDate: start,
              daysPerWeek: 4,
              notes: '   ',
              generated: generated,
            )
          : training.createPlan(
              name: '  Spring 10k  ',
              goalEvent: GoalEvent.distance10k,
              goalDistanceM: 10000,
              startDate: start,
              daysPerWeek: 4,
              notes: '   ',
              generated: generated,
              onOverlap: onOverlap,
            );

  test('createPlan writes through create_training_plan, refusing overlaps by default',
      () async {
    final generated = plan();
    final created = await create(generated);

    expect(created.id, 'new-plan-id');
    final writes = fake.requests.where((r) => r.method != 'GET').toList();
    expect(writes.map((r) => r.path), ['/rest/v1/rpc/create_training_plan'],
        reason: 'no table insert or overlap update may happen beside the RPC');
    final body = writes.single.body! as Map<String, dynamic>;
    expect(body['p_overlap'], 'refuse');
    final p = body['p_plan'] as Map<String, dynamic>;
    expect(p['name'], 'Spring 10k');
    expect(p['goal_event'], 'distance_10k');
    expect(p['start_date'], '2031-03-02');
    expect(p['end_date'], toIsoDate(generated.endDate));
    expect(p['days_per_week'], 4);
    expect(p['notes'], isNull);
    expect(p.containsKey('user_id'), isFalse);
    final weeks = body['p_weeks'] as List;
    expect(weeks, hasLength(generated.weeks.length));
    final firstWeek = weeks.first as Map<String, dynamic>;
    expect(firstWeek['week_index'], generated.weeks.first.weekIndex);
    expect((firstWeek['workouts'] as List), hasLength(generated.weeks.first.workouts.length));
    final firstWorkout = (firstWeek['workouts'] as List).first as Map<String, dynamic>;
    expect(firstWorkout['kind'], isA<String>());
    expect(firstWorkout['scheduled_date'],
        toIsoDate(generated.weeks.first.workouts.first.scheduledDate));
  });

  test('createPlan carries the runner\'s overlap choice', () async {
    await create(plan(), onOverlap: PlanOverlapAction.trim);
    final body = fake.requests
        .singleWhere((r) => r.path == '/rest/v1/rpc/create_training_plan')
        .body! as Map<String, dynamic>;
    expect(body['p_overlap'], 'trim');
  });

  test('an overlap refusal surfaces as ActivePlanExistsError', () async {
    fake.rpcErrorCode = '23P01';
    await expectLater(create(plan()), throwsA(isA<ActivePlanExistsError>()));
  });

  test('the clone RPCs carry the overlap choice and map a refusal', () async {
    await training.clonePlanTemplate(
        templateId: 'tmpl-1', startDate: start, onOverlap: PlanOverlapAction.replace);
    await training.clonePublicPlan(templateId: 'tmpl-2', startDate: start);
    final template = fake.requests
        .singleWhere((r) => r.path == '/rest/v1/rpc/clone_plan_template')
        .body! as Map<String, dynamic>;
    final public = fake.requests
        .singleWhere((r) => r.path == '/rest/v1/rpc/clone_public_plan')
        .body! as Map<String, dynamic>;
    expect(template, {
      'template_id': 'tmpl-1',
      'new_start_date': '2031-03-02',
      'p_overlap': 'replace',
    });
    expect(public['p_overlap'], 'refuse');

    fake.rpcErrorCode = '23P01';
    await expectLater(
      training.clonePublicPlan(templateId: 'tmpl-2', startDate: start),
      throwsA(isA<ActivePlanExistsError>()),
    );
  });

  group('a trim refused for completed workouts (TR001)', () {
    Map<String, Object?> active(String name, String startIso, String endIso) => {
          'id': 'plan-$name',
          'user_id': 'viewer-1',
          'name': name,
          'goal_event': 'distance_10k',
          'goal_distance_m': 10000,
          'start_date': startIso,
          'end_date': endIso,
          'days_per_week': 4,
          'status': 'active',
          'source': 'generated',
          'is_template': false,
          'is_public_template': false,
        };

    setUp(() {
      fake.rpcErrorCode = 'TR001';
      fake.activePlans = [
        active('Winter base', '2031-01-05', '2031-03-29'),
        active('Summer 5k', '2031-06-01', '2031-07-20'),
      ];
    });

    Matcher blocked(String? planName) => isA<PlanTrimBlockedError>()
        .having((e) => e.planName, 'planName', planName)
        .having((e) => e.trimEndIso, 'trimEndIso', '2031-03-01');

    test('createPlan names the plan that runs into the new start', () async {
      await expectLater(create(plan(), onOverlap: PlanOverlapAction.trim),
          throwsA(blocked('Winter base')));
    });

    test('both clone RPCs map it the same way', () async {
      await expectLater(
        training.clonePlanTemplate(
            templateId: 'tmpl-1', startDate: start, onOverlap: PlanOverlapAction.trim),
        throwsA(blocked('Winter base')),
      );
      await expectLater(
        training.clonePublicPlan(
            templateId: 'tmpl-2', startDate: start, onOverlap: PlanOverlapAction.trim),
        throwsA(blocked('Winter base')),
      );
    });

    test('with no plan found in the way it still reports the refusal, unnamed',
        () async {
      fake.activePlans = const [];
      await expectLater(create(plan(), onOverlap: PlanOverlapAction.trim),
          throwsA(blocked(null)));
    });
  });

  test('applyRaceTaper stamps every workout it eases in the one RPC', () async {
    await training.applyRaceTaper(planId: 'plan-1', patches: {
      'w-int': {'kind': 'easy', 'target_distance_m': 6500.0},
      'w-easy': {'target_distance_m': 5200.0},
    });
    final calls = fake.requests.where((r) => r.path.startsWith('/rest/v1/'));
    expect([for (final r in calls) r.path],
        ['/rest/v1/rpc/apply_workout_adjustments']);
    final body = calls.single.body! as Map<String, dynamic>;
    expect(body['p_plan_id'], 'plan-1');
    final changes = (body['p_changes'] as List).cast<Map<String, dynamic>>();
    expect([for (final c in changes) c['id']], ['w-int', 'w-easy']);
    final stamp = changes.first['race_taper_applied_at'] as String;
    expect(DateTime.parse(stamp).isUtc, isTrue);
    expect(changes[0], {
      'id': 'w-int',
      'kind': 'easy',
      'target_distance_m': 6500.0,
      'race_taper_applied_at': stamp,
    });
    expect(changes[1], {
      'id': 'w-easy',
      'target_distance_m': 5200.0,
      'race_taper_applied_at': stamp,
    });
  });
}
