import 'dart:convert';

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
      ];

      expect(await api.fetchDmBadgeStates(), [
        (conversationId: 'c-1', unread: 2, muted: false, archived: false),
        (conversationId: 'c-2', unread: 5, muted: true, archived: false),
        (conversationId: 'c-3', unread: 1, muted: false, archived: true),
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
}
