// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/dm_pending_hides.dart';
import '../lib/dm_send_error.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/rate_limit_message.dart';
import '../lib/screens/message_thread_screen.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/undo_queue.dart';
import '../lib/widgets/dm_route_attachment.dart';
import '../lib/widgets/error_state.dart';
import '../lib/widgets/sign_in_required_state.dart';
import '../lib/widgets/undo_bar.dart';

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
  DateTime? seenAt,
}) =>
    DirectMessageRow(
      id: id,
      conversationId: 'c-1',
      senderId: from,
      recipientId: from == _me ? _partner : _me,
      body: body ?? 'body $id',
      createdAt: DateTime.utc(2026, 10, 14, 8, minute),
      readAt: read ? DateTime.utc(2026, 10, 14, 9) : null,
      seenAt: seenAt,
      routeId: routeId,
    );

/// One of a burst, stamped a second apart so the thread order is the index.
DirectMessageRow _burst(int i, {bool read = false}) => DirectMessageRow(
      id: 'b${i.toString().padLeft(3, '0')}',
      conversationId: 'c-1',
      senderId: _partner,
      recipientId: _me,
      body: 'burst $i',
      createdAt: DateTime.utc(2026, 10, 14, 8).add(Duration(seconds: i)),
      readAt: read ? DateTime.utc(2026, 10, 14, 7) : null,
    );

int _order(DirectMessageRow x, DirectMessageRow y) {
  final at = x.createdAt.compareTo(y.createdAt);
  return at != 0 ? at : x.id.compareTo(y.id);
}

