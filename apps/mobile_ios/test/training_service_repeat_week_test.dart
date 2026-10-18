/// Pins `TrainingService.repeatPlanWeek` (decisions § 2201): repeating a week
/// is one `repeat_plan_week` call carrying the runner's today and the week a
/// race plan drops, and the overlap refusal (23P01) reaches the caller as
/// [ActivePlanExistsError].
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/plan_repeat_week.dart';
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

  /// When set, the RPC answers with this SQLSTATE instead.
  String? errorCode;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final raw = await utf8.decoder.bind(req).join();
    requests.add(_Request(
        req.method, req.uri.path, raw.isEmpty ? null : jsonDecode(raw)));
    final res = req.response..headers.contentType = ContentType.json;
    if (errorCode != null) {
      res.statusCode = HttpStatus.badRequest;
      res.write(jsonEncode({'code': errorCode, 'message': 'refused'}));
    } else {
      res.write(jsonEncode('new-week-id'));
    }
    await res.close();
  }
}

const _raceChange = RepeatWeekChange(
  weekId: 'week-4',
  copyIndex: 5,
  copyStartIso: '2031-03-16',
  dropWeekId: 'week-6',
  endIso: '2031-04-20',
  raceDateIso: '2031-04-20',
);

void main() {
  late _FakePostgrest fake;
  late SupabaseClient client;
  late TrainingService training;

  setUp(() async {
    fake = await _FakePostgrest.start();
    client = SupabaseClient('http://127.0.0.1:${fake.port}', 'eyJ.local.test');
    training = TrainingService.withClient(client);
  });

  tearDown(() async {
    client.dispose();
    await fake.close();
  });

  test('a repeat is one repeat_plan_week call with the week it drops',
      () async {
    await training.repeatPlanWeek('plan-1', _raceChange, '2031-03-12');

    expect(fake.requests.map((r) => '${r.method} ${r.path}'),
        ['POST /rest/v1/rpc/repeat_plan_week']);
    expect(fake.requests.single.body, {
      'p_plan_id': 'plan-1',
      'p_today': '2031-03-12',
      'p_week_id': 'week-4',
      'p_drop_week_id': 'week-6',
    });
  });

  test('a plan without a race sends no week to drop', () async {
    const change = RepeatWeekChange(
      weekId: 'week-4',
      copyIndex: 5,
      copyStartIso: '2031-03-16',
      dropWeekId: null,
      endIso: '2031-04-26',
      raceDateIso: null,
    );
    await training.repeatPlanWeek('plan-1', change, '2031-03-12');
    expect((fake.requests.single.body! as Map)['p_drop_week_id'], isNull);
  });

  test('running into another active plan reads as ActivePlanExistsError',
      () async {
    fake.errorCode = '23P01';
    await expectLater(
        training.repeatPlanWeek('plan-1', _raceChange, '2031-03-12'),
        throwsA(isA<ActivePlanExistsError>()));
  });
}
