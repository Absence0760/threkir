// ignore_for_file: avoid_relative_lib_imports
// Share with coach (issue #1215 Phase 3): the action under an AI Coach answer,
// the sheet that sends picked paragraphs, and the card the thread draws.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/coach_screen.dart';
import '../lib/screens/message_thread_screen.dart';
import '../lib/screens/messages_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/coach_share_card.dart';
import '../lib/widgets/coach_share_sheet.dart';
import 'realtime_drain.dart';
import 'supabase_test_init.dart';

const _me = 'u-viewer';
const _coach = 'coach-1';
const _answer =
    'Keep the long run easy.\n\n'
    'Add strides on Thursday.\n\n'
    'Rest on Friday.';

CoachAthleteLink _link(String userId, String name) => CoachAthleteLink(
  id: 'link-$userId',
  status: 'active',
  note: null,
  createdAt: DateTime.utc(2026, 1, 1),
  acceptedAt: DateTime.utc(2026, 1, 2),
  userId: userId,
  displayName: name,
  avatarUrl: null,
);

class _Api extends ApiClient {
  _Api({
    this.shareEnabled = true,
    List<CoachAthleteLink>? coaches,
    this.coachesError,
  }) : coaches = coaches ?? [_link(_coach, 'Kim')];

  bool shareEnabled;
  List<CoachAthleteLink> coaches;
  Object? coachesError;
  Object? shareError;
  final List<(String, String, List<int>)> shares = [];
  List<DirectMessageRow> thread = [];
  String? planIdForSource = 'plan-7';
  final List<String> sourceReads = [];

  @override
  String? get userId => _me;

  @override
  Future<Map<String, dynamic>?> fetchAiDisclosure() async => const {
    'ai_disclosure_version': 2,
    'coach_consent_at': '2026-01-01T00:00:00Z',
  };

  @override
  Future<List<CoachMessageRow>> fetchCoachMessages({String? planId}) async => [
    CoachMessageRow(
      id: 'cm-1',
      userId: _me,
      role: 'assistant',
      content: _answer,
      createdAt: DateTime.utc(2026, 3, 1, 10),
    ),
  ];

  @override
  Future<List<DateTime>> listCoachArchives({String? planId}) async => [];

  @override
  Future<int> getCoachUsage() async => 0;

  @override
  Future<bool> isPro() async => false;

  @override
  Future<bool> fetchCoachShareEnabled() async => shareEnabled;

  List<DmThread> threads = [];

  @override
  Future<List<DmThread>> fetchDmThreads() async => threads;

  @override
  Future<List<CoachAthleteLink>> fetchMyCoaches() async {
    if (coachesError != null) throw coachesError!;
    return coaches;
  }

  @override
  Future<DirectMessageRow> shareCoachMessage(
    String coachMessageId,
    String coachId,
    List<int> paragraphs,
  ) async {
    shares.add((coachMessageId, coachId, paragraphs));
    if (shareError != null) throw shareError!;
    return _share('dm-new', from: _me, body: 'shared');
  }

  @override
  Future<String?> fetchCoachMessagePlanId(String coachMessageId) async {
    sourceReads.add(coachMessageId);
    return planIdForSource;
  }

  @override
  Future<DmThreadPage> fetchDmThread(
    DmThreadTarget target, {
    DirectMessageRow? before,
    int limit = 50,
  }) async => DmThreadPage(messages: thread, hasMore: false);

  @override
  Future<void> markDmThreadRead(
    String otherId, {
    required DirectMessageRow through,
  }) async {}

  @override
  Future<List<PlanChangeRequestRow>> fetchPlanChangeRequests({
    String? planId,
    String? partnerId,
  }) async => const [];

  @override
  Future<bool> isBlockedByViewer(String userId) async => false;

  @override
  Future<UserProfileRow?> fetchPublicProfile(String userId) async => null;

  @override
  Future<({bool muted, DateTime? archivedAt, bool markedUnread, bool request})?>
  fetchDmConversationState(String conversationId) async => null;
}

DirectMessageRow _share(
  String id, {
  required String from,
  String? body,
  String? coachMessageId = 'cm-1',
  bool unsent = false,
}) => DirectMessageRow(
  kind: 'coach_share',
  isGroup: false,
  id: id,
  conversationId: 'c-1',
  senderId: from,
  recipientId: from == _me ? _coach : _me,
  body: unsent ? null : body,
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
  unsentAt: unsent ? DateTime.utc(2026, 10, 14, 11) : null,
  coachMessageId: from == _me ? coachMessageId : null,
);

