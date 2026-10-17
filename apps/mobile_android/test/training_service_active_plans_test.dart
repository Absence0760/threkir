/// Pins the `TrainingService` reads and writes plan chaining added on mobile
/// (decisions § 2008): which plan `fetchActiveOverview` shows when several
/// are active and which it names as up next, `resumePlan` refusing only on an
/// overlap (and mapping the constraint's own 23P01 when a plan appears
/// between its check and its write), and the B/C race taper landing as one
/// `apply_workout_adjustments` call. Web twins: `planOverviewFor`,
/// `resumePlan` and `applyWorkoutAdjustments` in
/// `apps/web/src/lib/core/data.ts`.
///
/// The fixture is a loopback PostgREST stand-in that records every request.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/training_service.dart';

class _Request {
  _Request(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
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

  /// Every plan the fake knows, by id. A list read returns the active ones.
  final Map<String, Map<String, Object?>> plans = {};

  /// When set, a PATCH of `training_plans` answers with this SQLSTATE.
  String? patchErrorCode;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    final path = req.uri.path;
    final query = req.uri.queryParameters;
    requests.add(_Request(req.method, path, query, raw.isEmpty ? null : jsonDecode(raw)));
    final res = req.response..headers.contentType = ContentType.json;
    if (req.method == 'GET' &&
        path == '/rest/v1/training_plans' &&
        query.containsKey('id')) {
      // A by-id read (maybeSingle sends a GET as a plain list read).
      final row = plans[query['id']!.substring('eq.'.length)];
      res.write(jsonEncode([if (row != null) row]));
    } else if (req.method == 'GET' && path == '/rest/v1/training_plans') {
      res.write(jsonEncode([
        for (final p in plans.values)
          if (p['status'] == 'active') p,
      ]));
    } else if (req.method == 'GET' && path == '/rest/v1/plan_weeks') {
      final planId = query['plan_id']!.substring('eq.'.length);
      res.write(jsonEncode([
        {
          'id': 'week-$planId',
          'plan_id': planId,
          'week_index': 0,
          'phase': 'base',
          'target_volume_m': 8000,
        },
      ]));
    } else if (req.method == 'GET' && path == '/rest/v1/plan_workouts') {
      res.write(jsonEncode(<Object>[]));
    } else if (req.method == 'PATCH' && path == '/rest/v1/training_plans') {
      if (patchErrorCode != null) {
        res.statusCode = HttpStatus.conflict;
        res.write(jsonEncode({
          'code': patchErrorCode,
          'message': 'conflicting key value violates exclusion constraint',
        }));
      } else {
        res.statusCode = HttpStatus.noContent;
      }
    } else if (req.method == 'POST' &&
        path == '/rest/v1/rpc/apply_workout_adjustments') {
      res.statusCode = HttpStatus.noContent;
    } else {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode({'message': 'unexpected request', 'code': 'XX000'}));
    }
    await res.close();
  }
}

