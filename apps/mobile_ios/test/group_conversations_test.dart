// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart'
    show DirectMessageRow, KeysetPage, UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/group_create_screen.dart';
import '../lib/screens/group_thread_screen.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/widgets/group_members_sheet.dart';
import 'pump_until.dart';

const _me = 'me';
const _group = 'g-1';
const _quiet = Duration(hours: 1);

DirectMessageRow _msg(
  String id, {
  String from = 'p-1',
  int minute = 0,
  String? body,
  String kind = 'text',
}) =>
    DirectMessageRow(
      kind: kind,
      isGroup: true,
      id: id,
      conversationId: _group,
      senderId: from,
      body: body ?? 'body $id',
      createdAt: DateTime.utc(2026, 11, 10, 8, minute),
    );

GroupMember _member(String id, String? role,
        {String state = 'active', String? name}) =>
    GroupMember(userId: id, role: role, state: state, name: name);

DmThread _groupRow({
  String id = _group,
  String? title = 'Tuesday tempo',
  int? members = 3,
  String membership = 'active',
  String? lastBody = 'see you there',
  String lastKind = 'text',
}) =>
    DmThread(
      conversationId: id,
      partnerId: null,
      kind: 'group',
      title: title,
      memberCount: members,
      membershipState: membership,
      lastBody: lastBody,
      lastKind: lastKind,
      lastAt: DateTime.utc(2026, 11, 10, 9),
      lastFromMe: false,
      unread: 0,
    );

UserProfileRow _person(String id, String name) => UserProfileRow(
    profilePrivate: false, id: id, displayName: name, shadowHidden: false);

class _FakeApi extends ApiClient {
  /// The flag read: null is a failed read.
  bool? groupsOn = true;
  int flagReads = 0;

  List<DmThread> threads = [];
  List<GroupInvite> invites = [];
  List<DirectMessageRow> messages = [];
  List<GroupPlaceholder> placeholders = [];
  List<GroupMember> members = [
    _member(_me, 'owner', name: 'Me'),
    _member('p-1', 'member', name: 'Ada'),
    _member('p-2', 'admin', name: 'Grace'),
  ];
  Object? membersError;
  List<UserProfileRow> followers = [];
  List<UserProfileRow> following = [];

  final List<String> calls = [];
  final List<String> sent = [];
  ({String title, List<String> invitees})? created;
  List<String>? invited;

  @override
  String? get userId => _me;

  @override
  Stream<String?> get authUserChanges => const Stream.empty();

  @override
  Future<bool?> fetchGroupMessagesEnabled() async {
    flagReads++;
    return groupsOn;
  }

  @override
  Future<List<DmThread>> fetchDmThreads() async => threads;

  @override
  Future<List<GroupInvite>> fetchGroupInvites() async => invites;

  @override
  Future<void> acceptGroupInvite(String conversationId) async {
    calls.add('accept:$conversationId');
  }

  @override
  Future<void> declineGroupInvite(String conversationId) async {
    calls.add('decline:$conversationId');
  }

  @override
  Future<String> createGroupConversation(
      String title, List<String> invitees) async {
    created = (title: title, invitees: invitees);
    return 'g-new';
  }

  @override
  Future<int> inviteToGroup(String conversationId, List<String> ids) async {
    invited = ids;
    return ids.length;
  }

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowers(String userId,
          {int limit = 100, List<Object?>? after}) async =>
      KeysetPage(followers, null);

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowing(String userId,
          {int limit = 100, List<Object?>? after}) async =>
      KeysetPage(following, null);

  @override
  Future<DmThreadPage> fetchGroupThread(String conversationId,
          {DirectMessageRow? before, int limit = 50}) async =>
      DmThreadPage(messages: messages, hasMore: false);

  @override
  Future<List<GroupMember>> fetchGroupMembers(String conversationId) async {
    if (membersError != null) throw membersError!;
    return members;
  }

