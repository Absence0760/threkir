// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/dm_send_error.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/rate_limit_message.dart';
import '../lib/screens/message_thread_screen.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/sign_in_required_state.dart';

const _me = 'me';
const _partner = 'p-1';
const _quiet = Duration(hours: 1);

DirectMessageRow _msg(
  String id, {
  String from = _partner,
  int minute = 0,
  String? body,
  String? routeId,
  bool read = true,
}) =>
    DirectMessageRow(
      id: id,
      senderId: from,
      recipientId: from == _me ? _partner : _me,
      body: body ?? 'body $id',
      createdAt: DateTime.utc(2026, 10, 14, 8, minute),
      readAt: read ? DateTime.utc(2026, 10, 14, 9) : null,
      routeId: routeId,
    );

DmThread _thread(String id, {String? name, int unread = 0, bool mine = false}) =>
    DmThread(
      partnerId: id,
      partnerName: name,
      lastBody: 'last from $id',
      lastAt: DateTime.utc(2026, 10, 14, 8),
      lastFromMe: mine,
      unread: unread,
    );

class _FakeApi extends ApiClient {
  _FakeApi({this.signedIn = true});

  bool signedIn;

  List<DmThread> threads = [];
  Object? threadsError;
  int threadsCalls = 0;

  List<DirectMessageRow> newest = [];
  bool newestHasMore = false;
  List<DirectMessageRow> older = [];
  Object? threadError;
  final List<DirectMessageRow?> befores = [];

  Completer<DirectMessageRow>? sendGate;
  Object? sendError;
  final List<String> sent = [];

  int markReadCalls = 0;

  final Map<String, Route?> routes = {};
  Object? routeError;
  final List<String> routeReads = [];

  ProfileSummary? summary;

  @override
  String? get userId => signedIn ? _me : null;

  Completer<List<DmThread>>? threadsGate;

  @override
  Future<List<DmThread>> fetchDmThreads() async {
    threadsCalls++;
    final gate = threadsGate;
    if (gate != null) return gate.future;
    if (threadsError != null) throw threadsError!;
    return threads;
  }

  @override
  Future<DmThreadPage> fetchDmThread(
    String otherId, {
    DirectMessageRow? before,
    int limit = 50,
  }) async {
    befores.add(before);
    if (threadError != null) throw threadError!;
    if (before != null) {
      return DmThreadPage(messages: older, hasMore: false);
    }
    return DmThreadPage(messages: newest, hasMore: newestHasMore);
  }

  @override
  Future<DirectMessageRow> sendDm(String recipientId, String body) async {
    sent.add(body);
    final gate = sendGate;
    if (gate != null) return gate.future;
    if (sendError != null) throw sendError!;
    return _msg('sent-${sent.length}', from: _me, minute: 59, body: body);
  }

  @override
  Future<void> markDmThreadRead(String otherId) async {
    markReadCalls++;
    threads = [
      for (final t in threads) t.partnerId == otherId ? t.copyWith(unread: 0) : t,
    ];
  }

  @override
  Future<UserProfileRow?> fetchPublicProfile(String userId) async => null;

