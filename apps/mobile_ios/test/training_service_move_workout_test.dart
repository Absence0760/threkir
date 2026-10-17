/// Pins `TrainingService.moveWorkout` (issue #1186, decisions § 2073): a move
/// is one `move_plan_workout` RPC, never a direct `plan_workouts` date update,
/// which on a generated week always meets the row already on that day.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// What the RPC answers: the swapped workout's id, or null.
  Object? swapped;

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
      res.write(jsonEncode(swapped));
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
  });

  tearDown(() async {
    client.dispose();
    await fake.close();
  });

  test('a move is one move_plan_workout call and returns the swapped id',
      () async {
    fake.swapped = 'rest-thu';
    final swapped = await training.moveWorkout('tempo-tue', '2031-03-13');

    expect(swapped, 'rest-thu');
    expect(fake.requests.map((r) => '${r.method} ${r.path}'),
        ['POST /rest/v1/rpc/move_plan_workout']);
    expect(fake.requests.single.body,
        {'p_workout_id': 'tempo-tue', 'p_date': '2031-03-13'});
  });

  test('a move onto a free day returns null', () async {
    expect(await training.moveWorkout('tempo-tue', '2031-03-14'), isNull);
  });

  test('a refusal reaches the caller', () async {
    fake.errorCode = '22023';
    await expectLater(training.moveWorkout('done-wed', '2031-03-13'),
        throwsA(isA<PostgrestException>()));
  });
}
