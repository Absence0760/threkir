import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// `request_distance_recompute` refuses with two SQLSTATEs the run-detail
/// screen renders as different messages: 42501 (not the caller's run, or no
/// such run) and 22000 (no stored track). The fake sits at the http boundary
/// and answers with the real PostgREST error shape, so the PostgREST builder
/// and ApiClient's mapping both run as real code.
class _FakeRpc extends http.BaseClient {
  Map<String, dynamic>? error;
  final List<http.Request> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request as http.Request);
    if (error != null) return _json(error!, 400, request);
    return http.StreamedResponse(
      const Stream.empty(),
      204,
      request: request,
    );
  }

  static http.StreamedResponse _json(
          Object payload, int status, http.BaseRequest request) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(payload))),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
}

Map<String, dynamic> _pgError(String code, String message) => {
      'code': code,
      'details': null,
      'hint': null,
      'message': message,
    };

void main() {
  late _FakeRpc fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() {
    fake = _FakeRpc();
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  test('calls the RPC with the run id and completes on success', () async {
    await api.requestDistanceRecompute('run-1');

    expect(fake.calls, hasLength(1));
    final call = fake.calls.single;
    expect(call.method, 'POST');
    expect(call.url.path, '/rest/v1/rpc/request_distance_recompute');
    expect(jsonDecode(call.body), {'p_run_id': 'run-1'});
  });

  test('42501 surfaces as a notAuthorized refusal', () async {
    fake.error = _pgError(
        '42501', 'request_distance_recompute: not authorized');

    await expectLater(
      api.requestDistanceRecompute('run-1'),
      throwsA(isA<DistanceRecomputeRefused>().having(
          (e) => e.reason, 'reason', DistanceRecomputeRefusal.notAuthorized)),
    );
  });

  test('22000 surfaces as a noTrack refusal', () async {
    fake.error =
        _pgError('22000', 'request_distance_recompute: run has no track');

    await expectLater(
      api.requestDistanceRecompute('run-1'),
      throwsA(isA<DistanceRecomputeRefused>().having(
          (e) => e.reason, 'reason', DistanceRecomputeRefusal.noTrack)),
    );
  });

  test('any other failure is rethrown unchanged', () async {
    fake.error = _pgError('XX000', 'boom');

    await expectLater(
      api.requestDistanceRecompute('run-1'),
      throwsA(isA<PostgrestException>()
          .having((e) => e.code, 'code', 'XX000')),
    );
  });
}