  @override
  Future<({Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async {
    routeReads.add(routeId);
    if (routeError != null) throw routeError!;
    final route = routes[routeId];
    return (route: route, ownerId: route?.userId);
  }

  @override
  Future<ProfileSummary?> fetchProfileSummary(String userId) async => summary;

  @override
  Future<bool> isBlockedByViewer(String userId) async => false;

  @override
  Future<List<RunRow>> fetchPublicRunsByUser(String userId,
          {int limit = 50}) async =>
      const [];

  @override
  Future<List<UserProfileRow>> fetchFollowers(String userId,
          {int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<List<UserProfileRow>> fetchFollowing(String userId,
          {int limit = 20, int offset = 0}) async =>
      const [];

  @override
  Future<List<AchievementRow>> fetchUserBadges(String userId) async =>
      const [];

  List<NotificationView> notifications = [];

  @override
  Future<List<NotificationView>> fetchNotificationViews({
    int limit = 100,
  }) async =>
      notifications;

  @override
  Future<void> markNotificationRead(String id) async {}

  @override
  Future<void> markAllNotificationsRead() async {}
}

late AppLocalizations l10n;

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _pumpThread(
  WidgetTester tester,
  _FakeApi api, {
  Duration poll = _quiet,
  void Function(BuildContext, String)? onOpenRoute,
}) async {
  await tester.pumpWidget(_app(MessageThreadScreen(
    api: api,
    partnerId: _partner,
    partnerName: 'Ada',
    pollInterval: poll,
    onOpenRoute: onOpenRoute,
  )));
  await tester.pump();
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(
      find.byKey(const ValueKey('message-composer')), text);
  await tester.pump();
}

IconButton _sendButton(WidgetTester tester) => tester
    .widget<IconButton>(find.byKey(const ValueKey('message-send')));

/// The refusal banner auto-dismisses on a timer; let it run out so the test
/// does not end with it pending.
Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 7));

Route _route(String id, {String name = 'Cliff Loop'}) => Route(
      id: id,
      userId: 'owner-9',
      name: name,
      waypoints: const [
        Waypoint(lat: 51.5, lng: -0.1),
        Waypoint(lat: 51.51, lng: -0.11),
      ],
      distanceMetres: 8200,
      elevationGainMetres: 40,
      isPublic: true,
    );

void main() {
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('MessagesScreen (inbox)', () {
    testWidgets('lists conversations with preview, own prefix and unread count',
        (tester) async {
      final api = _FakeApi()
        ..threads = [
          _thread('p-1', name: 'Ada', unread: 2),
          _thread('p-2', name: null, mine: true),
        ];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text(l10n.profileRunnerFallback), findsOneWidget);
      expect(find.text('last from p-1'), findsOneWidget);
      expect(find.text(l10n.messagesYouPrefixed('last from p-2')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('dm-unread-p-1')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(l10n.messagesUnreadCount(2)))),
          findsOneWidget);
      expect(find.byKey(const ValueKey('dm-unread-p-2')), findsNothing);
      semantics.dispose();
    });

    testWidgets('an empty inbox says how a conversation starts',
        (tester) async {
      final api = _FakeApi();
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();

      expect(find.text(l10n.messagesEmptyTitle), findsOneWidget);
      expect(find.text(l10n.messagesEmptyBody), findsOneWidget);
    });

    testWidgets('a failed load is an error with a retry, not an empty inbox',
        (tester) async {
      final api = _FakeApi()..threadsError = StateError('boom');
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();

      expect(find.text(l10n.messagesLoadError), findsOneWidget);
      expect(find.text(l10n.messagesEmptyTitle), findsNothing);

      api
        ..threadsError = null
        ..threads = [_thread('p-1', name: 'Ada')];
      await tester.tap(find.descendant(
          of: find.byType(ErrorState),
          matching: find.text(l10n.errorStateRetry)));
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('signed out shows the sign-in state and reads nothing',
        (tester) async {
      final api = _FakeApi(signedIn: false);
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();

      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(api.threadsCalls, 0);
    });

    testWidgets('the list re-reads itself on its poll', (tester) async {
      final api = _FakeApi()..threads = [_thread('p-1', name: 'Ada')];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api, pollInterval: const Duration(seconds: 30))));
      await tester.pump();
      expect(find.text('Grace'), findsNothing);

      api.threads = [_thread('p-2', name: 'Grace'), ...api.threads];
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();

      expect(find.text('Grace'), findsOneWidget);
      expect(api.threadsCalls, 2);
    });

    testWidgets('opening a conversation clears its badge on the way back',
        (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada', unread: 2)]
        ..newest = [_msg('m1', read: false)];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api, pollInterval: _quiet, threadPollInterval: _quiet)));
      await tester.pump();