  @override
  Future<Map<String, ({String? name, String? avatarUrl})>> fetchGroupProfiles(
          List<String> userIds) async =>
      {};

  @override
  Future<List<GroupPlaceholder>> fetchGroupBlockedPlaceholders(
          String conversationId, DateTime? since) async =>
      placeholders;

  @override
  Future<List<DmReactionRecord>> fetchDmReactions(List<String> ids) async =>
      const [];

  @override
  Future<void> markGroupRead(String conversationId, String through) async {
    calls.add('read:$through');
  }

  @override
  Future<bool> fetchDmImagesEnabled() async => false;

  @override
  Future<DirectMessageRow> sendGroupMessage(String conversationId, String body,
      {String? imageId}) async {
    sent.add(body);
    return _msg('sent-${sent.length}', from: _me, minute: 59, body: body);
  }

  @override
  Future<void> leaveGroup(String conversationId) async {
    calls.add('leave:$conversationId');
  }

  @override
  Future<void> setDmConversationMuted(String conversationId,
      {required bool muted}) async {
    calls.add('mute:$muted');
  }

  @override
  Future<void> setGroupMemberRole(
      String conversationId, String userId, String role) async {
    calls.add('role:$userId:$role');
  }

  @override
  Future<void> transferGroupOwnership(
      String conversationId, String userId) async {
    calls.add('transfer:$userId');
  }

  @override
  Future<void> removeGroupMember(String conversationId, String userId) async {
    calls.add('remove:$userId');
  }

  @override
  Future<void> renameGroup(String conversationId, String title) async {
    calls.add('rename:$title');
  }
}

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _drainBanner(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 7));

bool _shows(Finder f) => f.evaluate().isNotEmpty;

/// The fakes answer in microtasks, so a few frames finish what a tap
/// started; a banner the action raises stays on the fake clock for
/// [_drainBanner] to expire.
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Future<void> _pumpInbox(WidgetTester tester, _FakeApi api,
    {bool requests = false}) async {
  await tester.pumpWidget(_app(MessagesScreen(
    api: api,
    pollInterval: _quiet,
    threadPollInterval: _quiet,
    initialShowRequests: requests,
  )));
  await pumpUntil(tester, () => !_shows(find.byType(LinearProgressIndicator)),
      describe: 'the inbox to load');
  await tester.pump();
}

Future<void> _pumpThread(WidgetTester tester, _FakeApi api,
    {bool left = false}) async {
  await tester.pumpWidget(_app(GroupThreadScreen(
    api: api,
    conversationId: _group,
    title: 'Tuesday tempo',
    initialLeft: left,
    pollInterval: _quiet,
  )));
  await pumpUntil(
    tester,
    () =>
        _shows(find.byKey(const ValueKey('group-unavailable'))) ||
        _shows(find.byKey(const ValueKey('group-history-note'))) ||
        _shows(find.byKey(const ValueKey('group-left-notice'))),
    describe: 'the group thread to load',
  );
}

