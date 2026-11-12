import 'dart:convert';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The direct-message wrappers name their table, RPC, filters and refusal
/// codes by hand, so a renamed column or a misread SQLSTATE reaches the
/// composer as a generic failure. The fake sits at the http boundary and
/// answers by path; the PostgREST builders and ApiClient above it are real.
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

const _threadsPath = '/rest/v1/rpc/dm_threads';
const _profilesPath = '/rest/v1/user_profiles';
const _messagesPath = '/rest/v1/direct_messages';

Map<String, dynamic> _message(
  String id, {
  String sender = 'user-1',
  String recipient = 'other-1',
  String createdAt = '2026-10-14T08:00:00Z',
  String? routeId,
  String? seenAt,
}) =>
    {
      'id': id,
      'conversation_id': 'c-1',
      'kind': 'text',
      'sender_id': sender,
      'recipient_id': recipient,
      'body': 'Body $id',
      'created_at': createdAt,
      'seen_at': seenAt,
      'route_id': routeId,
    };

Future<void> _signIn(SupabaseClient client) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'user-1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

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

  group('fetchDmThreads', () {
    test('reads dm_threads as a GET and joins each partner name', () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = [
        {
          'conversation_id': 'c-p-1',
          'partner_id': 'p-1',
          'last_body': 'see you Saturday',
          'last_at': '2026-10-14T09:30:00Z',
          'last_from_me': true,
          'unread': 0,
        },
        {
          'conversation_id': 'c-p-2',
          'partner_id': 'p-2',
          'last_body': 'nice run',
          'last_at': '2026-10-13T18:00:00Z',
          'last_from_me': false,
          'unread': 3,
          'marked_unread': true,
          'request': true,
        },
      ];
      fake.bodyByPath[_profilesPath] = [
        {'id': 'p-1', 'display_name': 'Ada', 'avatar_url': null},
        {'id': 'p-2', 'display_name': 'Grace', 'avatar_url': 'https://a/g.png'},
      ];

      final threads = await api.fetchDmThreads();

      final req = fake.to(_threadsPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, isEmpty);
      expect(threads.map((t) => t.partnerId), ['p-1', 'p-2']);
      expect(threads.map((t) => t.partnerName), ['Ada', 'Grace']);
      expect(threads.last.partnerAvatarUrl, 'https://a/g.png');
      expect(threads.map((t) => t.unread), [0, 3]);
      expect(threads.map((t) => t.lastFromMe), [true, false]);
      expect(threads.first.lastAt, DateTime.utc(2026, 10, 14, 9, 30));
      expect(threads.map((t) => t.conversationId), ['c-p-1', 'c-p-2']);
      expect(threads.map((t) => t.muted), [false, false]);
      expect(threads.map((t) => t.archived), [false, false]);
      expect(threads.map((t) => t.markedUnread), [false, true]);
      expect(threads.map((t) => t.request), [false, true]);

      final profileReq = fake.to(_profilesPath).single;
      expect(profileReq.url.queryParameters['select'],
          'id,display_name,avatar_url');
      expect(profileReq.url.queryParameters['id'], 'in.("p-1","p-2")');
    });

    test('an empty inbox answers empty and asks for no profiles', () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = const <dynamic>[];

      expect(await api.fetchDmThreads(), isEmpty);
      expect(fake.to(_profilesPath), isEmpty);
    });

    test('a failed name read keeps the conversations with no names', () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = [
        {
          'conversation_id': 'c-p-1',
          'partner_id': 'p-1',
          'last_body': 'hi',
          'last_at': '2026-10-14T09:30:00Z',
          'last_from_me': false,
          'unread': 1,
        },
      ];
      fake.statusByPath[_profilesPath] = 500;
      fake.bodyByPath[_profilesPath] = {'message': 'boom'};

      final threads = await api.fetchDmThreads();

      expect(threads.single.partnerId, 'p-1');
      expect(threads.single.partnerName, isNull);
    });

    test('a deleted partner and an unsent latest message map, and only the '
        'live partner is looked up', () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = [
        {
          'conversation_id': 'c-p-1',
          'partner_id': 'p-1',
          'deleted_partner_key': null,
          'last_body': null,
          'last_unsent': true,
          'last_at': '2026-10-14T09:30:00Z',
          'last_from_me': false,
          'unread': 0,
        },
        {
          'conversation_id': 'c-deleted',
          'partner_id': null,
          'deleted_partner_key': 'k-1',
          'last_body': 'are you there?',
          'last_unsent': false,
          'last_at': '2026-10-13T09:30:00Z',
          'last_from_me': true,
          'unread': 0,
        },
      ];
      fake.bodyByPath[_profilesPath] = [
        {'id': 'p-1', 'display_name': 'Ada', 'avatar_url': null},
      ];

      final threads = await api.fetchDmThreads();

      expect(threads.first.lastUnsent, isTrue);
      expect(threads.first.lastBody, isNull);
      expect(threads.last.partnerId, isNull);
      expect(threads.last.deletedPartnerKey, 'k-1');
      expect(threads.last.threadKey, 'k-1');
      expect(threads.last.target, isA<DmDeletedPartnerThread>());
      expect(fake.to(_profilesPath).single.url.queryParameters['id'],
          'in.("p-1")');
    });

    test('a failed inbox read throws rather than reading as empty', () async {
      await _signIn(client);
      fake.statusByPath[_threadsPath] = 500;
      fake.bodyByPath[_threadsPath] = {'message': 'boom'};

      expect(api.fetchDmThreads(), throwsA(isA<PostgrestException>()));
    });

    test('signed out answers empty without a wire call', () async {
      expect(await api.fetchDmThreads(), isEmpty);
      expect(fake.requests, isEmpty);
    });
  });

  group('fetchDmBadgeStates', () {
    test('reads each conversation\'s unread, mute and archive state and no names',
        () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = [
        {
          'conversation_id': 'c-1',
          'partner_id': 'p-1',
          'last_at': '2026-10-14T09:30:00Z',
          'unread': 2,
          'muted': false,
          'archived': false,
        },
        {
          'conversation_id': 'c-2',
          'partner_id': 'p-2',
          'last_at': '2026-10-13T09:30:00Z',
          'unread': 5,
          'muted': true,
          'archived': false,
        },
        {
          'conversation_id': 'c-3',
          'partner_id': 'p-3',
          'last_at': '2026-10-12T09:30:00Z',
          'unread': 1,
          'muted': false,
          'archived': true,
        },
        {
          'conversation_id': 'c-4',
          'partner_id': 'p-4',
          'last_at': '2026-10-11T09:30:00Z',
          'unread': 3,
          'muted': false,
          'archived': false,
          'request': true,
        },
      ];

      expect(await api.fetchDmBadgeStates(), [
        (conversationId: 'c-1', unread: 2, muted: false, archived: false, request: false),
        (conversationId: 'c-2', unread: 5, muted: true, archived: false, request: false),
        (conversationId: 'c-3', unread: 1, muted: false, archived: true, request: false),
        (conversationId: 'c-4', unread: 3, muted: false, archived: false, request: true),
      ]);
      expect(fake.to(_threadsPath).single.method, 'GET');
      expect(fake.to(_profilesPath), isEmpty);
    });

    test('a failed read throws rather than reading as nothing unread', () async {
      await _signIn(client);
      fake.statusByPath[_threadsPath] = 500;
      fake.bodyByPath[_threadsPath] = {'message': 'boom'};

      expect(api.fetchDmBadgeStates(), throwsA(isA<PostgrestException>()));
    });

    test('signed out answers empty without a wire call', () async {
      expect(await api.fetchDmBadgeStates(), isEmpty);
      expect(fake.requests, isEmpty);
    });
  });

  group('conversation state', () {
    test('hideDmConversation sends the id and the newest message seen',
        () async {
      await _signIn(client);
      await api.hideDmConversation('c-9', throughMessageId: 'm-4');
      final req = fake.to('/rest/v1/rpc/hide_conversation').single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body),
          {'p_conversation_id': 'c-9', 'p_through_message_id': 'm-4'});
    });

    test('setDmConversationMuted sends the flag', () async {
      await _signIn(client);
      await api.setDmConversationMuted('c-9', muted: true);
      final req =
          fake.to('/rest/v1/rpc/set_conversation_muted').single as http.Request;
      expect(jsonDecode(req.body), {'p_conversation_id': 'c-9', 'p_muted': true});
    });

    test('setDmConversationArchived sends the flag', () async {
      await _signIn(client);
      await api.setDmConversationArchived('c-9', archived: false);
      final req = fake.to('/rest/v1/rpc/set_conversation_archived').single
          as http.Request;
      expect(jsonDecode(req.body),
          {'p_conversation_id': 'c-9', 'p_archived': false});
    });

    test('setDmConversationUnread sends the flag', () async {
      await _signIn(client);
      await api.setDmConversationUnread('c-9', unread: true);
      final req = fake.to('/rest/v1/rpc/set_conversation_unread').single
          as http.Request;
      expect(jsonDecode(req.body), {'p_conversation_id': 'c-9', 'p_unread': true});
    });

    test('fetchDmConversationState reads the viewer\'s request state',
        () async {
      await _signIn(client);
      fake.bodyByPath['/rest/v1/conversation_participants'] = {
        'muted_at': null,
        'archived_at': null,
        'marked_unread_at': null,
        'request_state': 'pending',
      };
      final state = await api.fetchDmConversationState('c-9');
      expect(state?.request, isTrue);
      final req = fake.to('/rest/v1/conversation_participants').single;
      expect(req.url.queryParameters['select'],
          'muted_at,archived_at,marked_unread_at,request_state');
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
    });

    test('acceptDmRequest sends the conversation id', () async {
      await _signIn(client);
      await api.acceptDmRequest('c-9');
      final req = fake.to('/rest/v1/rpc/accept_message_request').single
          as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'p_conversation_id': 'c-9'});
    });

    test('declineDmRequest sends the newest message seen and the block flag',
        () async {
      await _signIn(client);
      await api.declineDmRequest('c-9', throughMessageId: 'm-4');
      await api.declineDmRequest('c-8', throughMessageId: 'm-5', block: true);
      final reqs = fake.to('/rest/v1/rpc/decline_message_request').toList();
      expect(jsonDecode((reqs[0] as http.Request).body), {
        'p_conversation_id': 'c-9',
        'p_through_message_id': 'm-4',
        'p_block': false,
      });
      expect(jsonDecode((reqs[1] as http.Request).body), {
        'p_conversation_id': 'c-8',
        'p_through_message_id': 'm-5',
        'p_block': true,
      });
    });

    test('a conversation the viewer is not in surfaces its P0002', () async {
      await _signIn(client);
      fake.statusByPath['/rest/v1/rpc/hide_conversation'] = 404;
      fake.bodyByPath['/rest/v1/rpc/hide_conversation'] = {
        'code': 'P0002',
        'message': 'hide_conversation: conversation not found',
      };
      expect(api.hideDmConversation('c-x', throughMessageId: 'm-x'),
          throwsA(isA<PostgrestException>()));
    });
  });

  group('fetchDmThread', () {
    test('reads the newest page of the pair and returns it oldest first',
        () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = [
        _message('m-3', createdAt: '2026-10-14T08:03:00Z'),
        _message('m-2',
            sender: 'other-1',
            recipient: 'user-1',
            createdAt: '2026-10-14T08:02:00Z',
            routeId: 'route-9'),
        _message('m-1', createdAt: '2026-10-14T08:01:00Z'),
      ];

      final page = await api.fetchDmThread(const DmPartnerThread('other-1'), limit: 3);

      final req = fake.to(_messagesPath).single;
      expect(req.method, 'GET');
      final q = req.url.queryParameters;
      expect(q['sender_id'], 'in.("user-1","other-1")');
      expect(q['recipient_id'], 'in.("user-1","other-1")');
      expect(q['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      expect(q['limit'], '4');
      expect(q.containsKey('or'), isFalse);
      expect(q['select']!.split(','), isNot(contains('read_at')));
      expect(q['select']!.split(','), contains('seen_at'));
      expect(page.messages.map((m) => m.id), ['m-1', 'm-2', 'm-3']);
      expect(page.messages[1].routeId, 'route-9');
      expect(page.hasMore, isFalse);
    });

    test('one row past the limit says older messages exist and is dropped',
        () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = [
        _message('m-3', createdAt: '2026-10-14T08:03:00Z'),
        _message('m-2', createdAt: '2026-10-14T08:02:00Z'),
        _message('m-1', createdAt: '2026-10-14T08:01:00Z'),
      ];

      final page = await api.fetchDmThread(const DmPartnerThread('other-1'), limit: 2);

      expect(page.hasMore, isTrue);
      expect(page.messages.map((m) => m.id), ['m-2', 'm-3']);
    });

    test('an older page is keyed on the oldest message shown, ties by id',
        () async {
      await _signIn(client);
      final oldest = DirectMessageRow.fromJson(
          _message('m-5', createdAt: '2026-10-14T08:05:00.123456Z'));

      await api.fetchDmThread(const DmPartnerThread('other-1'), before: oldest);

      final q = fake.to(_messagesPath).single.url.queryParameters;
      expect(
        q['or'],
        '(created_at.lt."2026-10-14T08:05:00.123456Z",'
        'and(created_at.eq."2026-10-14T08:05:00.123456Z",id.lt.m-5))',
      );
      expect(q['limit'], '51');
    });

    test('a deleted partner\'s thread reads the viewer\'s own messages under '
        'its key', () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = const <dynamic>[];

      await api.fetchDmThread(const DmDeletedPartnerThread('k-1'));

      final q = fake.to(_messagesPath).single.url.queryParameters;
      expect(q['sender_id'], 'eq.user-1');
      expect(q['deleted_partner_key'], 'eq.k-1');
      expect(q.containsKey('recipient_id'), isFalse);
    });

    test('signed out answers an empty page without a wire call', () async {
      final page = await api.fetchDmThread(const DmPartnerThread('other-1'));
      expect(page.messages, isEmpty);
      expect(page.hasMore, isFalse);
      expect(fake.requests, isEmpty);
    });
  });

  group('unsendDm', () {
    test('calls the sender-only RPC and returns the unsent row', () async {
      await _signIn(client);
      fake.bodyByPath['/rest/v1/rpc/unsend_direct_message'] = {
        ..._message('m-1'),
        'body': null,
        'unsent_at': '2026-10-14T09:00:00Z',
      };

      final row = await api.unsendDm('m-1');

      final req =
          fake.to('/rest/v1/rpc/unsend_direct_message').single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'p_message_id': 'm-1'});
      expect(row.body, isNull);
      expect(row.unsentAt, DateTime.utc(2026, 10, 14, 9));
    });

    test('a message the viewer did not send surfaces the refusal', () async {
      await _signIn(client);
      fake.statusByPath['/rest/v1/rpc/unsend_direct_message'] = 404;
      fake.bodyByPath['/rest/v1/rpc/unsend_direct_message'] = {
        'code': 'P0002',
        'message': 'unsend_direct_message: message not found',
      };

      expect(api.unsendDm('m-9'), throwsA(isA<PostgrestException>()));
    });
  });

  group('editDm', () {
    test('calls the sender-only RPC with the trimmed body and returns the row',
        () async {
      await _signIn(client);
      fake.bodyByPath['/rest/v1/rpc/edit_direct_message'] = {
        ..._message('m-1'),
        'body': 'see you at 7:30',
        'edited_at': '2026-10-14T09:05:00Z',
      };

      final row = await api.editDm('m-1', '  see you at 7:30  ');

      final req =
          fake.to('/rest/v1/rpc/edit_direct_message').single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body),
          {'p_message_id': 'm-1', 'p_body': 'see you at 7:30'});
      expect(row.body, 'see you at 7:30');
      expect(row.editedAt, DateTime.utc(2026, 10, 14, 9, 5));
    });

    test('a refusal past the window is DmEditClosed', () async {
      await _signIn(client);
      fake.statusByPath['/rest/v1/rpc/edit_direct_message'] = 400;
      fake.bodyByPath['/rest/v1/rpc/edit_direct_message'] = {
        'code': '55000',
        'message': 'edit_direct_message: message can no longer be edited',
      };

      expect(api.editDm('m-1', 'late'), throwsA(isA<DmEditClosed>()));
    });

    test('someone else\'s message is DmEditClosed too', () async {
      await _signIn(client);
      fake.statusByPath['/rest/v1/rpc/edit_direct_message'] = 404;
      fake.bodyByPath['/rest/v1/rpc/edit_direct_message'] = {
        'code': 'P0002',
        'message': 'edit_direct_message: message not found',
      };

      expect(api.editDm('m-9', 'forged'), throwsA(isA<DmEditClosed>()));
    });

    test('the edit throttle stays a PostgrestException for the shared parser',
        () async {
      await _signIn(client);
      fake.statusByPath['/rest/v1/rpc/edit_direct_message'] = 400;
      fake.bodyByPath['/rest/v1/rpc/edit_direct_message'] = {
        'code': 'P0001',
        'message': 'rate limit exceeded for edit_direct_message, retry in 60s',
      };

      expect(api.editDm('m-1', 'again'), throwsA(isA<PostgrestException>()));
    });

    test('a blank body is refused without a wire call', () async {
      await _signIn(client);
      expect(() => api.editDm('m-1', '   '), throwsArgumentError);
      expect(fake.to('/rest/v1/rpc/edit_direct_message'), isEmpty);
    });
  });

  group('sendDm', () {
    test('inserts the trimmed body from the viewer and returns the row',
        () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = _message('m-new');

      final row = await api.sendDm('other-1', '  on my way  ');

      final req = fake.to(_messagesPath).single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {
        'sender_id': 'user-1',
        'recipient_id': 'other-1',
        'body': 'on my way',
        'route_id': null,
      });
      expect(req.url.queryParameters['select']!.split(','),
          isNot(contains('read_at')));
      expect(row.id, 'm-new');
    });

    test('a route attachment rides the insert as its route_id', () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = _message('m-new', routeId: 'route-9');

      final row = await api.sendDm(
        'other-1',
        'https://threkir.com/share/route/route-9',
        routeId: ' route-9 ',
      );

      final req = fake.to(_messagesPath).single as http.Request;
      expect(jsonDecode(req.body), {
        'sender_id': 'user-1',
        'recipient_id': 'other-1',
        'body': 'https://threkir.com/share/route/route-9',
        'route_id': 'route-9',
      });
      expect(row.routeId, 'route-9');
    });

    test('a blank route id is sent as no attachment, not an empty FK',
        () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = _message('m-new');

      await api.sendDm('other-1', 'hi', routeId: '  ');

      final req = fake.to(_messagesPath).single as http.Request;
      expect((jsonDecode(req.body) as Map)['route_id'], isNull);
    });

    test('the follow / block refusal is a DmSendNotPermitted', () async {
      await _signIn(client);
      fake.statusByPath[_messagesPath] = 403;
      fake.bodyByPath[_messagesPath] = {
        'code': '42501',
        'message': 'new row violates row-level security policy for table '
            '"direct_messages"',
      };

      expect(api.sendDm('other-1', 'hi'), throwsA(isA<DmSendNotPermitted>()));
    });

    test('a fourth message into an unaccepted request is DmRequestCapReached',
        () async {
      await _signIn(client);
      fake.statusByPath[_messagesPath] = 400;
      fake.bodyByPath[_messagesPath] = {
        'code': '54000',
        'message': 'direct_messages: a message request holds at most 3 '
            'messages until it is accepted',
      };

      expect(api.sendDm('other-1', 'hi'), throwsA(isA<DmRequestCapReached>()));
    });

    test('the send throttle reaches the caller as its P0001', () async {
      await _signIn(client);
      fake.statusByPath[_messagesPath] = 400;
      fake.bodyByPath[_messagesPath] = {
        'code': 'P0001',
        'message':
            'rate limit exceeded for send_direct_message_burst, retry in 41s',
      };

      expect(
        api.sendDm('other-1', 'hi'),
        throwsA(isA<PostgrestException>()
            .having((e) => e.code, 'code', 'P0001')
            .having((e) => e.message, 'message',
                contains('send_direct_message_burst'))),
      );
    });

    test('a blank body is refused before the wire', () async {
      await _signIn(client);
      expect(api.sendDm('other-1', '   '), throwsArgumentError);
      expect(fake.requests, isEmpty);
    });

    test('signed out throws without a wire call', () async {
      expect(api.sendDm('other-1', 'hi'), throwsStateError);
      expect(fake.requests, isEmpty);
    });
  });

  group('markDmThreadRead', () {
    final shown = DirectMessageRow.fromJson(_message('m-9',
        sender: 'other-1',
        recipient: 'user-1',
        createdAt: '2026-10-14T08:09:00.654321Z'));

    test('asks the server to mark the partner\'s messages read through the '
        'newest shown', () async {
      await _signIn(client);

      await api.markDmThreadRead('other-1', through: shown);

      expect(fake.to(_messagesPath), isEmpty,
          reason: 'a client cannot write read_at directly any more');
      final req =
          fake.to('/rest/v1/rpc/mark_direct_messages_read').single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {
        'p_partner_id': 'other-1',
        'p_through_message_id': 'm-9',
      });
    });

    test('signed out throws without a wire call', () async {
      expect(api.markDmThreadRead('other-1', through: shown), throwsStateError);
      expect(fake.requests, isEmpty);
    });
  });

  group('read receipts setting', () {
    const settingsPath = '/rest/v1/user_settings';

    test('reads the viewer\'s own column', () async {
      await _signIn(client);
      fake.bodyByPath[settingsPath] = {'dm_read_receipts': false};

      expect(await api.fetchMyDmReadReceipts(), isFalse);

      final req = fake.to(settingsPath).single;
      expect(req.url.queryParameters['select'], 'dm_read_receipts');
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
    });

    test('no row yet reads as on', () async {
      await _signIn(client);
      fake.bodyByPath[settingsPath] = <dynamic>[];
      expect(await api.fetchMyDmReadReceipts(), isTrue);
    });

    test('writes the column on the viewer\'s row', () async {
      await _signIn(client);

      await api.setDmReadReceipts(false);

      final req = fake.to(settingsPath).single as http.Request;
      expect(req.method, 'POST');
      expect(req.url.queryParameters['on_conflict'], 'user_id');
      expect(jsonDecode(req.body), {'user_id': 'user-1', 'dm_read_receipts': false});
    });

    test('signed out cannot write', () async {
      expect(api.setDmReadReceipts(false), throwsStateError);
      expect(fake.requests, isEmpty);
    });
  });

  group('sendDm with a photo', () {
    test('a photo with no caption sends a null body and the image id',
        () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = {
        ..._message('m-new'),
        'body': null,
        'image_id': 'img-1',
      };

      final row = await api.sendDm('other-1', '   ', imageId: 'img-1');

      final req = fake.to(_messagesPath).single as http.Request;
      expect(jsonDecode(req.body), {
        'sender_id': 'user-1',
        'recipient_id': 'other-1',
        'body': null,
        'route_id': null,
        'image_id': 'img-1',
      });
      expect(req.url.queryParameters['select']!.split(',').map((c) => c.trim()),
          contains('image_id'));
      expect(row.imageId, 'img-1');
      expect(row.body, isNull);
    });

    test('a blank image id with a blank body is refused before the wire',
        () async {
      await _signIn(client);
      expect(api.sendDm('other-1', ' ', imageId: '  '), throwsArgumentError);
      expect(fake.requests, isEmpty);
    });

    test('a refused photo send is the same DmSendNotPermitted', () async {
      await _signIn(client);
      fake.statusByPath[_messagesPath] = 403;
      fake.bodyByPath[_messagesPath] = {'code': '42501', 'message': 'rls'};
      expect(api.sendDm('other-1', '', imageId: 'img-1'),
          throwsA(isA<DmSendNotPermitted>()));
    });
  });

  test('fetchDmThreads reads last_image', () async {
    await _signIn(client);
    fake.bodyByPath[_threadsPath] = [
      {
        'conversation_id': 'c-1',
        'partner_id': 'p-1',
        'last_body': null,
        'last_at': '2026-10-14T09:30:00Z',
        'last_from_me': false,
        'unread': 0,
        'last_image': true,
      },
    ];
    final threads = await api.fetchDmThreads();
    expect(threads.single.lastImage, isTrue);
    expect(threads.single.copyWith(unread: 2).lastImage, isTrue);
  });

  group('reactions', () {
    const reactionsPath = '/rest/v1/direct_message_reactions';
    const rpcPath = '/rest/v1/rpc/set_direct_message_reaction';

    test('reads the three columns for the messages asked, chunked', () async {
      await _signIn(client);
      fake.bodyByPath[reactionsPath] = [
        {'message_id': 'm-1', 'user_id': 'other-1', 'reaction': 'heart'},
      ];
      final ids = [for (var i = 0; i < kInFilterChunk + 1; i++) 'm-$i'];

      final rows = await api.fetchDmReactions(ids);

      final reqs = fake.to(reactionsPath).toList();
      expect(reqs, hasLength(2));
      expect(reqs.first.url.queryParameters['select'],
          'message_id,user_id,reaction');
      expect(reqs.first.url.queryParameters['message_id'], startsWith('in.('));
      expect(rows.first,
          (messageId: 'm-1', userId: 'other-1', reaction: 'heart'));
    });

    test('no messages, or signed out, asks nothing', () async {
      expect(await api.fetchDmReactions(const ['m-1']), isEmpty);
      await _signIn(client);
      expect(await api.fetchDmReactions(const []), isEmpty);
      expect(fake.requests, isEmpty);
    });

    test('a failed read throws rather than reading as no reactions',
        () async {
      await _signIn(client);
      fake.statusByPath[reactionsPath] = 500;
      fake.bodyByPath[reactionsPath] = {'code': 'XX000', 'message': 'boom'};
      expect(api.fetchDmReactions(const ['m-1']),
          throwsA(isA<PostgrestException>()));
    });

    test('sets and clears through the RPC as a POST', () async {
      await _signIn(client);
      await api.setDmReaction('m-1', 'fire');
      await api.setDmReaction('m-1', null);

      final reqs = fake.to(rpcPath).cast<http.Request>().toList();
      expect(reqs.map((r) => r.method), ['POST', 'POST']);
      expect(jsonDecode(reqs[0].body), {'p_message_id': 'm-1', 'p_reaction': 'fire'});
      expect(jsonDecode(reqs[1].body), {'p_message_id': 'm-1', 'p_reaction': null});
    });

    for (final (status, code) in [(400, '55000'), (404, 'P0002')]) {
      test('a $code refusal is one DmReactionRefused', () async {
        await _signIn(client);
        fake.statusByPath[rpcPath] = status;
        fake.bodyByPath[rpcPath] = {'code': code, 'message': 'refused'};
        expect(api.setDmReaction('m-1', 'heart'),
            throwsA(isA<DmReactionRefused>()));
      });
    }

    test('the reaction throttle stays a PostgrestException', () async {
      await _signIn(client);
      fake.statusByPath[rpcPath] = 400;
      fake.bodyByPath[rpcPath] = {
        'code': 'P0001',
        'message': 'rate limit exceeded for dm_reaction, retry in 30s',
      };
      expect(
        api.setDmReaction('m-1', 'heart'),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', 'P0001')),
      );
    });
  });

  group('searchDms', () {
    const searchPath = '/rest/v1/rpc/search_direct_messages';

    test('searches as a GET and names each partner', () async {
      await _signIn(client);
      fake.bodyByPath[searchPath] = [
        {
          'id': 'm-1',
          'conversation_id': 'c-1',
          'sender_id': 'other-1',
          'recipient_id': 'user-1',
          'deleted_partner_key': null,
          'body': 'see you at the track',
          'created_at': '2026-10-14T08:00:00Z',
          'kind': 'text',
        },
        {
          'id': 'm-2',
          'conversation_id': 'c-2',
          'sender_id': 'user-1',
          'recipient_id': null,
          'deleted_partner_key': 'k-9',
          'body': 'track session',
          'created_at': '2026-10-13T08:00:00Z',
          'kind': 'text',
        },
        {
          'id': 'm-3',
          'conversation_id': 'c-1',
          'sender_id': 'other-1',
          'recipient_id': 'user-1',
          'body': null,
          'created_at': '2026-10-12T08:00:00Z',
          'kind': 'text',
        },
      ];
      fake.bodyByPath[_profilesPath] = [
        {'id': 'other-1', 'display_name': 'Ada'},
      ];

      final hits = await api.searchDms('  track ');

      final req = fake.to(searchPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, {'p_query': 'track', 'p_limit': '50'});
      expect(hits.map((h) => h.id), ['m-1', 'm-2']);
      expect(hits.first.partnerId, 'other-1');
      expect(hits.first.partnerName, 'Ada');
      expect(hits.first.fromMe, isFalse);
      expect(hits.last.partnerId, isNull);
      expect(hits.last.deletedPartnerKey, 'k-9');
      expect(hits.last.target, isA<DmDeletedPartnerThread>());
      expect(hits.last.fromMe, isTrue);
      expect(fake.to(_profilesPath).single.url.queryParameters['id'],
          'in.("other-1")');
    });

    test('a failed name read keeps the hits with no names', () async {
      await _signIn(client);
      fake.bodyByPath[searchPath] = [
        {
          'id': 'm-1',
          'conversation_id': 'c-1',
          'sender_id': 'other-1',
          'recipient_id': 'user-1',
          'body': 'hello',
          'created_at': '2026-10-14T08:00:00Z',
        },
      ];
      fake.statusByPath[_profilesPath] = 500;
      fake.bodyByPath[_profilesPath] = {'code': 'XX000', 'message': 'boom'};

      final hits = await api.searchDms('he');
      expect(hits.single.partnerName, isNull);
    });

    test('a blank query, or signed out, asks nothing', () async {
      expect(await api.searchDms('track'), isEmpty);
      await _signIn(client);
      expect(await api.searchDms('   '), isEmpty);
      expect(fake.requests, isEmpty);
    });

    test('a failed search throws rather than reading as no match', () async {
      await _signIn(client);
      fake.statusByPath[searchPath] = 500;
      fake.bodyByPath[searchPath] = {'code': 'XX000', 'message': 'boom'};
      expect(api.searchDms('track'), throwsA(isA<PostgrestException>()));
    });
  });

  group('photos', () {
    const gatePath = '/rest/v1/rpc/dm_images_enabled';
    const imagesPath = '/rest/v1/direct_message_images';
    const createPath = '/rest/v1/rpc/create_dm_image_upload';
    const signPath = '/storage/v1/object/sign/dm-images/user-1/img-1.jpg';
    const uploadPath = '/storage/v1/object/dm-images/user-1/img-1/upload';
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]);

    test('the gate is read as a GET', () async {
      await _signIn(client);
      fake.bodyByPath[gatePath] = true;
      expect(await api.fetchDmImagesEnabled(), isTrue);
      expect(fake.to(gatePath).single.method, 'GET');
    });

    test('a failed gate read is off', () async {
      await _signIn(client);
      fake.statusByPath[gatePath] = 500;
      fake.bodyByPath[gatePath] = {'code': 'XX000', 'message': 'boom'};
      expect(await api.fetchDmImagesEnabled(), isFalse);
    });

    test('a pending photo is not signed', () async {
      await _signIn(client);
      fake.bodyByPath[imagesPath] = {
        'status': 'pending',
        'width': null,
        'height': null,
        'storage_path': 'user-1/img-1.jpg',
      };

      final view = await api.fetchDmImage('img-1');

      expect(view!.status, 'pending');
      expect(view.url, isNull);
      final req = fake.to(imagesPath).single;
      expect(req.url.queryParameters['select'],
          'status,width,height,storage_path');
      expect(req.url.queryParameters['id'], 'eq.img-1');
      expect(fake.requests.where((r) => r.url.path.contains('/storage/')),
          isEmpty);
    });

    test('a ready photo is signed for ten minutes', () async {
      await _signIn(client);
      fake.bodyByPath[imagesPath] = {
        'status': 'ready',
        'width': 1200,
        'height': 800,
        'storage_path': 'user-1/img-1.jpg',
      };
      fake.bodyByPath[signPath] = {
        'signedURL': '/object/sign/dm-images/user-1/img-1.jpg?token=t',
      };

      final view = await api.fetchDmImage('img-1');

      expect(view!.status, 'ready');
      expect(view.width, 1200);
      expect(view.url, contains('token=t'));
      final sign = fake.to(signPath).single as http.Request;
      expect((jsonDecode(sign.body) as Map)['expiresIn'], 600);
    });

    test('a photo the viewer cannot see is null', () async {
      await _signIn(client);
      fake.bodyByPath[imagesPath] = <dynamic>[];
      expect(await api.fetchDmImage('img-1'), isNull);
    });

    test('an upload starts the image, then uploads the JPEG to its path',
        () async {
      await _signIn(client);
      fake.bodyByPath[createPath] = [
        {'id': 'img-1', 'upload_path': 'user-1/img-1/upload'},
      ];
      fake.bodyByPath[uploadPath] = {'Key': 'dm-images/user-1/img-1/upload'};

      expect(await api.uploadDmImage(jpeg), 'img-1');

      expect(fake.to(createPath).single.method, 'POST');
      final up = fake.to(uploadPath).single as http.MultipartRequest;
      expect(up.method, 'POST');
      expect(up.files.single.contentType.mimeType, 'image/jpeg');
      expect(up.headers['x-upsert'], 'false');
    });

    test('anything but a JPEG is refused before the wire', () async {
      await _signIn(client);
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0]);
      expect(api.uploadDmImage(png), throwsArgumentError);
      expect(fake.requests, isEmpty);
    });

    test('a closed gate is DmImageUnavailable and uploads nothing', () async {
      await _signIn(client);
      fake.statusByPath[createPath] = 400;
      fake.bodyByPath[createPath] = {'code': '0A000', 'message': 'off'};
      await expectLater(
          api.uploadDmImage(jpeg), throwsA(isA<DmImageUnavailable>()));
      expect(fake.requests.where((r) => r.url.path.contains('/storage/')),
          isEmpty);
    });

    test('the upload throttle stays a PostgrestException', () async {
      await _signIn(client);
      fake.statusByPath[createPath] = 400;
      fake.bodyByPath[createPath] = {
        'code': 'P0001',
        'message': 'rate limit exceeded for dm_image_upload, retry in 120s',
      };
      expect(api.uploadDmImage(jpeg),
          throwsA(isA<PostgrestException>().having((e) => e.code, 'code', 'P0001')));
    });
  });

  group('message requests setting', () {
    const settingsPath = '/rest/v1/user_settings';

    test('reads the viewer\'s own column', () async {
      await _signIn(client);
      fake.bodyByPath[settingsPath] = {'dm_requests': false};

      expect(await api.fetchMyDmRequests(), isFalse);

      final req = fake.to(settingsPath).single;
      expect(req.url.queryParameters['select'], 'dm_requests');
      expect(req.url.queryParameters['user_id'], 'eq.user-1');
    });

    test('no row yet reads as on', () async {
      await _signIn(client);
      fake.bodyByPath[settingsPath] = <dynamic>[];
      expect(await api.fetchMyDmRequests(), isTrue);
    });

    test('writes the column on the viewer\'s row', () async {
      await _signIn(client);

      await api.setDmRequests(false);

      final req = fake.to(settingsPath).single as http.Request;
      expect(req.method, 'POST');
      expect(req.url.queryParameters['on_conflict'], 'user_id');
      expect(jsonDecode(req.body), {'user_id': 'user-1', 'dm_requests': false});
    });

    test('signed out cannot write', () async {
      expect(api.setDmRequests(false), throwsStateError);
      expect(fake.requests, isEmpty);
    });
  });

  group('group conversations', () {
    test('dm_threads maps a group row: title, size, membership, the rename line',
        () async {
      await _signIn(client);
      fake.bodyByPath[_threadsPath] = [
        {
          'conversation_id': 'g-1',
          'partner_id': null,
          'kind': 'group',
          'title': 'Tuesday tempo',
          'member_count': 6,
          'membership_state': 'active',
          'last_body': 'Tempo club',
          'last_kind': 'group_renamed',
          'last_at': '2026-11-10T09:30:00Z',
          'last_from_me': false,
          'unread': 2,
        },
        {
          'conversation_id': 'g-2',
          'partner_id': null,
          'kind': 'group',
          'title': null,
          'member_count': null,
          'membership_state': 'left',
          'last_body': 'bye',
          'last_at': '2026-11-09T09:30:00Z',
          'last_from_me': true,
          'unread': 0,
        },
      ];

      final threads = await api.fetchDmThreads();

      expect(fake.to(_profilesPath), isEmpty, reason: 'a group names no partner');
      expect(threads.map((t) => t.isGroup), [true, true]);
      expect(threads.map((t) => t.threadKey), ['group/g-1', 'group/g-2']);
      expect(threads.first.title, 'Tuesday tempo');
      expect(threads.first.memberCount, 6);
      expect(threads.first.lastKind, 'group_renamed');
      expect(threads.map((t) => t.membershipState), ['active', 'left']);
    });

    test('a group thread reads its conversation\'s group rows, oldest first',
        () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = [
        {..._message('m-2', createdAt: '2026-11-10T08:02:00Z'), 'recipient_id': null},
        {..._message('m-1', createdAt: '2026-11-10T08:01:00Z'), 'recipient_id': null},
      ];

      final page = await api.fetchGroupThread('g-1', limit: 2);

      final q = fake.to(_messagesPath).single.url.queryParameters;
      expect(q['conversation_id'], 'eq.g-1');
      expect(q['is_group'], 'eq.true');
      expect(q['order'], 'created_at.desc.nullslast,id.desc.nullslast');
      expect(q['limit'], '3');
      expect(page.messages.map((m) => m.id), ['m-1', 'm-2']);
      expect(page.hasMore, isFalse);
    });

    test('a group send names the conversation and no recipient', () async {
      await _signIn(client);
      fake.bodyByPath[_messagesPath] = {
        ..._message('m-9'),
        'recipient_id': null,
        'conversation_id': 'g-1',
      };

      await api.sendGroupMessage('g-1', '  hello all  ');

      final req = fake.to(_messagesPath).single as http.Request;
      expect(req.method, 'POST');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body, {
        'sender_id': 'user-1',
        'conversation_id': 'g-1',
        'body': 'hello all',
      });
    });

    test('a refused group send is GroupActionRefused, the throttle stays a '
        'PostgrestException', () async {
      await _signIn(client);
      fake.statusByPath[_messagesPath] = 403;
      fake.bodyByPath[_messagesPath] = {
        'code': '42501',
        'message': 'new row violates row-level security policy',
      };
      await expectLater(
        api.sendGroupMessage('g-1', 'hi'),
        throwsA(isA<GroupActionRefused>()
            .having((e) => e.reason, 'reason', GroupRefusal.refused)),
      );
      fake.statusByPath[_messagesPath] = 400;
      fake.bodyByPath[_messagesPath] = {
        'code': 'P0001',
        'message': 'rate limit exceeded for send_direct_message, retry after 30 seconds',
      };
      await expectLater(api.sendGroupMessage('g-1', 'hi'),
          throwsA(isA<PostgrestException>()));
    });

    test('create sends the title and invitees and maps the seat cap', () async {
      await _signIn(client);
      const path = '/rest/v1/rpc/create_group_conversation';
      fake.bodyByPath[path] = 'g-new';

      expect(await api.createGroupConversation('Tempo', ['a', 'b']), 'g-new');
      final req = fake.to(path).single as http.Request;
      expect(jsonDecode(req.body), {
        'p_title': 'Tempo',
        'p_invitees': ['a', 'b'],
      });

      fake.statusByPath[path] = 400;
      fake.bodyByPath[path] = {'code': '54000', 'message': 'group is full'};
      await expectLater(
        api.createGroupConversation('Tempo', ['a', 'b']),
        throwsA(isA<GroupActionRefused>()
            .having((e) => e.reason, 'reason', GroupRefusal.capReached)),
      );
    });

    test('the roster reads roles, invitations and names; outside it is notFound',
        () async {
      await _signIn(client);
      const path = '/rest/v1/rpc/group_members';
      fake.bodyByPath[path] = [
        {'user_id': 'user-1', 'role': 'owner', 'membership_state': 'active'},
        {'user_id': 'p-2', 'role': null, 'membership_state': 'invited'},
      ];
      fake.bodyByPath[_profilesPath] = [
        {'id': 'p-2', 'display_name': 'Grace', 'avatar_url': null},
      ];

      final members = await api.fetchGroupMembers('g-1');

      expect(fake.to(path).single.method, 'GET');
      expect(members.map((m) => m.role), ['owner', null]);
      expect(members.map((m) => m.invited), [false, true]);
      expect(members.last.name, 'Grace');

      fake.statusByPath[path] = 404;
      fake.bodyByPath[path] = {'code': 'P0002', 'message': 'not found'};
      await expectLater(
        api.fetchGroupMembers('g-1'),
        throwsA(isA<GroupActionRefused>()
            .having((e) => e.reason, 'reason', GroupRefusal.notFound)),
      );
    });

    test('a failed flag read is unknown, not off', () async {
      await _signIn(client);
      const path = '/rest/v1/rpc/group_messages_enabled';
      fake.bodyByPath[path] = true;
      expect(await api.fetchGroupMessagesEnabled(), isTrue);
      fake.bodyByPath[path] = false;
      expect(await api.fetchGroupMessagesEnabled(), isFalse);
      fake.statusByPath[path] = 500;
      fake.bodyByPath[path] = {'message': 'boom'};
      expect(await api.fetchGroupMessagesEnabled(), isNull);
    });

    test('a search hit in a group names the group, not a partner', () async {
      await _signIn(client);
      fake.bodyByPath['/rest/v1/rpc/search_direct_messages'] = [
        {
          'id': 'm-1',
          'conversation_id': 'g-1',
          'sender_id': 'p-2',
          'recipient_id': null,
          'deleted_partner_key': null,
          'body': 'tempo tonight',
          'created_at': '2026-11-10T08:00:00Z',
        },
      ];
      fake.bodyByPath['/rest/v1/conversations'] = [
        {'id': 'g-1', 'title': 'Tuesday tempo'},
      ];

      final hits = await api.searchDms('tempo');

      expect(hits.single.isGroup, isTrue);
      expect(hits.single.partnerId, isNull);
      expect(hits.single.groupTitle, 'Tuesday tempo');
      expect(fake.to(_profilesPath), isEmpty);
    });

    test('placeholders are read inside the loaded window', () async {
      await _signIn(client);
      const path = '/rest/v1/rpc/group_blocked_placeholders';
      fake.bodyByPath[path] = [
        {'id': 'm-4', 'created_at': '2026-11-10T08:04:00Z'},
      ];

      final rows = await api.fetchGroupBlockedPlaceholders(
          'g-1', DateTime.utc(2026, 11, 10, 8));

      final q = fake.to(path).single.url.queryParameters;
      expect(q['p_conversation_id'], 'g-1');
      expect(q['p_since'], '2026-11-10T08:00:00.000Z');
      expect(rows.single.id, 'm-4');
    });

    test('a thread with no lower bound omits p_since rather than sending "null"',
        () async {
      await _signIn(client);
      const path = '/rest/v1/rpc/group_blocked_placeholders';
      fake.bodyByPath[path] = <Map<String, dynamic>>[];

      await api.fetchGroupBlockedPlaceholders('g-1', null);

      final q = fake.to(path).single.url.queryParameters;
      expect(q['p_conversation_id'], 'g-1');
      expect(q.containsKey('p_since'), isFalse);
    });
  });
}