      await tester.tap(find.text('Ada'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final thread = tester.widget<MessageThreadScreen>(
          find.byType(MessageThreadScreen));
      expect(thread.partnerId, 'p-1');
      expect(thread.partnerName, 'Ada');
      expect(api.markReadCalls, 1);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('dm-unread-p-1')), findsNothing);
    });

    testWidgets('a list read that started before the thread was opened does '
        'not put its badge back', (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada', unread: 2)]
        ..newest = [_msg('m1', read: false)];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api,
          pollInterval: const Duration(seconds: 30),
          threadPollInterval: _quiet)));
      await tester.pump();

      final stale = Completer<List<DmThread>>();
      api.threadsGate = stale;
      await tester.pump(const Duration(seconds: 30));

      await tester.tap(find.text('Ada'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      api.threadsGate = null;
      stale.complete([_thread('p-1', name: 'Ada', unread: 2)]);
      await tester.pump();

      expect(find.byKey(const ValueKey('dm-unread-p-1')), findsNothing);
    });
  });

  group('MessageThreadScreen', () {
    testWidgets('shows the conversation and marks the partner\'s unread read',
        (tester) async {
      final api = _FakeApi()
        ..newest = [
          _msg('m1', minute: 1, body: 'hello'),
          _msg('m2', from: _me, minute: 2, body: 'hi back'),
          _msg('m3', minute: 3, body: 'run tomorrow?', read: false),
        ];
      await _pumpThread(tester, api);

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(find.text('hi back'), findsOneWidget);
      final newestY = tester.getTopLeft(find.text('run tomorrow?')).dy;
      final oldestY = tester.getTopLeft(find.text('hello')).dy;
      expect(newestY, greaterThan(oldestY),
          reason: 'the newest message sits at the bottom');
      expect(api.markReadCalls, 1);
    });

    testWidgets('a conversation with nothing unread is not re-marked',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);
      expect(api.markReadCalls, 0);
    });

    testWidgets('a failed load is an error with a retry and no composer',
        (tester) async {
      final api = _FakeApi()..threadError = StateError('boom');
      await _pumpThread(tester, api);

      expect(find.text(l10n.messagesThreadLoadError), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);

      api
        ..threadError = null
        ..newest = [_msg('m1', body: 'back again')];
      await tester.tap(find.descendant(
          of: find.byType(ErrorState),
          matching: find.text(l10n.errorStateRetry)));
      await tester.pump();
      await tester.pump();
      expect(find.text('back again'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    });

    testWidgets('an empty conversation invites the first message',
        (tester) async {
      final api = _FakeApi();
      await _pumpThread(tester, api);

      expect(find.text(l10n.messagesThreadEmpty), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      expect(_sendButton(tester).onPressed, isNull,
          reason: 'nothing typed, nothing to send');
    });

    testWidgets('signed out shows the sign-in state and reads nothing',
        (tester) async {
      final api = _FakeApi(signedIn: false);
      await _pumpThread(tester, api);
      expect(find.byType(SignInRequiredState), findsOneWidget);
      expect(api.befores, isEmpty);
    });

    testWidgets('a send shows at once, cannot be sent twice, then settles',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final api = _FakeApi()..sendGate = Completer<DirectMessageRow>();
      await _pumpThread(tester, api);

      await _type(tester, '  on my way ');
      await tester.tap(find.byKey(const ValueKey('message-send')));
      await tester.pump();

      expect(find.text('on my way'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(l10n.messagesSending))), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('message-composer')))
              .controller!
              .text,
          isEmpty);

      await _type(tester, 'second');
      expect(_sendButton(tester).onPressed, isNull,
          reason: 'one send in flight at a time');
      await tester.tap(find.byKey(const ValueKey('message-send')));
      await tester.pump();
      expect(api.sent, ['on my way']);

      api.sendGate!.complete(
          _msg('stored-1', from: _me, minute: 30, body: 'on my way'));
      await tester.pump();

      expect(find.text('on my way'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(l10n.messagesSending))), findsNothing);
      expect(_sendButton(tester).onPressed, isNotNull);
      semantics.dispose();
    });

    testWidgets('a refused send is withdrawn, the text comes back, and the '
        'follow/block reason is shown', (tester) async {
      final semantics = tester.ensureSemantics();
      final api = _FakeApi()..sendError = const DmSendNotPermitted();
      await _pumpThread(tester, api);

      await _type(tester, 'hello stranger');
      await tester.tap(find.byKey(const ValueKey('message-send')));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.messagesSendNotAllowed), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(RegExp.escape(l10n.messagesSending))), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('message-composer')))
              .controller!
              .text,
          'hello stranger');
      expect(find.text(l10n.messagesThreadEmpty), findsOneWidget);
      await _drainBanner(tester);
      semantics.dispose();
    });

    testWidgets('a throttled send says how long to wait', (tester) async {
      final api = _FakeApi()
        ..sendError = const PostgrestException(
          code: 'P0001',
          message:
              'rate limit exceeded for send_direct_message_burst, retry in 41s',
        );
      await _pumpThread(tester, api);

      await _type(tester, 'again');
      await tester.tap(find.byKey(const ValueKey('message-send')));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.rateLimitSendMessage(rateLimitWait(l10n, 41))),
          findsOneWidget);
      expect(find.text(l10n.messagesSendNotAllowed), findsNothing);
      await _drainBanner(tester);
    });

    testWidgets('a poll brings in a reply and marks it read', (tester) async {
      final api = _FakeApi()..newest = [_msg('m1', minute: 1, body: 'first')];
      await _pumpThread(tester, api, poll: const Duration(seconds: 10));
      expect(api.markReadCalls, 0);

      api.newest = [
        ...api.newest,
        _msg('m2', minute: 2, body: 'reply', read: false),
      ];
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text('first'), findsOneWidget);
      expect(find.text('reply'), findsOneWidget);
      expect(api.markReadCalls, 1);
    });

    testWidgets('older messages load above the oldest one shown',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m5', minute: 5, body: 'five')]
        ..newestHasMore = true
        ..older = [_msg('m4', minute: 4, body: 'four')];
      await _pumpThread(tester, api);

      await tester.tap(find.text(l10n.messagesLoadEarlier));
      await tester.pump();
      await tester.pump();

      expect(api.befores.last?.id, 'm5');
      expect(find.text('four'), findsOneWidget);
      expect(find.text(l10n.messagesLoadEarlier), findsNothing);
      expect(tester.getTopLeft(find.text('five')).dy,
          greaterThan(tester.getTopLeft(find.text('four')).dy));
    });
  });

  group('route attachment card', () {
    testWidgets('draws the route the reader may see and hides the share URL',
        (tester) async {
      final api = _FakeApi()
        ..routes['route-a'] = _route('route-a')
        ..newest = [
          _msg('m1',
              routeId: 'route-a',
              body: 'https://threkir.com/share/route/route-a'),
        ];
      String? opened;
      await _pumpThread(tester, api, onOpenRoute: (_, id) => opened = id);
      await tester.pump();

      expect(api.routeReads, ['route-a']);
      expect(find.byKey(const ValueKey('dm-route-attachment')), findsOneWidget);
      expect(find.text('Cliff Loop'), findsOneWidget);
      expect(find.textContaining('share/route'), findsNothing);

      await tester.tap(find.text('Cliff Loop'));
      expect(opened, 'route-a');
    });

    testWidgets('a note beside the route still renders', (tester) async {
      final api = _FakeApi()
        ..routes['route-b'] = _route('route-b', name: 'Ridge')
        ..newest = [_msg('m1', routeId: 'route-b', body: 'try this Saturday')];
      await _pumpThread(tester, api);
      await tester.pump();

      expect(find.text('Ridge'), findsOneWidget);
      expect(find.text('try this Saturday'), findsOneWidget);
    });

    testWidgets('a route the reader cannot see says so', (tester) async {
      final api = _FakeApi()
        ..routes['route-c'] = null
        ..newest = [
          _msg('m1',
              routeId: 'route-c',
              body: 'https://threkir.com/share/route/route-c'),
        ];
      await _pumpThread(tester, api);
      await tester.pump();

      expect(find.byKey(const ValueKey('dm-route-attachment-unavailable')),
          findsOneWidget);
      expect(find.text(l10n.messagesRouteUnavailable), findsOneWidget);
    });

    testWidgets('a failed route read reads as unavailable, not as a card',
        (tester) async {
      final api = _FakeApi()
        ..routeError = StateError('offline')
        ..newest = [_msg('m1', routeId: 'route-d', body: 'look')];
      await _pumpThread(tester, api);
      await tester.pump();

      expect(find.text(l10n.messagesRouteUnavailable), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-route-attachment')), findsNothing);
    });

    test('the card reads the route only through the owner-aware path', () {
      // fetchRouteById is what clips the sender's privacy zones for a
      // non-owner reader; a direct table read here would hand the recipient
      // the unclipped line (decisions § 33, § 772).
      final src =
          File('lib/widgets/dm_route_attachment.dart').readAsStringSync();
      expect(src, contains('widget.api.fetchRouteById('));
      expect(src.contains('.from('), isFalse);
      expect(RegExp(r'api\.\w+\(').allMatches(src).map((m) => m.group(0)),
          everyElement('api.fetchRouteById('));
    });
  });

  group('dmSendErrorMessage', () {
    test('each refusal reads its own sentence', () {
      expect(dmSendErrorMessage(l10n, const DmSendNotPermitted()),
          l10n.messagesSendNotAllowed);
      expect(
        dmSendErrorMessage(
          l10n,
          const PostgrestException(
              code: 'P0001',
              message: 'rate limit exceeded for send_direct_message, retry in 600s'),
        ),
        l10n.rateLimitSendMessage(rateLimitWait(l10n, 600)),
      );
      expect(dmSendErrorMessage(l10n, const SocketException('down')),
          l10n.authErrorOffline);
      expect(dmSendErrorMessage(l10n, const PostgrestException(message: 'x')),
          l10n.messagesSendFailed);
      expect(dmSendErrorMessage(l10n, StateError('x')), l10n.messagesSendFailed);
    });

    test('the four sentences differ in every locale', () async {
      for (final locale in AppLocalizations.supportedLocales) {
        final l = await AppLocalizations.delegate.load(locale);
        final sentences = {
          l.messagesSendNotAllowed,
          l.rateLimitSendMessage(rateLimitWait(l, 41)),
          l.authErrorOffline,
          l.messagesSendFailed,
        };
        expect(sentences, hasLength(4), reason: '$locale');
      }
    });
  });
}
