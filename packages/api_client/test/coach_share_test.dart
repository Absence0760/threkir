import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Share with coach (issue #1215 Phase 3) names its RPCs, parameters and
/// refusal codes by hand, so a renamed parameter or a misread SQLSTATE reaches
/// the share sheet as a generic failure. Same http-boundary fake as
/// direct_messages_test.dart: the PostgREST builders above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object> bodyByPath = {};
  final Map<String, int> statusByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object body = const <dynamic>[];
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

const _sharePath = '/rest/v1/rpc/share_coach_message';
const _gatePath = '/rest/v1/rpc/coach_share_enabled';
const _coachMessagesPath = '/rest/v1/coach_messages';
const _threadsPath = '/rest/v1/rpc/dm_threads';

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
    fake.statusByPath[_sharePath] = status;
    fake.bodyByPath[_sharePath] = {'code': code, 'message': message};
  }

  group('shareCoachMessage', () {
    test(
      'posts the answer, the coach and the picked indexes, returns the row',
      () async {
        fake.bodyByPath[_sharePath] = {
          'id': 'dm-1',
          'conversation_id': 'c-1',
          'kind': 'coach_share',
          'coach_message_id': 'cm-1',
          'sender_id': 'user-1',
          'recipient_id': 'coach-1',
          'body': 'Keep the long run easy.',
          'created_at': '2026-11-10T08:00:00Z',
        };

        final row = await api.shareCoachMessage('cm-1', 'coach-1', [0, 2]);

        final req = fake.to(_sharePath).single as http.Request;
        expect(req.method, 'POST');
        expect(jsonDecode(req.body), {
          'p_coach_message_id': 'cm-1',
          'p_coach_id': 'coach-1',
          'p_paragraphs': [0, 2],
        });
        expect(row.kind, 'coach_share');
        expect(row.coachMessageId, 'cm-1');
        expect(row.recipientId, 'coach-1');
        expect(row.body, 'Keep the long run easy.');
      },
    );

    test(
      'not your coach, a block or a declined request is DmSendNotPermitted',
      () async {
        refuse(403, '42501', 'share_coach_message: not allowed');
        expect(
          api.shareCoachMessage('cm-1', 'coach-1', [0]),
          throwsA(isA<DmSendNotPermitted>()),
        );
      },
    );

    test('the gate being closed is CoachShareUnavailable', () async {
      refuse(400, '0A000', 'share_coach_message: not available');
      expect(
        api.shareCoachMessage('cm-1', 'coach-1', [0]),
        throwsA(isA<CoachShareUnavailable>()),
      );
    });

    test('the request cap is DmRequestCapReached', () async {
      refuse(400, '54000', 'direct_messages: request cap');
      expect(
        api.shareCoachMessage('cm-1', 'coach-1', [0]),
        throwsA(isA<DmRequestCapReached>()),
      );
    });

    test(
      'the send throttle stays a PostgrestException for the shared parser',
      () async {
        refuse(
          400,
          'P0001',
          'rate limit exceeded for send_direct_message_burst, retry in 41s',
        );
        expect(
          api.shareCoachMessage('cm-1', 'coach-1', [0]),
          throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', 'P0001'),
          ),
        );
      },
    );

    test('an answer that is gone surfaces its P0002', () async {
      refuse(404, 'P0002', 'share_coach_message: answer not found');
      expect(
        api.shareCoachMessage('cm-9', 'coach-1', [0]),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'P0002'),
        ),
      );
    });
  });

  group('fetchCoachShareEnabled', () {
    test('reads the gate as a GET', () async {
      fake.bodyByPath[_gatePath] = true;
      expect(await api.fetchCoachShareEnabled(), isTrue);
      expect(fake.to(_gatePath).single.method, 'GET');
    });

    test('false reads as off', () async {
      fake.bodyByPath[_gatePath] = false;
      expect(await api.fetchCoachShareEnabled(), isFalse);
    });

    test('a failed read fails closed', () async {
      fake.statusByPath[_gatePath] = 500;
      fake.bodyByPath[_gatePath] = {'code': 'XX000', 'message': 'boom'};
      expect(await api.fetchCoachShareEnabled(), isFalse);
    });
  });

  group('fetchCoachMessagePlanId', () {
    test('reads the plan id of one answer', () async {
      fake.bodyByPath[_coachMessagesPath] = {'plan_id': 'plan-7'};
      expect(await api.fetchCoachMessagePlanId('cm-1'), 'plan-7');
      final req = fake.to(_coachMessagesPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters['select'], 'plan_id');
      expect(req.url.queryParameters['id'], 'eq.cm-1');
    });

    test('an answer outside a plan answers null', () async {
      fake.bodyByPath[_coachMessagesPath] = {'plan_id': null};
      expect(await api.fetchCoachMessagePlanId('cm-1'), isNull);
    });
  });

  group('fetchDmThreads last_kind', () {
    Map<String, dynamic> row(String id, Object? kind) => {
      'conversation_id': 'c-$id',
      'partner_id': id,
      'last_body': 'body $id',
      'last_at': '2026-10-14T09:30:00Z',
      'last_from_me': false,
      'unread': 0,
      if (kind != null) 'last_kind': kind,
    };

    test('coach_share is read; missing or unknown reads as text', () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = [
        row('p-1', 'coach_share'),
        row('p-2', 'text'),
        row('p-3', null),
        row('p-4', 'poll'),
      ];

      final threads = await api.fetchDmThreads();

      expect(threads.map((t) => t.lastKind), [
        'coach_share',
        'text',
        'text',
        'text',
      ]);
    });

    test('copyWith keeps the kind', () {
      final t = DmThread(
        conversationId: 'c-1',
        partnerId: 'p-1',
        lastBody: 'x',
        lastAt: DateTime.utc(2026),
        lastFromMe: false,
        unread: 0,
        lastKind: 'coach_share',
      );
      expect(t.copyWith(unread: 2).lastKind, 'coach_share');
    });
  });
}
