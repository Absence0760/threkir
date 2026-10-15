// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart'
    show DirectMessageRow, KeysetPage, UserProfileRow;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/dm_recipients.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/route_detail_screen.dart';
import '../lib/widgets/audience_sheet.dart' show audienceLinkUrl;
import '../lib/widgets/send_route_sheet.dart';
import 'pump_until.dart';

const _me = 'me';
const _routeId = 'r1';
const _shareUrl = 'https://threkir.com/share/route/r1';

UserProfileRow _person(String id, String? name) =>
    UserProfileRow(id: id, displayName: name, shadowHidden: false);

class _FakeApi extends ApiClient {
  _FakeApi({this.signedIn = true});

  bool signedIn;
  List<UserProfileRow> followers = [];
  List<UserProfileRow> following = [];
  Object? followError;
  int followReads = 0;

  bool audienceOn = false;
  int publicCalls = 0;

  /// Every write in the order it reached the server, so a test can assert
  /// the grant landed before the message.
  final List<String> writes = [];
  final List<({String to, String body, String? routeId})> sent = [];
  Completer<void>? sendGate;
  Object? sendError;
  Object? shareError;

  @override
  String? get userId => signedIn ? _me : null;

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowers(
    String userId, {
    int limit = 100,
    List<Object?>? after,
  }) async {
    followReads++;
    if (followError != null) throw followError!;
    return KeysetPage(followers, null);
  }

  @override
  Future<KeysetPage<UserProfileRow>> fetchFollowing(
    String userId, {
    int limit = 100,
    List<Object?>? after,
  }) async {
    if (followError != null) throw followError!;
    return KeysetPage(following, null);
  }

  @override
  Future<void> addShare(
    ShareableKind kind,
    String id,
    String recipientId,
  ) async {
    writes.add('share:${kind.name}:$id:$recipientId');
    if (shareError != null) throw shareError!;
  }

  @override
  Future<DirectMessageRow> sendDm(
    String recipientId,
    String body, {
    String? routeId,
  }) async {
    writes.add('dm:$recipientId');
    sent.add((to: recipientId, body: body, routeId: routeId));
    final gate = sendGate;
    if (gate != null) await gate.future;
    if (sendError != null) throw sendError!;
    return DirectMessageRow(
      id: 'm-${sent.length}',
      senderId: _me,
      recipientId: recipientId,
      body: body,
      createdAt: DateTime.utc(2026, 10, 15, 8),
      routeId: routeId,
    );
  }

  @override
  Future<bool> audienceSharingEnabled() async => audienceOn;

  @override
  Future<bool> isRouteBookmarked(String routeId) async => false;

  @override
  Future<List<cm.Waypoint>> clipRouteForViewer(String routeId) async =>
      const [];

  @override
  Future<List<cm.RouteReviewRow>> getRouteReviews(String routeId) async =>
      const [];

  @override
  Future<void> setRoutePublic(String routeId, bool isPublic) async {
    publicCalls++;
  }
}

Finder _inSheet(Finder f) => find.descendant(
  of: find.byKey(const ValueKey('send-route-sheet')),
  matching: f,
);

Finder _recipient(String id) =>
    find.byKey(ValueKey('send-route-recipient-$id'));