DmThread _thread(
  String id, {
  String? name,
  int unread = 0,
  bool mine = false,
  bool muted = false,
  bool archived = false,
}) =>
    DmThread(
      conversationId: 'c-$id',
      partnerId: id,
      partnerName: name,
      lastBody: 'last from $id',
      lastAt: DateTime.utc(2026, 10, 14, 8),
      lastFromMe: mine,
      unread: unread,
      muted: muted,
      archived: archived,
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

  /// When set, the thread is this list and is paged the way the table is:
  /// newest first on `(created_at, id)`, [limit] at a time, before a cursor.
  List<DirectMessageRow>? server;

  /// Runs after a newest-page read has been answered, to land a message in
  /// the window between that read and whatever the screen does next.
  void Function()? afterNewestRead;

  Completer<DirectMessageRow>? sendGate;
  Object? sendError;
  final List<String> sent = [];

  int markReadCalls = 0;
  final List<DirectMessageRow> throughs = [];

  final Map<String, Route?> routes = {};
  Object? routeError;
  final List<String> routeReads = [];

  ProfileSummary? summary;

  /// The signed-in account; change it, then [switchTo] tells the screens.
  String me = _me;
  final _authChanges = StreamController<String?>.broadcast();

  @override
  String? get userId => signedIn ? me : null;

  @override
  Stream<String?> get authUserChanges => _authChanges.stream;

  /// The thread's suggested-plan-change strip reads this; none here.
  @override
  Future<List<PlanChangeRequestRow>> fetchPlanChangeRequests({
    String? planId,
    String? partnerId,
  }) async =>
      const [];

  void switchTo(String id) {
    me = id;
    _authChanges.add(id);
  }

  Completer<List<DmThread>>? threadsGate;

  @override
  Future<List<DmThread>> fetchDmThreads() async {
    threadsCalls++;
    final gate = threadsGate;
    if (gate != null) return gate.future;
    if (threadsError != null) throw threadsError!;
    return threads;
  }

  final List<DmThreadTarget> targets = [];

  /// When set, the next newest-page read waits on it (then it clears).
  Completer<DmThreadPage>? pollGate;

  final List<String> unsent = [];
  Object? unsendError;

  final List<String> edits = [];
  Object? editError;

  @override
  Future<DirectMessageRow> editDm(String messageId, String body) async {
    edits.add(body);
    if (editError != null) throw editError!;
    final m = [...newest, ...?server].firstWhere((m) => m.id == messageId);
    return m.copyWith(body: body, editedAt: DateTime.now().toUtc());
  }

  @override
  Future<DirectMessageRow> unsendDm(String messageId) async {
    unsent.add(messageId);
    if (unsendError != null) throw unsendError!;
    final m = [...newest, ...?server].firstWhere((m) => m.id == messageId);
    return DirectMessageRow(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      recipientId: m.recipientId,
      createdAt: m.createdAt,
      readAt: m.readAt,
      unsentAt: DateTime.utc(2026, 10, 14, 11),
    );
  }

  @override
  Future<DmThreadPage> fetchDmThread(
    DmThreadTarget target, {
    DirectMessageRow? before,
    int limit = 50,
  }) async {
    targets.add(target);
    befores.add(before);
    final gate = pollGate;
    if (gate != null && before == null) {
      pollGate = null;
      return gate.future;
    }
    if (threadError != null) throw threadError!;
    final all = server;
    if (all != null) {
      final sorted = [...all]..sort(_order);
      final eligible = [
        for (final m in sorted)
          if (before == null || _order(m, before) < 0) m,
      ];
      final hasMore = eligible.length > limit;
      final page =
          hasMore ? eligible.sublist(eligible.length - limit) : eligible;
      if (before == null) afterNewestRead?.call();
      return DmThreadPage(messages: page, hasMore: hasMore);
    }
    if (before != null) {
      return DmThreadPage(messages: older, hasMore: false);
    }
    return DmThreadPage(messages: newest, hasMore: newestHasMore);
  }

  @override
  Future<DirectMessageRow> sendDm(
    String recipientId,
    String body, {
    String? routeId,
  }) async {
    sent.add(body);
    final gate = sendGate;
    if (gate != null) return gate.future;
    if (sendError != null) throw sendError!;
    return _msg('sent-${sent.length}', from: _me, minute: 59, body: body);
  }

  @override
  Future<void> markDmThreadRead(
    String otherId, {
    required DirectMessageRow through,
  }) async {
    markReadCalls++;
    throughs.add(through);
    final all = server;
    if (all != null) {
      for (var i = 0; i < all.length; i++) {
        final m = all[i];
        if (m.senderId == otherId &&
            m.readAt == null &&
            _order(m, through) <= 0) {
          all[i] = m.copyWith(readAt: DateTime.utc(2026, 10, 14, 10));
        }
      }
    }
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

  bool blocked = false;
  Object? blockError;
  final List<String> blocks = [];
  final List<String> unblocks = [];
  final List<String> blockChecks = [];

  Completer<bool>? blockCheckGate;

  @override
  Future<bool> isBlockedByViewer(String userId) async {
    blockChecks.add(userId);
    final gate = blockCheckGate;
    if (gate != null) return gate.future;
    return blocked;
  }

  @override
  Future<void> blockUser(String targetUserId, {String? reason}) async {
    blocks.add(targetUserId);
    if (blockError != null) throw blockError!;
    blocked = true;
  }

  @override
  Future<void> unblockUser(String targetUserId) async {
    unblocks.add(targetUserId);
    blocked = false;
  }

  @override
  Future<List<RunRow>> fetchPublicRunsByUser(String userId,
          {int limit = 50}) async =>
      const [];

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowers(String userId,
          {int limit = 20, List<Object?>? after}) async =>
      const KeysetPage(<UserProfileRow>[], null);

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowing(String userId,
          {int limit = 20, List<Object?>? after}) async =>
      const KeysetPage(<UserProfileRow>[], null);

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

  final List<(String, bool)> mutes = [];
  final List<(String, bool)> archives = [];
  final List<(String, String)> hides = [];
  Object? conversationError;
  ({bool muted, DateTime? archivedAt, bool markedUnread})? conversationState;
  final List<(String, bool)> unreadMarks = [];
  final List<String> stateReads = [];

  @override
  Future<void> setDmConversationMuted(String conversationId,
      {required bool muted}) async {
    mutes.add((conversationId, muted));
    if (conversationError != null) throw conversationError!;
  }

  @override
  Future<void> setDmConversationArchived(String conversationId,
      {required bool archived}) async {
    archives.add((conversationId, archived));
    if (conversationError != null) throw conversationError!;
  }

  /// Like the server, a mark shows in the next list read as one unread.
  @override
  Future<void> setDmConversationUnread(String conversationId,
      {required bool unread}) async {
    unreadMarks.add((conversationId, unread));
    if (conversationError != null) throw conversationError!;
    threads = [
      for (final t in threads)
        t.conversationId == conversationId
            ? t.copyWith(
                markedUnread: unread,
                unread: unread ? (t.unread < 1 ? 1 : t.unread) : 0)
            : t,
    ];
  }

  Object? hideError;

  @override
  Future<void> hideDmConversation(String conversationId,
      {required String throughMessageId}) async {
    hides.add((conversationId, throughMessageId));
    if (hideError != null) throw hideError!;
  }

  @override
  Future<({bool muted, DateTime? archivedAt, bool markedUnread})?>
      fetchDmConversationState(
      String conversationId) async {
    stateReads.add(conversationId);
    return conversationState;
  }
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

    // read_at is withheld from clients (migration 20271113000001), so the
    // screen cannot tell a read message from an unread one: it marks through
    // the newest partner message once and remembers how far it marked.
    testWidgets('opening marks once, and a poll with nothing new does not again',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api, poll: const Duration(seconds: 10));
      expect(api.throughs.map((m) => m.id), ['m1']);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(api.markReadCalls, 1);
    });

    testWidgets('Seen sits under the viewer\'s newest message the partner read',
        (tester) async {
      final api = _FakeApi()
        ..newest = [
          _msg('m1', from: _me, minute: 1, body: 'one', seenAt: DateTime.utc(2026, 10, 14, 9)),
          _msg('m2', from: _me, minute: 2, body: 'two', seenAt: DateTime.utc(2026, 10, 14, 9, 5)),
          _msg('m3', from: _me, minute: 3, body: 'three'),
        ];
      await _pumpThread(tester, api);

      final seen = find.byKey(const ValueKey('dm-seen'));
      expect(seen, findsOneWidget);
      expect(tester.widget<Text>(seen).data, startsWith('Seen '));
      final column = find.ancestor(of: seen, matching: find.byType(Column)).first;
      expect(find.descendant(of: column, matching: find.text('two')), findsOneWidget);
      expect(find.descendant(of: column, matching: find.text('three')), findsNothing);
    });

    testWidgets('no receipt the server did not share: no Seen at all',
        (tester) async {
      final api = _FakeApi()
        ..newest = [
          _msg('m1', from: _me, minute: 1, body: 'one'),
          _msg('m2', minute: 2, body: 'reply', seenAt: DateTime.utc(2026, 10, 14, 9)),
        ];
      await _pumpThread(tester, api);
      expect(find.byKey(const ValueKey('dm-seen')), findsNothing);
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
      expect(api.markReadCalls, 1);

      api.newest = [
        ...api.newest,
        _msg('m2', minute: 2, body: 'reply', read: false),
      ];
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text('first'), findsOneWidget);
      expect(find.text('reply'), findsOneWidget);
      expect(api.throughs.map((m) => m.id), ['m1', 'm2']);
    });

    testWidgets('a burst larger than a page leaves no gap in the conversation',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _FakeApi()
        ..server = [for (var i = 0; i < 3; i++) _burst(i, read: true)];
      await _pumpThread(tester, api, poll: const Duration(seconds: 10));
      expect(find.text('burst 2'), findsOneWidget);

      api.server!.addAll([for (var i = 3; i < 63; i++) _burst(i)]);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text('burst 62'), findsOneWidget);
      await tester.tap(find.text(l10n.messagesLoadEarlier));
      await tester.pump();
      await tester.pump();

      for (var i = 0; i < 63; i++) {
        expect(find.text('burst $i'), findsOneWidget, reason: 'burst $i');
      }
      expect(find.text(l10n.messagesLoadEarlier), findsNothing);
    });

    testWidgets('a reply that lands after the read is not marked read',
        (tester) async {
      final api = _FakeApi()..server = [_burst(0)];
      var landed = false;
      api.afterNewestRead = () {
        if (landed) return;
        landed = true;
        api.server!.add(_burst(1));
      };
      await _pumpThread(tester, api);

      expect(find.text('burst 0'), findsOneWidget);
      expect(find.text('burst 1'), findsNothing);
      expect(api.throughs.map((m) => m.id), ['b000']);
      expect(api.server!.firstWhere((m) => m.id == 'b000').readAt, isNotNull);
      expect(api.server!.firstWhere((m) => m.id == 'b001').readAt, isNull,
          reason: 'never drawn, so never read');
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

  group('edit', () {
    DirectMessageRow fresh(String id, {String from = _me, String? body}) =>
        DirectMessageRow(
          id: id,
          conversationId: 'c-1',
          senderId: from,
          recipientId: from == _me ? _partner : _me,
          body: body ?? 'body $id',
          createdAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
        );

    Future<void> longPress(WidgetTester tester, String body) async {
      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
    }

    testWidgets('your fresh message offers Edit; an old one does not',
        (tester) async {
      final api = _FakeApi()
        ..newest = [
          _msg('m0', from: _me, body: 'old'),
          fresh('m1', body: 'new'),
        ];
      await _pumpThread(tester, api);

      await longPress(tester, 'new');
      expect(find.byKey(const ValueKey('message-action-edit')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await longPress(tester, 'old');
      expect(find.byKey(const ValueKey('message-action-edit')), findsNothing);
      expect(
          find.byKey(const ValueKey('message-action-unsend')), findsOneWidget);
    });

    testWidgets("the other person's fresh message offers no Edit",
        (tester) async {
      final api = _FakeApi()..newest = [fresh('m1', from: _partner, body: 'hi')];
      await _pumpThread(tester, api);

      await longPress(tester, 'hi');
      expect(find.byKey(const ValueKey('message-action-edit')), findsNothing);
      expect(
          find.byKey(const ValueKey('message-action-report')), findsOneWidget);
    });

    testWidgets('a saved edit replaces the text and marks it Edited',
        (tester) async {
      final api = _FakeApi()..newest = [fresh('m1', body: 'see you at 7')];
      await _pumpThread(tester, api);
      expect(find.byKey(const ValueKey('dm-edited')), findsNothing);

      await longPress(tester, 'see you at 7');
      await tester.tap(find.byKey(const ValueKey('message-action-edit')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.messagesEditTitle), findsWidgets);

      await tester.enterText(
          find.byKey(const ValueKey('message-edit-field')), 'see you at 7:30');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('message-edit-save')));
      await tester.pumpAndSettle();

      expect(api.edits, ['see you at 7:30']);
      expect(find.text('see you at 7:30'), findsOneWidget);
      expect(find.text('see you at 7'), findsNothing);
      expect(find.byKey(const ValueKey('dm-edited')), findsOneWidget);
      expect(find.text(l10n.messagesEdited), findsOneWidget);
    });

    testWidgets('a refused edit keeps the dialog and the text, and says why',
        (tester) async {
      final api = _FakeApi()
        ..newest = [fresh('m1', body: 'see you at 7')]
        ..editError = const DmEditClosed();
      await _pumpThread(tester, api);

      await longPress(tester, 'see you at 7');
      await tester.tap(find.byKey(const ValueKey('message-action-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('message-edit-field')), 'too late');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('message-edit-save')));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.messagesEditClosed), findsOneWidget);
      expect(find.byKey(const ValueKey('message-edit-field')), findsOneWidget);
      expect(find.text('too late'), findsOneWidget);

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(find.text('see you at 7'), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-edited')), findsNothing);
    });

    testWidgets('an edit the other person made reads as Edited',
        (tester) async {
      final api = _FakeApi()
        ..newest = [
          _msg('m1', body: 'changed').copyWith(
              editedAt: DateTime.utc(2026, 10, 14, 8, 5)),
        ];
      await _pumpThread(tester, api);

      expect(find.text('changed'), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-edited')), findsOneWidget);
    });

    test('the edit throttle says how long to wait', () {
      final message = dmEditErrorMessage(
        l10n,
        const PostgrestException(
          code: 'P0001',
          message: 'rate limit exceeded for edit_direct_message, retry in 60s',
        ),
      );
      expect(message, contains('editing messages too quickly'));
    });
  });

  group('unsend and report', () {
    Future<void> longPress(WidgetTester tester, String body) async {
      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
    }

    testWidgets('your own message offers Unsend, never Report', (tester) async {
      final api = _FakeApi()..newest = [_msg('m1', from: _me, body: 'mine')];
      await _pumpThread(tester, api);

      await longPress(tester, 'mine');

      expect(find.byKey(const ValueKey('message-action-unsend')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-action-report')), findsNothing);
    });

    testWidgets('the other person\'s message offers Report, never Unsend',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1', body: 'theirs')];
      await _pumpThread(tester, api);

      await longPress(tester, 'theirs');

      expect(find.byKey(const ValueKey('message-action-report')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-action-unsend')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('message-action-report')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reportTitleMessage), findsOneWidget);
    });

    testWidgets('unsend asks first; cancelling changes nothing', (tester) async {
      final api = _FakeApi()..newest = [_msg('m1', from: _me, body: 'mine')];
      await _pumpThread(tester, api);

      await longPress(tester, 'mine');
      await tester.tap(find.byKey(const ValueKey('message-action-unsend')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.messagesUnsendConfirmTitle), findsOneWidget);

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(api.unsent, isEmpty);
      expect(find.text('mine'), findsOneWidget);
    });

    testWidgets('a confirmed unsend leaves the placeholder, with no options',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1', from: _me, body: 'mine')];
      await _pumpThread(tester, api);

      await longPress(tester, 'mine');
      await tester.tap(find.byKey(const ValueKey('message-action-unsend')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-unsend-confirm')));
      await tester.pumpAndSettle();

      expect(api.unsent, ['m1']);
      expect(find.text('mine'), findsNothing);
      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);

      await longPress(tester, l10n.messagesUnsentPlaceholder);
      expect(find.byKey(const ValueKey('message-action-unsend')), findsNothing);
    });

    testWidgets('a failed unsend says so and keeps the message',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1', from: _me, body: 'mine')]
        ..unsendError = StateError('offline');
      await _pumpThread(tester, api);

      await longPress(tester, 'mine');
      await tester.tap(find.byKey(const ValueKey('message-action-unsend')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-unsend-confirm')));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.messagesUnsendFailed), findsOneWidget);
      expect(find.text('mine'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a poll already in flight when you unsend does not bring the '
        'text back', (tester) async {
      final api = _FakeApi()..newest = [_msg('m1', from: _me, body: 'mine')];
      await _pumpThread(tester, api, poll: const Duration(seconds: 10));

      final stale = Completer<DmThreadPage>();
      api.pollGate = stale;
      await tester.pump(const Duration(seconds: 10));

      await longPress(tester, 'mine');
      await tester.tap(find.byKey(const ValueKey('message-action-unsend')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-unsend-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);

      stale.complete(DmThreadPage(
          messages: [_msg('m1', from: _me, body: 'mine')], hasMore: false));
      await tester.pump();
      await tester.pump();

      expect(find.text('mine'), findsNothing);
      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);
    });

    testWidgets('a message the other person unsent reads as unsent',
        (tester) async {
      final api = _FakeApi()
        ..newest = [
          DirectMessageRow(
            id: 'm1',
            conversationId: 'c-1',
            senderId: _partner,
            recipientId: _me,
            createdAt: DateTime.utc(2026, 10, 14, 8),
            readAt: DateTime.utc(2026, 10, 14, 9),
            unsentAt: DateTime.utc(2026, 10, 14, 10),
          ),
        ];
      await _pumpThread(tester, api);

      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);
      await longPress(tester, l10n.messagesUnsentPlaceholder);
      expect(find.byKey(const ValueKey('message-action-report')), findsNothing);
    });
  });

  group('deleted account', () {
    testWidgets('the inbox names a deleted partner and an unsent preview',
        (tester) async {
      final api = _FakeApi()
        ..threads = [
          DmThread(
            conversationId: 'c-k-1',
            partnerId: null,
            deletedPartnerKey: 'k-1',
            lastBody: 'still here?',
            lastAt: DateTime.utc(2026, 10, 14, 8),
            lastFromMe: true,
            unread: 0,
          ),
          DmThread(
            conversationId: 'c-p-2',
            partnerId: 'p-2',
            partnerName: 'Grace',
            lastBody: null,
            lastUnsent: true,
            lastAt: DateTime.utc(2026, 10, 13, 8),
            lastFromMe: false,
            unread: 0,
          ),
        ];
      await tester.pumpWidget(
          _app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();

      expect(find.text(l10n.messagesDeletedAccount), findsOneWidget);
      expect(find.text(l10n.messagesYouPrefixed('still here?')), findsOneWidget);
      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-thread-k-1')), findsOneWidget);
    });

    testWidgets('a deleted partner\'s thread reads by its key and cannot be '
        'replied to', (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1', from: _me, body: 'still here?')];
      await tester.pumpWidget(_app(MessageThreadScreen.deletedPartner(
        api: api,
        deletedPartnerKey: 'k-1',
        pollInterval: _quiet,
      )));
      await tester.pump();
      await tester.pump();

      final target = api.targets.single;
      expect(target, isA<DmDeletedPartnerThread>());
      expect((target as DmDeletedPartnerThread).deletedPartnerKey, 'k-1');
      expect(find.text(l10n.messagesDeletedAccount), findsOneWidget);
      expect(find.text('still here?'), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
      expect(find.text(l10n.messagesDeletedAccountClosed), findsOneWidget);
      expect(find.byTooltip(l10n.messagesViewProfile), findsNothing);
      expect(api.markReadCalls, 0);
      expect(api.blockChecks, isEmpty);
      // The viewer can still archive or delete it, but there is no one to
      // block or mute.
      await tester.tap(find.byKey(const ValueKey('message-thread-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-thread-block')), findsNothing);
      expect(find.byKey(const ValueKey('message-thread-mute')), findsNothing);
      expect(find.byKey(const ValueKey('message-thread-archive')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-thread-delete')), findsOneWidget);
    });
  });

  group('block from the conversation', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('message-thread-more')));
      await tester.pumpAndSettle();
    }

    testWidgets('Block asks first; cancelling changes nothing',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);
      expect(api.blockChecks, [_partner]);

      await openMenu(tester);
      expect(find.text(l10n.messagesBlock), findsOneWidget);
      await tester.tap(find.text(l10n.messagesBlock));
      await tester.pumpAndSettle();
      expect(find.text(l10n.profileBlockConfirmTitle('Ada')), findsOneWidget);
      expect(find.text(l10n.messagesBlockConfirmBody), findsOneWidget);

      await tester.tap(find.text(l10n.profileCancel));
      await tester.pumpAndSettle();
      expect(api.blocks, isEmpty);
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
    });

    testWidgets('a confirmed block swaps the composer for the blocked notice',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesBlock));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-block-confirm')));
      await tester.pump();
      await tester.pump();

      expect(api.blocks, [_partner]);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
      expect(find.byKey(const ValueKey('message-send')), findsNothing);
      expect(find.text(l10n.messagesBlockedNotice('Ada')), findsOneWidget);
      expect(find.text(l10n.profileBlocked('Ada')), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a thread opened on a blocked partner shows the notice, and '
        'Unblock brings the composer back without a confirm', (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..blocked = true;
      await _pumpThread(tester, api);

      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
      expect(find.text(l10n.messagesBlockedNotice('Ada')), findsOneWidget);

      await openMenu(tester);
      final item = find.byKey(const ValueKey('message-thread-block'));
      expect(
          find.descendant(of: item, matching: find.text(l10n.messagesUnblock)),
          findsOneWidget);
      await tester.tap(item);
      await tester.pump();
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);
      expect(api.unblocks, [_partner]);
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('the notice\'s own Unblock lifts the block', (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..blocked = true;
      await _pumpThread(tester, api);

      await tester.tap(find.byKey(const ValueKey('message-unblock')));
      await tester.pump();
      await tester.pump();

      expect(api.unblocks, [_partner]);
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a block-state read that answers after Block cannot undo it',
        (tester) async {
      final pending = Completer<bool>();
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..blockCheckGate = pending;
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesBlock));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-block-confirm')));
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.messagesBlockedNotice('Ada')), findsOneWidget);

      pending.complete(false);
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.messagesBlockedNotice('Ada')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
      await _drainBanner(tester);
    });

    testWidgets('a failed block says so and keeps the composer',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..blockError = StateError('offline');
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesBlock));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-block-confirm')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      expect(find.textContaining('Could not block'), findsOneWidget);
      await _drainBanner(tester);
    });
  });

  group('mute, archive and delete the conversation', () {
    tearDown(() {
      debugResetUndo();
      DmPendingHides.instance.debugClear();
    });

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('message-thread-more')));
      await tester.pumpAndSettle();
    }

    testWidgets('the inbox files archived conversations under Archived and '
        'marks a muted one', (tester) async {
      final api = _FakeApi()
        ..threads = [
          _thread('p-1', name: 'Ada', unread: 2, muted: true),
          _thread('p-2', name: 'Grace', archived: true),
        ];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsNothing);
      expect(find.byKey(const ValueKey('dm-muted-p-1')), findsOneWidget);
      expect(
          find.bySemanticsLabel(
              RegExp(RegExp.escape(l10n.messagesMutedMark))),
          findsOneWidget);
      expect(find.text(l10n.messagesArchivedCount(1)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('inbox-show-archived')));
      await tester.pump();
      expect(find.text('Grace'), findsOneWidget);
      expect(find.text('Ada'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('inbox-back-to-inbox')));
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsNothing);
      semantics.dispose();
    });

    testWidgets('Mute and Archive write the viewer\'s state and flip in the menu',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);
      expect(api.stateReads, ['c-1']);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesMute));
      await tester.pump();
      expect(api.mutes, [('c-1', true)]);
      expect(find.text(l10n.messagesMutedToast), findsOneWidget);
      await _drainBanner(tester);

      await openMenu(tester);
      expect(find.text(l10n.messagesUnmute), findsOneWidget);
      await tester.tap(find.text(l10n.messagesArchive));
      await tester.pump();
      expect(api.archives, [('c-1', true)]);
      expect(find.text(l10n.messagesArchivedToast), findsOneWidget);
      await _drainBanner(tester);

      await openMenu(tester);
      expect(find.text(l10n.messagesUnarchive), findsOneWidget);
      await tester.tap(find.text(l10n.messagesUnmute));
      await tester.pump();
      expect(api.mutes.last, ('c-1', false));
    });

    testWidgets('a thread opened outside the inbox reads its muted state',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..conversationState =
            (muted: true, archivedAt: null, markedUnread: false);
      await _pumpThread(tester, api);

      await openMenu(tester);
      expect(find.text(l10n.messagesUnmute), findsOneWidget);
      expect(find.text(l10n.messagesArchive), findsOneWidget);
    });

    testWidgets(
        'Mark as unread leaves the conversation, the inbox counts it, and '
        'reopening clears it', (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada')]
        ..newest = [_msg('m1')];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api, pollInterval: _quiet, threadPollInterval: _quiet)));
      await tester.pump();
      expect(find.byKey(const ValueKey('dm-unread-p-1')), findsNothing);

      await tester.tap(find.text('Ada'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.unreadMarks, isEmpty);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesMarkUnread));
      await tester.pump();
      // The pop lands inside that frame's microtasks, so the route's exit
      // animation starts on the next frame and finishes on the one after.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.unreadMarks, [('c-p-1', true)]);
      expect(find.byType(MessageThreadScreen), findsNothing);
      expect(find.text(l10n.messagesMarkedUnreadToast), findsOneWidget);
      final pill = find.descendant(
          of: find.byKey(const ValueKey('dm-unread-p-1')),
          matching: find.text('1'));
      expect(pill, findsOneWidget);
      await _drainBanner(tester);

      await tester.tap(find.text('Ada'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.unreadMarks.last, ('c-p-1', false));
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('dm-unread-p-1')), findsNothing);
    });

    testWidgets('a thread opened outside the inbox clears its unread mark',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..conversationState =
            (muted: false, archivedAt: null, markedUnread: true);
      await _pumpThread(tester, api);
      await tester.pump();
      expect(api.unreadMarks, [('c-1', false)]);
    });

    testWidgets('a thread opened outside the inbox with no mark writes none',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..conversationState =
            (muted: false, archivedAt: null, markedUnread: false);
      await _pumpThread(tester, api);
      await tester.pump();
      expect(api.stateReads, ['c-1']);
      expect(api.unreadMarks, isEmpty);
    });

    testWidgets('a failed Mark as unread says so and stays in the conversation',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..conversationError = StateError('offline');
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesMarkUnread));
      await tester.pump();
      expect(api.unreadMarks, [('c-1', true)]);
      expect(find.byType(MessageThreadScreen), findsOneWidget);
      expect(find.textContaining(l10n.messagesConversationActionFailed('').trim()),
          findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a failed mute says so and leaves the state as it was',
        (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..conversationError = StateError('offline');
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesMute));
      await tester.pump();
      expect(find.textContaining(l10n.messagesConversationActionFailed('').trim()),
          findsOneWidget);
      await _drainBanner(tester);
      await openMenu(tester);
      expect(find.text(l10n.messagesMute), findsOneWidget);
    });

    testWidgets('Delete takes no confirm, and Undo never calls the server',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesDeleteConversation));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('message-thread-deleted')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
      expect(DmPendingHides.instance.contains('c-1'), isTrue);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.byKey(const ValueKey('message-thread-deleted')), findsNothing);
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      expect(DmPendingHides.instance.contains('c-1'), isFalse);
      await tester.pump(const Duration(seconds: kDefaultUndoWindowS + 1));
      expect(api.hides, isEmpty);
    });

    testWidgets('a Delete left to run hides the conversation on the server',
        (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesDeleteConversation));
      await tester.pump();
      expect(api.hides, isEmpty);

      await tester.pump(const Duration(seconds: kDefaultUndoWindowS + 1));
      await tester.pump();
      expect(api.hides, [('c-1', 'm1')]);
      expect(DmPendingHides.instance.contains('c-1'), isFalse);
    });

    testWidgets('a message that arrives during the undo window is not '
        'deleted with the conversation', (tester) async {
      final api = _FakeApi()..newest = [_msg('m1')];
      await _pumpThread(tester, api);

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesDeleteConversation));
      await tester.pump();
      expect(find.text(l10n.messagesConversationDeletedNotice), findsOneWidget);
      api.newest = [_msg('m1'), _msg('m2', minute: 5)];

      await tester.pump(const Duration(seconds: kDefaultUndoWindowS + 1));
      await tester.pump();
      expect(api.hides, [('c-1', 'm1')],
          reason: 'the delete stops at the newest message on screen when it '
              'was tapped');
    });

    testWidgets('deleting a deleted account\'s thread does not promise it '
        'comes back', (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1', from: _me, body: 'still here?')];
      await tester.pumpWidget(_app(MessageThreadScreen.deletedPartner(
        api: api,
        deletedPartnerKey: 'k-1',
        pollInterval: _quiet,
      )));
      await tester.pump();
      await tester.pump();

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesDeleteConversation));
      await tester.pump();
      expect(find.text(l10n.messagesConversationDeletedNoticeDeletedAccount),
          findsOneWidget);
      expect(find.text(l10n.messagesConversationDeletedNotice), findsNothing);

      await tester.pump(const Duration(seconds: kDefaultUndoWindowS + 1));
      await tester.pump();
      expect(api.hides, [('c-1', 'm1')]);
    });

    testWidgets('a Delete that fails after the thread was left says so over '
        'the screen under it', (tester) async {
      final api = _FakeApi()
        ..newest = [_msg('m1')]
        ..hideError = StateError('offline');
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Inbox')),
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => MessageThreadScreen(
                api: api,
                partnerId: _partner,
                partnerName: 'Ada',
                pollInterval: _quiet,
              ),
            )),
            child: const Text('open'),
          ),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await openMenu(tester);
      await tester.tap(find.text(l10n.messagesDeleteConversation));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      // Not pumpAndSettle: the undo pill's countdown would run it through
      // the whole window.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MessageThreadScreen), findsNothing);
      expect(api.hides, isEmpty);

      await tester.pump(const Duration(seconds: kDefaultUndoWindowS + 1));
      await tester.pump();
      expect(api.hides, [('c-1', 'm1')]);
      expect(DmPendingHides.instance.contains('c-1'), isFalse);
      final failed = find.textContaining(
          l10n.messagesConversationActionFailed('').trim());
      expect(failed, findsOneWidget);
      expect(tester.getTopLeft(failed).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
          reason: 'the banner sits under the app bar of the screen left '
              'showing, not over its title');
      await _drainBanner(tester);
    });

    testWidgets('the inbox leaves out a conversation whose delete is pending',
        (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);

      final reads = api.threadsCalls;
      DmPendingHides.instance.add('c-p-1');
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Grace'), findsOneWidget);
      expect(api.threadsCalls, reads,
          reason: 'the list already holds the row it leaves out');

      DmPendingHides.instance.remove('c-p-1');
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
      expect(api.threadsCalls, reads + 1,
          reason: 'Undo or the commit is the server\'s to answer');
    });

    testWidgets('a poll that started before a delete was committed does not '
        'put the conversation back', (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api,
          pollInterval: const Duration(seconds: 30),
          threadPollInterval: _quiet)));
      await tester.pump();
      DmPendingHides.instance.add('c-p-1');
      await tester.pump();

      final stale = Completer<List<DmThread>>();
      api.threadsGate = stale;
      await tester.pump(const Duration(seconds: 30));
      final reads = api.threadsCalls;

      api
        ..threadsGate = null
        ..threads = [_thread('p-2', name: 'Grace')];
      DmPendingHides.instance.landed('c-p-1');
      await tester.pump();
      await tester.pump();
      expect(api.threadsCalls, reads + 1,
          reason: 'the poll in flight must not hold off the read the commit '
              'asks for');
      expect(find.text('Ada'), findsNothing);

      stale.complete(
          [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Grace'), findsOneWidget);
    });

    testWidgets('a landed delete stays out of the list while the read after '
        'it is in flight, and its marker goes once that read is held',
        (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();
      DmPendingHides.instance.add('c-p-1');
      await tester.pump();
      expect(find.text('Ada'), findsNothing);

      final fresh = Completer<List<DmThread>>();
      api.threadsGate = fresh;
      final reads = api.threadsCalls;
      DmPendingHides.instance.landed('c-p-1');
      await tester.pump();
      await tester.pump();
      expect(api.threadsCalls, reads + 1);
      expect(DmPendingHides.instance.contains('c-p-1'), isFalse);
      expect(find.text('Ada'), findsNothing,
          reason: 'the list held started before the delete landed');
      expect(DmPendingHides.instance.debugHasMarker('c-p-1'), isTrue);

      fresh.complete([_thread('p-2', name: 'Grace')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Grace'), findsOneWidget);
      expect(DmPendingHides.instance.debugHasMarker('c-p-1'), isFalse,
          reason: 'no read the list holds can list it any more');
    });

    testWidgets('signing out lets go of a landed delete the list was keeping',
        (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();
      DmPendingHides.instance.add('c-p-1');
      await tester.pump();

      final fresh = Completer<List<DmThread>>();
      addTearDown(() {
        if (!fresh.isCompleted) fresh.complete(const []);
      });
      api.threadsGate = fresh;
      DmPendingHides.instance.landed('c-p-1');
      await tester.pump();
      expect(DmPendingHides.instance.debugHasMarker('c-p-1'), isTrue,
          reason: 'the list held started before the delete landed');

      api.signedIn = false;
      api._authChanges.add(null);
      await tester.pump();
      expect(DmPendingHides.instance.debugHasMarker('c-p-1'), isFalse);
    });

    testWidgets('Undo brings the row back at once, before the re-read answers',
        (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pumpWidget(_app(MessagesScreen(api: api, pollInterval: _quiet)));
      await tester.pump();
      DmPendingHides.instance.add('c-p-1');
      await tester.pump();
      expect(find.text('Ada'), findsNothing);

      final fresh = Completer<List<DmThread>>();
      api.threadsGate = fresh;
      DmPendingHides.instance.remove('c-p-1');
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
      expect(DmPendingHides.instance.debugHasMarker('c-p-1'), isFalse);

      fresh.complete(
          [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('a list read that lands after the account changed is dropped, '
        'and the list is read again for the new one', (tester) async {
      final api = _FakeApi()..threads = [_thread('p-1', name: 'Ada')];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api, pollInterval: const Duration(seconds: 30))));
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);

      final stale = Completer<List<DmThread>>();
      api.threadsGate = stale;
      await tester.pump(const Duration(seconds: 30));

      api
        ..threadsGate = null
        ..threads = [_thread('p-2', name: 'Grace')];
      api.switchTo('someone-else');
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Grace'), findsOneWidget);

      stale.complete([_thread('p-1', name: 'Ada')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsNothing,
          reason: 'that read was the previous account\'s list');
      expect(find.text('Grace'), findsOneWidget);
    });

    testWidgets('a list read is dropped when the account changed before it '
        'landed, even before the change is announced', (tester) async {
      final api = _FakeApi()..threads = [_thread('p-1', name: 'Ada')];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api, pollInterval: const Duration(seconds: 30))));
      await tester.pump();

      final stale = Completer<List<DmThread>>();
      api.threadsGate = stale;
      await tester.pump(const Duration(seconds: 30));
      api.me = 'someone-else';
      stale.complete([_thread('p-9', name: 'Zed')]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Zed'), findsNothing);
    });

    testWidgets('a conversation the server lists again after the delete '
        'landed shows on the next read', (tester) async {
      final api = _FakeApi()
        ..threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pumpWidget(_app(MessagesScreen(
          api: api, pollInterval: const Duration(seconds: 30))));
      await tester.pump();
      DmPendingHides.instance.add('c-p-1');
      await tester.pump();
      api.threads = [_thread('p-2', name: 'Grace')];
      DmPendingHides.instance.landed('c-p-1');
      await tester.pump();
      await tester.pump();
      expect(find.text('Ada'), findsNothing);

      // A newer message brings the conversation back on the server.
      api.threads = [_thread('p-1', name: 'Ada'), _thread('p-2', name: 'Grace')];
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
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

    testWidgets('a failed read is retried on the next refresh, not cached',
        (tester) async {
      final api = _FakeApi()
        ..routeError = StateError('offline')
        ..newest = [_msg('m1', routeId: 'route-e', body: 'look')];
      await _pumpThread(tester, api, poll: const Duration(seconds: 10));
      await tester.pump();
      expect(find.text(l10n.messagesRouteUnavailable), findsOneWidget);

      api
        ..routeError = null
        ..routes['route-e'] = _route('route-e', name: 'River');
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();

      expect(find.text('River'), findsOneWidget);
      expect(api.routeReads, ['route-e', 'route-e']);
    });

    testWidgets('a route the reader may not see is cached across refreshes',
        (tester) async {
      final api = _FakeApi()
        ..routes['route-f'] = null
        ..newest = [_msg('m1', routeId: 'route-f', body: 'look')];
      await _pumpThread(tester, api, poll: const Duration(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text(l10n.messagesRouteUnavailable), findsOneWidget);
      expect(api.routeReads, ['route-f']);
    });

    testWidgets('a cached answer expires, so a route shared later recovers',
        (tester) async {
      final api = _FakeApi()..routes['route-g'] = null;
      var now = DateTime.utc(2026, 10, 14, 8);
      Future<void> pumpCard(int tick) async {
        await tester.pumpWidget(_app(Scaffold(
          body: DmRouteAttachment(
            api: api,
            routeId: 'route-g',
            refreshTick: tick,
            now: () => now,
          ),
        )));
        await tester.pump();
      }

      await pumpCard(0);
      expect(find.text(l10n.messagesRouteUnavailable), findsOneWidget);

      api.routes['route-g'] = _route('route-g', name: 'Shared later');
      now = now.add(const Duration(minutes: 1));
      await pumpCard(1);
      expect(find.text(l10n.messagesRouteUnavailable), findsOneWidget);
      expect(api.routeReads, ['route-g']);

      now = now.add(kDmRouteAttachmentCacheTtl);
      await pumpCard(2);
      expect(find.text('Shared later'), findsOneWidget);
      expect(api.routeReads, ['route-g', 'route-g']);
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

  group('entry points', () {
    const other = ProfileSummary(
      id: 'p-1',
      displayName: 'Ada',
      followerCount: 0,
      followingCount: 0,
      viewerFollows: false,
    );

    testWidgets('another runner\'s profile offers Message and opens the thread',
        (tester) async {
      final api = _FakeApi()..summary = other;
      await tester.pumpWidget(_app(ProfileScreen(api: api, userId: 'p-1')));
      await tester.pump();
      await tester.pump();

      final button = find.byKey(const ValueKey('profile-message'));
      expect(button, findsOneWidget);
      // A labelled button since the profile header redesign (decisions
      // § 1952), not an icon whose name lived only in a tooltip.
      expect(find.descendant(of: button, matching: find.text(l10n.profileMessage)),
          findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final thread = tester.widget<MessageThreadScreen>(
          find.byType(MessageThreadScreen));
      expect(thread.partnerId, 'p-1');
      expect(thread.partnerName, 'Ada');
    });

    testWidgets('your own profile has no Message action', (tester) async {
      final api = _FakeApi()
        ..summary = const ProfileSummary(
          id: _me,
          displayName: 'Me',
          followerCount: 0,
          followingCount: 0,
          viewerFollows: false,
        );
      await tester.pumpWidget(_app(ProfileScreen(api: api, userId: _me)));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('profile-message')), findsNothing);
    });

    testWidgets('signed out, a profile has no Message action', (tester) async {
      final api = _FakeApi(signedIn: false)..summary = other;
      await tester.pumpWidget(_app(ProfileScreen(api: api, userId: 'p-1')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('profile-message')), findsNothing);
    });

    testWidgets('a message notification opens the conversation with its sender',
        (tester) async {
      final api = _FakeApi()
        ..summary = const ProfileSummary(
          id: _me,
          displayName: 'Me',
          followerCount: 0,
          followingCount: 0,
          viewerFollows: false,
        )
        ..notifications = [
          NotificationView(
            row: NotificationRow(
              id: 'n1',
              userId: _me,
              actorId: 'p-7',
              kind: 'message',
              createdAt: DateTime.utc(2026, 10, 14, 8),
              refunded: false,
            ),
            actor: const PublicProfile(id: 'p-7', displayName: 'Grace'),
          ),
        ];
      await tester.pumpWidget(_app(ProfileScreen(
          api: api, userId: _me, initialTab: ProfileTab.notifications)));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text(l10n.profileNotifMessage('Grace')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final thread = tester.widget<MessageThreadScreen>(
          find.byType(MessageThreadScreen));
      expect(thread.partnerId, 'p-7');
      expect(thread.partnerName, 'Grace');
    });
  });
}