String _day(int offset) {
  final now = DateTime.now();
  final d = DateTime(now.year, now.month, now.day + offset);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, Object?> _plan(String id, int startOffset, int endOffset,
        {String status = 'active'}) =>
    {
      'id': id,
      'user_id': 'viewer-1',
      'name': 'Plan $id',
      'goal_event': 'distance_10k',
      'goal_distance_m': 10000,
      'start_date': _day(startOffset),
      'end_date': _day(endOffset),
      'days_per_week': 4,
      'status': status,
      'source': 'generated',
      'is_template': false,
      'is_public_template': false,
    };

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

  void addPlans(List<Map<String, Object?>> rows) {
    for (final r in rows) {
      fake.plans[r['id']! as String] = r;
    }
  }

  List<_Request> patches() => [
        for (final r in fake.requests)
          if (r.method == 'PATCH') r,
      ];

  test('fetchMyPlans reads only the viewer\'s own plans, never templates',
      () async {
    await training.fetchMyPlans();
    final read = fake.requests.singleWhere(
        (r) => r.method == 'GET' && r.path == '/rest/v1/training_plans');
    expect(read.query['user_id'], 'eq.viewer-1');
    expect(read.query['is_template'], 'eq.false');
  });

  group('fetchActiveOverview', () {
    test('shows the plan covering today and names the nearer queued plan as up next',
        () async {
      addPlans([
        _plan('ended', -60, -30),
        _plan('current', -5, 20),
        _plan('far', 60, 90),
        _plan('near', 21, 59),
      ]);
      final o = await training.fetchActiveOverview();
      expect(o?.plan.id, 'current');
      expect(o?.upcomingPlan?.id, 'near');
    });

    test('between blocks it keeps the ended plan and names the queued one', () async {
      addPlans([_plan('ended', -30, -3), _plan('queued', 4, 40)]);
      final o = await training.fetchActiveOverview();
      expect(o?.plan.id, 'ended');
      expect(o?.upcomingPlan?.id, 'queued');
    });

    test('with only queued plans it shows the first and names the one after it',
        () async {
      addPlans([_plan('second', 50, 80), _plan('first', 10, 40)]);
      final o = await training.fetchActiveOverview();
      expect(o?.plan.id, 'first');
      expect(o?.upcomingPlan?.id, 'second');
    });

    test('a single queued plan has nothing up next', () async {
      addPlans([_plan('only', 10, 40)]);
      final o = await training.fetchActiveOverview();
      expect(o?.plan.id, 'only');
      expect(o?.upcomingPlan, isNull);
    });

    test('no active plan is no overview, and no plan read', () async {
      addPlans([_plan('paused', -5, 20, status: 'paused')]);
      expect(await training.fetchActiveOverview(), isNull);
      expect(fake.requests.where((r) => r.path == '/rest/v1/plan_weeks'), isEmpty);
    });
  });

  group('resumePlan', () {
    test('refuses, without writing, when an active plan overlaps the paused one',
        () async {
      addPlans([
        _plan('paused', 10, 40, status: 'paused'),
        _plan('active', 30, 60),
      ]);
      await expectLater(
          training.resumePlan('paused'), throwsA(isA<ActivePlanExistsError>()));
      expect(patches(), isEmpty);
    });

    test('resumes beside active plans queued clear of it', () async {
      addPlans([
        _plan('paused', 10, 40, status: 'paused'),
        _plan('before', -20, 9),
        _plan('after', 41, 70),
      ]);
      await training.resumePlan('paused');
      final sent = patches().single;
      expect(sent.query['id'], 'eq.paused');
      expect(sent.body, {'status': 'active'});
    });

    test('an overlap the constraint catches after the check still reads as one',
        () async {
      addPlans([_plan('paused', 10, 40, status: 'paused')]);
      fake.patchErrorCode = '23P01';
      await expectLater(
          training.resumePlan('paused'), throwsA(isA<ActivePlanExistsError>()));
    });
  });

  test('applyRaceTaper writes every non-empty patch in one adjustments call',
      () async {
    await training.applyRaceTaper(planId: 'plan-1', patches: {
      'wo-1': {'target_distance_m': 6000, 'target_pace_sec_per_km': null},
      'wo-2': <String, Object?>{},
      'wo-3': {'structure': null},
    });
    final calls = [
      for (final r in fake.requests)
        if (r.path == '/rest/v1/rpc/apply_workout_adjustments') r,
    ];
    expect(calls, hasLength(1));
    final body = calls.single.body as Map;
    expect(body['p_plan_id'], 'plan-1');
    final changes = (body['p_changes'] as List).cast<Map>();
    // The empty wo-2 patch is neither sent nor stamped: a stamp on a
    // workout the taper left alone would hide it from every later taper.
    expect(changes.map((c) => c['id']), ['wo-1', 'wo-3']);
    final stamp = changes.first['race_taper_applied_at'];
    expect(stamp, isA<String>());
    expect(changes, [
      {'id': 'wo-1', 'target_distance_m': 6000, 'target_pace_sec_per_km': null, 'race_taper_applied_at': stamp},
      {'id': 'wo-3', 'structure': null, 'race_taper_applied_at': stamp},
    ]);
    expect(fake.requests.where((r) => r.method == 'PATCH'), isEmpty);
  });

  test('a taper with nothing to change sends nothing', () async {
    await training.applyRaceTaper(planId: 'plan-1', patches: {
      'wo-1': <String, Object?>{},
    });
    expect(fake.requests, isEmpty);
  });
}