/// A bare host whose one button opens the sheet, recording how it closed.
Future<List<DmRecipient?>> _pumpHost(
  WidgetTester tester,
  _FakeApi api, {
  bool grantAccess = false,
}) async {
  final results = <DmRecipient?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              results.add(
                await showSendRouteSheet(
                  context,
                  api: api,
                  routeId: _routeId,
                  shareUrl: _shareUrl,
                  grantAccess: grantAccess,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return results;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    dotenv.loadFromString(isOptional: true);
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('SendRouteSheet', () {
    testWidgets(
      'offers both follow directions, tagged, and sends the link with the '
      'route attached',
      (tester) async {
        final api = _FakeApi()
          ..followers = [_person('a', 'Ana'), _person(_me, 'Me')]
          ..following = [_person('a', 'Ana'), _person('b', 'Bo')];
        await _pumpHost(tester, api);
        await pumpUntil(
          tester,
          () => _recipient('b').evaluate().isNotEmpty,
          describe: 'the recipients to load',
        );
        await _settle(tester);

        expect(
          _recipient(_me),
          findsNothing,
          reason: 'the sender is never offered as a recipient',
        );
        expect(
          find.descendant(
            of: _recipient('a'),
            matching: find.text(l10n.routeDetailSendDmRelationMutual),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _recipient('b'),
            matching: find.text(l10n.routeDetailSendDmRelationYouFollow),
          ),
          findsOneWidget,
        );
        expect(
          _inSheet(find.text(l10n.routeDetailSendDmLinkNote)),
          findsOneWidget,
        );

        await tester.tap(_recipient('b'));
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('send-route-sent'))
              .evaluate()
              .isNotEmpty,
          describe: 'the sent confirmation',
        );
        await _settle(tester);

        expect(api.sent.single, (to: 'b', body: _shareUrl, routeId: _routeId));
        expect(api.writes, ['dm:b'], reason: 'a public send grants nothing');
        expect(find.text(l10n.routeDetailSendDmSent('Bo')), findsOneWidget);
      },
    );

    testWidgets('a private send grants that one person before the message', (
      tester,
    ) async {
      final api = _FakeApi()..followers = [_person('a', 'Ana')];
      await _pumpHost(tester, api, grantAccess: true);
      await pumpUntil(
        tester,
        () => _recipient('a').evaluate().isNotEmpty,
        describe: 'the recipients to load',
      );
      await _settle(tester);
      expect(
        _inSheet(find.text(l10n.routeDetailSendDmPrivateNote)),
        findsOneWidget,
      );

      await tester.tap(_recipient('a'));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('send-route-sent')).evaluate().isNotEmpty,
        describe: 'the sent confirmation',
      );
      await _settle(tester);
      expect(api.writes, ['share:route:$_routeId:a', 'dm:a']);
    });

    testWidgets('a refused grant stops the send and says why', (tester) async {
      final api = _FakeApi()
        ..followers = [_person('a', 'Ana')]
        ..shareError = StateError('grant refused');
      await _pumpHost(tester, api, grantAccess: true);
      await pumpUntil(
        tester,
        () => _recipient('a').evaluate().isNotEmpty,
        describe: 'the recipients to load',
      );
      await _settle(tester);

      await tester.tap(_recipient('a'));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('send-route-error'))
            .evaluate()
            .isNotEmpty,
        describe: 'the send error',
      );
      await _settle(tester);
      expect(
        api.sent,
        isEmpty,
        reason: 'a message whose link does not open must not go',
      );
      expect(find.byKey(const ValueKey('send-route-sent')), findsNothing);
    });

    testWidgets(
      'the follow / block refusal reads as its own sentence and never as sent',
      (tester) async {
        final api = _FakeApi()
          ..followers = [_person('a', 'Ana')]
          ..sendError = const DmSendNotPermitted();
        await _pumpHost(tester, api);
        await pumpUntil(
          tester,
          () => _recipient('a').evaluate().isNotEmpty,
          describe: 'the recipients to load',
        );
        await _settle(tester);

        await tester.tap(_recipient('a'));
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('send-route-error'))
              .evaluate()
              .isNotEmpty,
          describe: 'the send error',
        );
        await _settle(tester);
        expect(
          _inSheet(find.text(l10n.messagesSendNotAllowed)),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('send-route-sent')), findsNothing);
      },
    );

    testWidgets('one send at a time: a second tap while one is in flight is '
        'ignored', (tester) async {
      final api = _FakeApi()
        ..followers = [_person('a', 'Ana'), _person('b', 'Bo')]
        ..sendGate = Completer<void>();
      await _pumpHost(tester, api);
      await pumpUntil(
        tester,
        () => _recipient('b').evaluate().isNotEmpty,
        describe: 'the recipients to load',
      );
      await _settle(tester);

      await tester.tap(_recipient('a'));
      await tester.pump();
      expect(
        find.descendant(
          of: _recipient('a'),
          matching: find.text(l10n.routeDetailSendDmSending),
        ),
        findsOneWidget,
      );
      await tester.tap(_recipient('b'), warnIfMissed: false);
      await tester.pump();
      expect(api.sent.map((s) => s.to).toList(), ['a']);

      api.sendGate!.complete();
      await pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('send-route-sent')).evaluate().isNotEmpty,
        describe: 'the sent confirmation',
      );
      await _settle(tester);
      expect(api.sent.length, 1);
    });

    testWidgets(
      'a failed recipient read is an error with Retry, never the empty copy',
      (tester) async {
        final api = _FakeApi()..followError = StateError('offline');
        await _pumpHost(tester, api);
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('send-route-load-error'))
              .evaluate()
              .isNotEmpty,
          describe: 'the load error',
        );
        await _settle(tester);
        expect(find.byKey(const ValueKey('send-route-empty')), findsNothing);

        api
          ..followError = null
          ..followers = [_person('a', 'Ana')];
        await tester.tap(_inSheet(find.text(l10n.audienceRetry)));
        await pumpUntil(
          tester,
          () => _recipient('a').evaluate().isNotEmpty,
          describe: 'the retried load',
        );
        await _settle(tester);
        expect(api.followReads, 2);
      },
    );

    testWidgets('nobody either way is the empty copy, not an error', (
      tester,
    ) async {
      final api = _FakeApi();
      await _pumpHost(tester, api);
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('send-route-empty'))
            .evaluate()
            .isNotEmpty,
        describe: 'the empty state',
      );
      await _settle(tester);
      expect(find.byKey(const ValueKey('send-route-load-error')), findsNothing);
    });

    testWidgets('the search folds accents and says when nobody matches', (
      tester,
    ) async {
      final api = _FakeApi()
        ..followers = [_person('a', 'Émile Zola'), _person('b', 'Bo')];
      await _pumpHost(tester, api);
      await pumpUntil(
        tester,
        () => _recipient('b').evaluate().isNotEmpty,
        describe: 'the recipients to load',
      );
      await _settle(tester);

      await tester.enterText(
        find.byKey(const ValueKey('send-route-search')),
        'emile',
      );
      await tester.pump();
      expect(_recipient('a'), findsOneWidget);
      expect(_recipient('b'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('send-route-search')),
        'xyz',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('send-route-no-matches')),
        findsOneWidget,
      );
    });

    testWidgets('Open conversation hands back the recipient; Done hands back '
        'nothing', (tester) async {
      final api = _FakeApi()..followers = [_person('a', 'Ana')];
      final results = await _pumpHost(tester, api);
      await pumpUntil(
        tester,
        () => _recipient('a').evaluate().isNotEmpty,
        describe: 'the recipients to load',
      );
      await _settle(tester);
      await tester.tap(_recipient('a'));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('send-route-sent')).evaluate().isNotEmpty,
        describe: 'the sent confirmation',
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('send-route-open-thread')));
      await _settle(tester);
      expect(results.single?.id, 'a');

      await tester.tap(find.text('open'));
      await _settle(tester);
      await pumpUntil(
        tester,
        () => _recipient('a').evaluate().isNotEmpty,
        describe: 'the recipients to load again',
      );
      await _settle(tester);
      await tester.tap(_recipient('a'));
      await pumpUntil(
        tester,
        () =>
            find.byKey(const ValueKey('send-route-done')).evaluate().isNotEmpty,
        describe: 'the sent confirmation',
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('send-route-done')));
      await _settle(tester);
      expect(results.length, 2);
      expect(results.last, isNull);
    });
  });

  group('route detail Send to a follower', () {
    Future<void> pumpDetail(
      WidgetTester tester,
      _FakeApi api, {
      required bool isPublic,
      required bool isOwner,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RouteDetailScreen(
            route: cm.Route(
              id: _routeId,
              userId: isOwner ? _me : 'someone-else',
              name: 'River Loop',
              waypoints: const [],
              distanceMetres: 8500,
              isPublic: isPublic,
            ),
            routeStore: LocalRouteStore(),
            preferences: prefs,
            apiClient: api,
            isOwner: isOwner,
          ),
        ),
      );
      // pumpAndSettle would spin LiveRunMap's pulse animation.
      await tester.pump();
      await tester.pump(Duration.zero);
    }

    Future<void> openShareMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.ios_share));
      await _settle(tester);
    }

    testWidgets(
      'a private route confirms the public flip first, and cancel leaves it '
      'private with the picker closed',
      (tester) async {
        final api = _FakeApi()..followers = [_person('a', 'Ana')];
        await pumpDetail(tester, api, isPublic: false, isOwner: true);

        await openShareMenu(tester);
        await tester.tap(find.text(l10n.routeDetailSendToFollower));
        await _settle(tester);
        final confirm = find.byType(AlertDialog);
        expect(
          find.descendant(
            of: confirm,
            matching: find.text(l10n.routeDetailShareConfirmTitle),
          ),
          findsOneWidget,
        );

        await tester.tap(
          find.descendant(
            of: confirm,
            matching: find.text(l10n.routeDetailCancel),
          ),
        );
        await _settle(tester);
        expect(api.publicCalls, 0);
        expect(find.byKey(const ValueKey('send-route-sheet')), findsNothing);
        expect(api.followReads, 0);

        await openShareMenu(tester);
        await tester.tap(find.text(l10n.routeDetailSendToFollower));
        await _settle(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(l10n.routeDetailShareConfirmCta),
          ),
        );
        await pumpUntil(
          tester,
          () => _recipient('a').evaluate().isNotEmpty,
          describe: 'the picker after the flip',
        );
        await _settle(tester);
        expect(api.publicCalls, 1);
        expect(
          _inSheet(find.text(l10n.routeDetailSendDmLinkNote)),
          findsOneWidget,
        );

        await tester.tap(_recipient('a'));
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('send-route-sent'))
              .evaluate()
              .isNotEmpty,
          describe: 'the sent confirmation',
        );
        await _settle(tester);
        expect(api.sent.single.body, routeShareUrl(_routeId));
        expect(api.sent.single.routeId, _routeId);

        // Let the made-public banner's dismiss timer run out.
        await tester.pump(const Duration(seconds: 7));
      },
    );

    testWidgets(
      'with audience sharing on, a private route stays private and the send '
      'grants the one recipient',
      (tester) async {
        final api = _FakeApi()
          ..audienceOn = true
          ..followers = [_person('a', 'Ana')];
        await pumpDetail(tester, api, isPublic: false, isOwner: true);

        await openShareMenu(tester);
        await tester.tap(find.text(l10n.routeDetailSendToFollower));
        await pumpUntil(
          tester,
          () => _recipient('a').evaluate().isNotEmpty,
          describe: 'the picker',
        );
        await _settle(tester);
        expect(find.byType(AlertDialog), findsNothing);
        expect(api.publicCalls, 0);
        expect(
          _inSheet(find.text(l10n.routeDetailSendDmPrivateNote)),
          findsOneWidget,
        );

        await tester.tap(_recipient('a'));
        await pumpUntil(
          tester,
          () => find
              .byKey(const ValueKey('send-route-sent'))
              .evaluate()
              .isNotEmpty,
          describe: 'the sent confirmation',
        );
        await _settle(tester);
        expect(api.writes, ['share:route:$_routeId:a', 'dm:a']);
        expect(
          api.sent.single.body,
          audienceLinkUrl(ShareableKind.route, _routeId),
        );
        expect(api.publicCalls, 0);
      },
    );

    testWidgets('a public route opens the picker with no confirm', (
      tester,
    ) async {
      final api = _FakeApi()..following = [_person('b', 'Bo')];
      await pumpDetail(tester, api, isPublic: true, isOwner: false);

      await openShareMenu(tester);
      await tester.tap(find.text(l10n.routeDetailSendToFollower));
      await pumpUntil(
        tester,
        () => _recipient('b').evaluate().isNotEmpty,
        describe: 'the picker',
      );
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(api.publicCalls, 0);
    });

    testWidgets('signed out, the action is not offered', (tester) async {
      final api = _FakeApi(signedIn: false);
      await pumpDetail(tester, api, isPublic: true, isOwner: false);

      await openShareMenu(tester);
      expect(find.text(l10n.routeDetailShareLink), findsOneWidget);
      expect(find.text(l10n.routeDetailSendToFollower), findsNothing);
    });

    testWidgets("someone else's private route offers no send", (tester) async {
      final api = _FakeApi();
      await pumpDetail(tester, api, isPublic: false, isOwner: false);

      await openShareMenu(tester);
      expect(find.text(l10n.routeDetailSendToFollower), findsNothing);
    });
  });
}