DirectMessageRow _assisted(
  String id, {
  required String from,
  String body = 'Easy week, then the long run.',
  bool unsent = false,
}) => DirectMessageRow(
  kind: 'ai_assisted',
  isGroup: false,
  id: id,
  conversationId: 'c-1',
  senderId: from,
  recipientId: from == _me ? _coach : _me,
  body: unsent ? null : body,
  createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
  unsentAt: unsent ? DateTime.utc(2026, 10, 14, 11) : null,
);

late AppLocalizations l10n;

Widget _app(Widget home) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

/// Opens the sheet from a button, so its resolved value can be read.
class _SheetHost extends StatelessWidget {
  const _SheetHost(this.api, this.onResult);
  final _Api api;
  final void Function(CoachAthleteLink?) onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async => onResult(
          await showCoachShareSheet(
            context,
            api: api,
            messageId: 'cm-1',
            content: _answer,
            coaches: api.coaches,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _openSheet(
  WidgetTester tester,
  _Api api, {
  void Function(CoachAthleteLink?)? onResult,
}) async {
  await tester.pumpWidget(_app(_SheetHost(api, onResult ?? (_) {})));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _quote(String text) => find.textContaining(text, findRichText: true);

void main() {
  setUpAll(() async {
    await _ensureSupabase();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('CoachScreen share action', () {
    Future<void> pumpCoach(WidgetTester tester, _Api api) async {
      await tester.pumpWidget(
        _app(CoachScreen(api: api, training: TrainingService())),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }

    final action = find.byKey(const ValueKey('coach-share-action'));

    realtimeWidgetTest(
      'shown on an answer when the gate is on and a coach is linked',
      (tester) async {
        await pumpCoach(tester, _Api());
        expect(action, findsOneWidget);
        expect(find.byTooltip(l10n.coachShareAction), findsOneWidget);
      },
    );

    realtimeWidgetTest('hidden while the gate is off', (tester) async {
      await pumpCoach(tester, _Api(shareEnabled: false));
      expect(find.text('Rest on Friday.', findRichText: true), findsWidgets);
      expect(action, findsNothing);
    });

    realtimeWidgetTest('hidden with no active coach', (tester) async {
      await pumpCoach(tester, _Api(coaches: const []));
      expect(action, findsNothing);
    });

    realtimeWidgetTest('a failed coaches read hides it and keeps the chat', (
      tester,
    ) async {
      await pumpCoach(tester, _Api(coachesError: Exception('offline')));
      expect(action, findsNothing);
      expect(find.byTooltip(l10n.coachActionHelpful), findsOneWidget);
    });

    realtimeWidgetTest('opens the sheet on that answer', (tester) async {
      await pumpCoach(tester, _Api());
      await tester.tap(action);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.coachShareTitle), findsOneWidget);
      expect(find.text(l10n.coachShareTo('Kim')), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
    });
  });

  group('CoachShareSheet', () {
    testWidgets('sends the picked paragraph indexes and says it went', (
      tester,
    ) async {
      final api = _Api();
      CoachAthleteLink? opened;
      await _openSheet(tester, api, onResult: (c) => opened = c);

      expect(find.text(l10n.coachShareTo('Kim')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('coach-share-paragraph-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('coach-share-send')));
      await tester.pumpAndSettle();

      expect(api.shares.single.$1, 'cm-1');
      expect(api.shares.single.$2, _coach);
      expect(api.shares.single.$3, [0, 2]);
      expect(find.text(l10n.coachShareSent('Kim')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('coach-share-open-thread')));
      await tester.pumpAndSettle();
      expect(opened?.userId, _coach);
    });

    testWidgets('with two coaches the picked one gets it', (tester) async {
      final api = _Api(
        coaches: [_link(_coach, 'Kim'), _link('coach-2', 'Lee')],
      );
      await _openSheet(tester, api);

      expect(find.text(l10n.coachShareCoachLegend), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('coach-share-coach-coach-2')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const ValueKey('coach-share-send')),
      );
      await tester.tap(find.byKey(const ValueKey('coach-share-send')));
      await tester.pumpAndSettle();

      expect(api.shares.single.$2, 'coach-2');
      expect(find.text(l10n.coachShareSent('Lee')), findsOneWidget);
    });

    testWidgets('a refusal is said in the sheet and nothing is marked sent', (
      tester,
    ) async {
      final api = _Api()..shareError = const DmSendNotPermitted();
      await _openSheet(tester, api);

      await tester.tap(find.byKey(const ValueKey('coach-share-send')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.messagesSendNotAllowed), findsOneWidget);
      expect(find.byKey(const ValueKey('coach-share-sent')), findsNothing);
    });

    testWidgets('the gate closing under it reads as unavailable', (
      tester,
    ) async {
      final api = _Api()..shareError = const CoachShareUnavailable();
      await _openSheet(tester, api);

      await tester.tap(find.byKey(const ValueKey('coach-share-send')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.coachShareUnavailable), findsOneWidget);
    });

    testWidgets('nothing picked cannot be sent', (tester) async {
      final api = _Api();
      await _openSheet(tester, api);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(ValueKey('coach-share-paragraph-$i')));
        await tester.pump();
      }
      final send = tester.widget<FilledButton>(
        find.byKey(const ValueKey('coach-share-send')),
      );
      expect(send.onPressed, isNull);
    });

    testWidgets('an excerpt over the cap is refused before the wire', (
      tester,
    ) async {
      final api = _Api();
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CoachShareSheet(
              api: api,
              messageId: 'cm-1',
              content: 'a' * 4001,
              coaches: api.coaches,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('coach-share-too-long')),
        findsOneWidget,
      );
      final send = tester.widget<FilledButton>(
        find.byKey(const ValueKey('coach-share-send')),
      );
      expect(send.onPressed, isNull);
    });
  });

  group('MessageThreadScreen coach_share', () {
    Future<void> pumpThread(
      WidgetTester tester,
      _Api api, {
      void Function(BuildContext, String?)? onOpenCoachSource,
    }) async {
      await tester.pumpWidget(
        _app(
          MessageThreadScreen(
            api: api,
            partnerId: _coach,
            partnerName: 'Kim',
            pollInterval: const Duration(hours: 1),
            onOpenCoachSource: onOpenCoachSource,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('draws the card with the AI tag and the quote, as the sender', (
      tester,
    ) async {
      final api = _Api()
        ..thread = [_share('dm-1', from: _me, body: 'Keep the long run easy.')];
      String? openedPlan;
      await pumpThread(
        tester,
        api,
        onOpenCoachSource: (_, planId) => openedPlan = planId,
      );

      expect(find.byKey(const ValueKey('dm-coach-share')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-tag')), findsOneWidget);
      expect(find.text(l10n.coachShareCardLabel), findsOneWidget);
      expect(find.text(l10n.coachShareCardFromMe), findsOneWidget);
      expect(_quote('Keep the long run easy.'), findsOneWidget);

      final source = find.byKey(const ValueKey('dm-coach-share-source'));
      expect(source, findsOneWidget);
      await tester.tap(source);
      await tester.pump();
      expect(api.sourceReads, ['cm-1']);
      expect(openedPlan, 'plan-7');
    });

    testWidgets('the coach sees who shared it and no link back', (
      tester,
    ) async {
      final api = _Api()
        ..thread = [_share('dm-1', from: _coach, body: 'Rest on Friday.')];
      await pumpThread(tester, api);

      expect(find.byKey(const ValueKey('ai-tag')), findsOneWidget);
      expect(find.text(l10n.coachShareCardFromAthlete('Kim')), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-coach-share-source')), findsNothing);
    });

    testWidgets('a shared answer offers no Edit, only Unsend', (tester) async {
      final api = _Api()
        ..thread = [_share('dm-1', from: _me, body: 'Rest on Friday.')];
      await pumpThread(tester, api);

      await tester.longPress(find.text(l10n.coachShareCardLabel));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('message-action-edit')), findsNothing);
      expect(
        find.byKey(const ValueKey('message-action-unsend')),
        findsOneWidget,
      );
    });

    testWidgets('an unsent share keeps the placeholder and no card', (
      tester,
    ) async {
      final api = _Api()..thread = [_share('dm-1', from: _me, unsent: true)];
      await pumpThread(tester, api);

      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-coach-share')), findsNothing);
    });

    testWidgets('markup in the quote stays text: no link, no markdown widget', (
      tester,
    ) async {
      const body =
          '**Bold** and [tap me](https://evil.example) '
          '<img src=x onerror=alert(1)> `code`';
      final api = _Api()..thread = [_share('dm-1', from: _coach, body: body)];
      await pumpThread(tester, api);

      final card = find.byKey(const ValueKey('dm-coach-share'));
      expect(
        find.descendant(of: card, matching: find.byType(MarkdownBody)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(Image)),
        findsNothing,
      );
      final quote = tester.widget<RichText>(
        find.descendant(
          of: find.byType(SharedText),
          matching: find.byType(RichText),
        ),
      );
      final plain = quote.text.toPlainText();
      expect(plain, 'Bold and tap me <img src=x onerror=alert(1)> code');
      expect(plain, isNot(contains('https://evil.example')));
      var recognizers = 0;
      quote.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          recognizers++;
        }
        return true;
      });
      expect(recognizers, 0);
    });
  });

  group('MessageThreadScreen ai_assisted', () {
    Future<void> pumpThread(WidgetTester tester, _Api api) async {
      await tester.pumpWidget(
        _app(
          MessageThreadScreen(
            api: api,
            partnerId: _coach,
            partnerName: 'Kim',
            pollInterval: const Duration(hours: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    for (final from in [_me, _coach]) {
      testWidgets(
        'marks the message AI-assisted for ${from == _me ? 'the sender' : 'the recipient'}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final api = _Api()..thread = [_assisted('dm-1', from: from)];
          await pumpThread(tester, api);

          expect(find.text('Easy week, then the long run.'), findsOneWidget);
          final marker = find.byKey(const ValueKey('dm-ai-assisted'));
          expect(marker, findsOneWidget);
          expect(
            find.descendant(
              of: marker,
              matching: find.text(l10n.coachAssistMarker),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: marker,
              matching: find.byIcon(Icons.auto_awesome),
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<Semantics>(marker).properties.label,
            l10n.coachAssistMarkerTitle,
          );
          final announced = tester.getSemantics(marker).label;
          expect(announced, contains(l10n.coachAssistMarkerTitle));
          expect(announced, isNot(contains('\n${l10n.coachAssistMarker}')));
          semantics.dispose();
        },
      );
    }

    testWidgets('an unsent AI-assisted message shows no marker', (
      tester,
    ) async {
      final api = _Api()..thread = [_assisted('dm-1', from: _me, unsent: true)];
      await pumpThread(tester, api);

      expect(find.text(l10n.messagesUnsentPlaceholder), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-ai-assisted')), findsNothing);
    });

    testWidgets('a plain text or shared message shows no marker', (
      tester,
    ) async {
      final api = _Api()
        ..thread = [_share('dm-1', from: _me, body: 'Rest on Friday.')];
      await pumpThread(tester, api);

      expect(find.byKey(const ValueKey('dm-coach-share')), findsOneWidget);
      expect(find.byKey(const ValueKey('dm-ai-assisted')), findsNothing);
    });
  });

  group('MessagesScreen inbox preview', () {
    DmThread inboxRow(String id, {String kind = 'text', bool unsent = false}) =>
        DmThread(
          conversationId: 'c-$id',
          partnerId: id,
          partnerName: 'Name $id',
          lastBody: unsent ? null : 'last from $id',
          lastUnsent: unsent,
          lastKind: kind,
          lastAt: DateTime.utc(2026, 10, 14, 8),
          lastFromMe: true,
          unread: 0,
        );

    testWidgets(
      'a shared Coach answer carries the AI tag; text and unsent do not',
      (tester) async {
        final api = _Api()
          ..threads = [
            inboxRow('p-1', kind: 'coach_share'),
            inboxRow('p-2'),
            inboxRow('p-3', kind: 'coach_share', unsent: true),
          ];
        await tester.pumpWidget(
          _app(
            MessagesScreen(api: api, pollInterval: const Duration(hours: 1)),
          ),
        );
        await tester.pump();
        await tester.pump();

        final shared = find.byKey(const ValueKey('dm-coach-share-preview-p-1'));
        expect(shared, findsOneWidget);
        expect(
          find.descendant(
            of: shared,
            matching: find.byKey(const ValueKey('ai-tag')),
          ),
          findsOneWidget,
        );
        expect(
          find.text(l10n.messagesYouPrefixed('last from p-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('dm-coach-share-preview-p-2')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('dm-coach-share-preview-p-3')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('ai-tag')), findsOneWidget);
      },
    );
  });
}