void main() {
  group('inbox', () {
    testWidgets('with the flag off, groups and New group stay hidden',
        (tester) async {
      final api = _FakeApi()
        ..groupsOn = false
        ..threads = [_groupRow()];
      await _pumpInbox(tester, api);
      expect(find.text('Tuesday tempo'), findsNothing);
      expect(find.byKey(const ValueKey('inbox-new-group')), findsNothing);
    });

    testWidgets(
        'a failed flag read hides groups until the next poll reads it '
        'again; a definite off is not re-read', (tester) async {
      final api = _FakeApi()
        ..groupsOn = null
        ..threads = [_groupRow()];
      const poll = Duration(seconds: 30);
      await tester.pumpWidget(_app(MessagesScreen(
        api: api,
        pollInterval: poll,
        threadPollInterval: _quiet,
      )));
      await pumpUntil(
          tester, () => !_shows(find.byType(LinearProgressIndicator)),
          describe: 'the inbox to load');
      await tester.pump();
      expect(find.text('Tuesday tempo'), findsNothing);
      expect(find.byKey(const ValueKey('inbox-new-group')), findsNothing);

      api.groupsOn = true;
      await tester.pump(poll);
      await pumpUntil(
          tester, () => _shows(find.byKey(const ValueKey('inbox-new-group'))),
          describe: 'the poll to read the flag again');
      expect(find.text('Tuesday tempo'), findsOneWidget);
      expect(api.flagReads, 2);

      final off = _FakeApi()
        ..groupsOn = false
        ..threads = [_groupRow()];
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(MessagesScreen(
        api: off,
        pollInterval: poll,
        threadPollInterval: _quiet,
      )));
      await pumpUntil(
          tester, () => !_shows(find.byType(LinearProgressIndicator)),
          describe: 'the inbox to load');
      await tester.pump(poll);
      await tester.pump();
      expect(off.flagReads, 1);
      expect(find.text('Tuesday tempo'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a group row shows its title, size and the right preview',
        (tester) async {
      final api = _FakeApi()
        ..threads = [
          _groupRow(),
          _groupRow(
              id: 'g-2',
              title: 'Hill reps',
              members: null,
              membership: 'left',
              lastBody: 'bye'),
          _groupRow(
              id: 'g-3',
              title: 'Tempo club',
              lastKind: 'group_renamed',
              lastBody: 'Tempo club'),
        ];
      await _pumpInbox(tester, api);
      await pumpUntil(
          tester, () => _shows(find.byKey(const ValueKey('inbox-new-group'))),
          describe: 'the flag to open the group surfaces');
      expect(find.text('Tuesday tempo'), findsOneWidget);
      expect(find.text('3 members'), findsNWidgets(2));
      expect(find.text('You left this group'), findsOneWidget);
      expect(find.text('Group renamed to Tempo club'), findsOneWidget);
    });

    testWidgets('an invitation sits in Requests; Join opens the group',
        (tester) async {
      final api = _FakeApi()
        ..invites = [
          GroupInvite(
            conversationId: _group,
            title: 'Tuesday tempo',
            inviterName: 'Ada',
            invitedAt: DateTime.utc(2026, 11, 10, 9),
            memberCount: 4,
          ),
        ];
      await _pumpInbox(tester, api);
      await pumpUntil(tester,
          () => _shows(find.byKey(const ValueKey('inbox-show-requests'))),
          describe: 'the Requests link');
      expect(find.text('Requests (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inbox-show-requests')));
      await tester.pump();
      expect(find.text('Ada invited you · 4 members'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('group-invite-accept-g-1')));
      await pumpUntil(tester, () => _shows(find.byType(GroupThreadScreen)),
          describe: 'the joined group to open');
      expect(api.calls, contains('accept:g-1'));
      await _drainBanner(tester);
    });

    testWidgets('Decline asks first, and Cancel leaves the invitation',
        (tester) async {
      final api = _FakeApi()
        ..invites = [
          GroupInvite(
            conversationId: _group,
            title: 'Tuesday tempo',
            invitedAt: DateTime.utc(2026, 11, 10, 9),
            memberCount: 4,
          ),
        ];
      await _pumpInbox(tester, api, requests: true);
      await pumpUntil(
          tester,
          () => _shows(
              find.byKey(const ValueKey('group-invite-decline-g-1'))),
          describe: 'the invitation row');

      await tester.tap(find.byKey(const ValueKey('group-invite-decline-g-1')));
      await tester.pump();
      expect(find.text('Decline the invitation to Tuesday tempo?'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(api.calls, isNot(contains('decline:g-1')));

      await tester.tap(find.byKey(const ValueKey('group-invite-decline-g-1')));
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Decline')));
      await pumpUntil(tester, () => api.calls.contains('decline:g-1'),
          describe: 'the decline to reach the server');
      await tester.pump();
      expect(find.text('Tuesday tempo'), findsNothing);
      await _drainBanner(tester);
    });
  });

  group('new group', () {
    testWidgets('needs a title and two people, then invites them',
        (tester) async {
      final api = _FakeApi()
        ..followers = [_person('p-1', 'Ada'), _person('p-2', 'Grace')]
        ..following = [_person('p-3', 'Linus')];
      String? popped;
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                    builder: (_) => GroupCreateScreen(api: api)));
          },
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await pumpUntil(
          tester, () => _shows(find.byKey(const ValueKey('group-person-p-1'))),
          describe: 'the follow graph');

      final submit = find.byKey(const ValueKey('group-create-submit'));
      FilledButton button() => tester.widget<FilledButton>(submit);
      await tester.enterText(
          find.byKey(const ValueKey('group-title-input')), '  Tempo  ');
      await tester.tap(find.byKey(const ValueKey('group-person-p-1')));
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'one person is not a group');
      await tester.tap(find.byKey(const ValueKey('group-person-p-3')));
      await tester.pump();
      expect(find.text('2 of 31 selected'), findsOneWidget);
      expect(button().onPressed, isNotNull);

      await tester.tap(submit);
      await pumpUntil(tester, () => popped != null,
          describe: 'the screen to pop with the new group');
      expect(api.created?.title, 'Tempo');
      expect(api.created?.invitees, ['p-1', 'p-3']);
      expect(popped, 'g-new');
      await _drainBanner(tester);
    });
  });

  group('thread', () {
    testWidgets('names senders, draws the rename line and the blocked place',
        (tester) async {
      final api = _FakeApi()
        ..messages = [
          _msg('m1', from: 'p-1', minute: 1, body: 'tempo at 6'),
          _msg('m2',
              from: 'p-2', minute: 2, body: 'Tempo club', kind: 'group_renamed'),
          _msg('m4', from: _me, minute: 4, body: 'in'),
        ]
        ..placeholders = [(id: 'm3', createdAt: DateTime.utc(2026, 11, 10, 8, 3))];
      await _pumpThread(tester, api);
      await pumpUntil(
          tester, () => _shows(find.text('Message from someone you blocked')),
          describe: 'the blocked placeholder');

      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace renamed the group to Tempo club'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-title')), findsOneWidget);
      expect(find.text('Tempo club'), findsOneWidget,
          reason: 'the newest rename line names the title');
      expect(find.text("Messages from before you joined aren't shown."),
          findsOneWidget);
      expect(api.calls, contains('read:m4'));
    });

    testWidgets('sends to the group and keeps a draft per group',
        (tester) async {
      final api = _FakeApi()..messages = [_msg('m1')];
      await _pumpThread(tester, api);
      await tester.enterText(
          find.byKey(const ValueKey('message-composer')), 'half-typed');
      await tester.pumpWidget(const SizedBox());
      await _pumpThread(tester, api);
      expect(find.text('half-typed'), findsOneWidget,
          reason: 'coming back to the group keeps what was typed');

      await tester.tap(find.byKey(const ValueKey('message-send')));
      await pumpUntil(tester, () => api.sent.isNotEmpty,
          describe: 'the send');
      await tester.pump();
      expect(api.sent, ['half-typed']);
      expect(find.text('half-typed'), findsOneWidget,
          reason: 'the stored message is on screen');
      final composer = tester.widget<TextField>(
          find.byKey(const ValueKey('message-composer')));
      expect(composer.controller!.text, isEmpty);
    });

    testWidgets(
        'a failed flag read shows nothing of the group, and the next poll '
        'opens it', (tester) async {
      final api = _FakeApi()
        ..groupsOn = null
        ..messages = [_msg('m1', body: 'tempo at 6')];
      const poll = Duration(seconds: 10);
      await tester.pumpWidget(_app(GroupThreadScreen(
        api: api,
        conversationId: _group,
        title: 'Tuesday tempo',
        pollInterval: poll,
      )));
      await pumpUntil(tester, () => api.flagReads == 1,
          describe: 'the first flag read');
      await tester.pump();
      expect(find.byKey(const ValueKey('group-unavailable')), findsNothing);
      expect(find.text('tempo at 6'), findsNothing);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);

      api.groupsOn = true;
      await tester.pump(poll);
      await pumpUntil(tester, () => _shows(find.text('tempo at 6')),
          describe: 'the poll to read the flag again and load the thread');
      expect(find.byKey(const ValueKey('message-composer')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Leave asks first; Cancel stays', (tester) async {
      final api = _FakeApi()..messages = [_msg('m1')];
      await _pumpThread(tester, api);
      await tester.tap(find.byKey(const ValueKey('group-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-leave')));
      await tester.pumpAndSettle();
      expect(find.text('Leave Tuesday tempo?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(api.calls, isNot(contains('leave:g-1')));

      await tester.tap(find.byKey(const ValueKey('group-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('group-leave')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Leave')));
      await pumpUntil(tester, () => api.calls.contains('leave:g-1'),
          describe: 'the leave to reach the server');
      await _drainBanner(tester);
    });

    testWidgets('someone who left reads only their own messages, no composer',
        (tester) async {
      final api = _FakeApi()
        ..membersError = const GroupActionRefused(GroupRefusal.notFound)
        ..messages = [
          _msg('m1', from: 'p-1', body: 'not for a leaver'),
          _msg('m2', from: _me, minute: 1, body: 'mine'),
        ];
      await _pumpThread(tester, api, left: true);
      expect(find.byKey(const ValueKey('group-left-notice')), findsOneWidget);
      expect(find.text('mine'), findsOneWidget);
      expect(find.text('not for a leaver'), findsNothing);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
      expect(find.byKey(const ValueKey('group-leave')), findsNothing);
    });

    testWidgets('a group the viewer is not in, or the flag off, is unavailable',
        (tester) async {
      final api = _FakeApi()
        ..membersError = const GroupActionRefused(GroupRefusal.notFound);
      await _pumpThread(tester, api);
      expect(find.text("This group isn't available."), findsOneWidget);

      final off = _FakeApi()
        ..groupsOn = false
        ..messages = [_msg('m1')];
      await tester.pumpWidget(const SizedBox());
      await _pumpThread(tester, off);
      expect(find.text("This group isn't available."), findsOneWidget);
      expect(find.byKey(const ValueKey('message-composer')), findsNothing);
    });

    testWidgets('mute runs at once and the button says which way it goes',
        (tester) async {
      final api = _FakeApi()..messages = [_msg('m1')];
      await _pumpThread(tester, api);
      await tester.tap(find.byKey(const ValueKey('group-mute-toggle')));
      await pumpUntil(tester, () => api.calls.contains('mute:true'),
          describe: 'the mute');
      await tester.pump();
      final mute = tester.widget<IconButton>(
          find.byKey(const ValueKey('group-mute-toggle')));
      expect(mute.isSelected, isTrue);
      await _drainBanner(tester);
    });
  });

  group('members sheet', () {
    Future<void> pumpSheet(WidgetTester tester, _FakeApi api,
        {List<GroupMember>? members}) async {
      await tester.pumpWidget(_app(Scaffold(
        body: GroupMembersSheet(
          api: api,
          conversationId: _group,
          title: 'Tuesday tempo',
          members: members ?? api.members,
          onChanged: () async {},
        ),
      )));
      await tester.pump();
    }

    Future<void> pick(WidgetTester tester, String user, String action) async {
      await tester.tap(find.byKey(ValueKey('group-member-menu-$user')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('group-member-$action-$user')));
      await tester.pumpAndSettle();
    }

    testWidgets('the owner sees roles, admins first, invitations last',
        (tester) async {
      final api = _FakeApi()
        ..members = [
          _member('i-1', null, state: 'invited', name: 'Ivy'),
          _member('p-1', 'member', name: 'Ada'),
          _member(_me, 'owner', name: 'Me'),
          _member('p-2', 'admin', name: 'Grace'),
        ];
      await pumpSheet(tester, api);
      expect(find.text('3 members'), findsOneWidget);
      final order = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => t.key)
          .toList();
      expect(order, [
        const ValueKey('group-member-me'),
        const ValueKey('group-member-p-2'),
        const ValueKey('group-member-p-1'),
        const ValueKey('group-member-i-1'),
      ]);
      expect(find.text('Me (you)'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-member-menu-me')), findsNothing);
    });

    testWidgets('making an admin runs at once; removal and hand-over confirm',
        (tester) async {
      final api = _FakeApi();
      await pumpSheet(tester, api);

      await pick(tester, 'p-1', 'promote');
      expect(api.calls, contains('role:p-1:admin'));
      await _drainBanner(tester);

      await pick(tester, 'p-1', 'remove');
      expect(find.text('Remove Ada from the group?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.calls, isNot(contains('remove:p-1')));
      await pick(tester, 'p-1', 'remove');
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Remove')));
      await _flush(tester);
      expect(api.calls.contains('remove:p-1'), isTrue);
      await _drainBanner(tester);

      await pick(tester, 'p-2', 'transfer');
      expect(find.text('Make Grace the owner?'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Make owner')));
      await _flush(tester);
      expect(api.calls.contains('transfer:p-2'), isTrue);
      await _drainBanner(tester);
    });

    testWidgets('an admin cancels an invitation but changes no roles',
        (tester) async {
      final api = _FakeApi()
        ..members = [
          _member('o-1', 'owner', name: 'Olu'),
          _member(_me, 'admin', name: 'Me'),
          _member('p-1', 'member', name: 'Ada'),
          _member('i-1', null, state: 'invited', name: 'Ivy'),
        ];
      await pumpSheet(tester, api);
      expect(find.byKey(const ValueKey('group-member-menu-o-1')), findsNothing,
          reason: 'nobody removes the owner');
      await tester.tap(find.byKey(const ValueKey('group-member-menu-p-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('group-member-promote-p-1')),
          findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await pick(tester, 'i-1', 'remove');
      expect(find.text('Cancel the invitation to Ivy?'), findsOneWidget);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel invitation')));
      await _flush(tester);
      expect(api.calls.contains('remove:i-1'), isTrue);
      await _drainBanner(tester);
    });

    testWidgets('a member sees the roster and nothing to manage',
        (tester) async {
      final api = _FakeApi()
        ..members = [
          _member('o-1', 'owner', name: 'Olu'),
          _member(_me, 'member', name: 'Me'),
        ];
      await pumpSheet(tester, api);
      expect(find.byKey(const ValueKey('group-rename')), findsNothing);
      expect(find.byKey(const ValueKey('group-invite-more')), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('invite picks from the follow graph, minus the group',
        (tester) async {
      final api = _FakeApi()
        ..followers = [_person('p-1', 'Ada'), _person('p-9', 'Zed')];
      await pumpSheet(tester, api);
      await tester.tap(find.byKey(const ValueKey('group-invite-more')));
      await pumpUntil(
          tester, () => _shows(find.byKey(const ValueKey('group-person-p-9'))),
          describe: 'the picker');
      expect(find.byKey(const ValueKey('group-person-p-1')), findsNothing,
          reason: 'already a member');
      await tester.tap(find.byKey(const ValueKey('group-person-p-9')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group-invite-send')));
      await _flush(tester);
      expect(api.invited, isNotNull);
      expect(api.invited, ['p-9']);
      await _drainBanner(tester);
    });

    testWidgets('rename saves a trimmed title', (tester) async {
      final api = _FakeApi();
      await pumpSheet(tester, api);
      await tester.tap(find.byKey(const ValueKey('group-rename')));
      await tester.pump();
      await tester.enterText(
          find.byKey(const ValueKey('group-rename-input')), '  Hill reps ');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group-rename-save')));
      await _flush(tester);
      expect(api.calls.contains('rename:Hill reps'), isTrue);
      await _drainBanner(tester);
    });
  });
}
