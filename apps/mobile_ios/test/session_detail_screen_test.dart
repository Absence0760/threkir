import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton, PageHeading;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/session_detail_screen.dart';

class _ThrowingFakeApi extends ApiClient {
  int calls = 0;

  @override
  String? get userId => 'me';

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
    bool isOfficial,
  })?> fetchSessionPlan(String id) async {
    calls++;
    throw Exception('network blip');
  }
}

class _NotFoundFakeApi extends ApiClient {
  @override
  String? get userId => 'me';

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
    bool isOfficial,
  })?> fetchSessionPlan(String id) async => null;
}

/// Never resolves, so the loading frame is observable.
class _HangingFakeApi extends ApiClient {
  @override
  String? get userId => 'me';

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
    bool isOfficial,
  })?> fetchSessionPlan(String id) => Completer<
      ({
        SessionPlanRow plan,
        List<SessionPlanBlockRow> blocks,
        List<SessionPlanItemRow> items,
        bool isOfficial,
      })?>().future;
}

const _longTitle =
    'Séance de mobilité du matin pour les hanches et le dos du club';

/// One reps step, so the runner waits on Done and starts no ticker.
class _PlanFakeApi extends ApiClient {
  @override
  String? get userId => 'me';

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
    bool isOfficial,
  })?> fetchSessionPlan(String id) async => (
        plan: SessionPlanRow(
          id: id,
          authorId: 'me',
          title: _longTitle,
          isPublic: false,
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
        blocks: const <SessionPlanBlockRow>[],
        items: [
          SessionPlanItemRow(
            id: 'i0',
            planId: id,
            position: 0,
            movementName: 'Cat-Cow',
            kind: 'reps',
            reps: 10,
            perSide: false,
            cue: 'Move with the breath, slowly and evenly',
          ),
        ],
        isOfficial: false,
      );
}

Widget _scaled(Widget child, double scale) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: child,
    );

/// Opens the follow-along runner from the plan's detail page.
Future<void> _openRunner(WidgetTester tester, LocalGymStore gym,
    {double scale = 1}) async {
  await tester.pumpWidget(_scaled(
      SessionDetailScreen(api: _PlanFakeApi(), gymStore: gym, planId: 'p1'),
      scale));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Start session'));
  await tester.pumpAndSettle();
  expect(find.text('Cat-Cow'), findsOneWidget);
}

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<LocalGymStore> _gymStore(Directory dir) async {
  final store = LocalGymStore();
  await store.init(overrideDirectory: dir);
  return store;
}

void main() {
  testWidgets('the loading frame stands step rows, not a bare spinner',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_loading');
    try {
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: _HangingFakeApi(),
          gymStore: gym,
          planId: 'p1',
          titleHint: 'Morning Flow')));
      await tester.pump();

      expect(find.byType(ListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'a fetch failure shows the error state with retry instead of a stuck spinner',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_error');
    try {
      final api = _ThrowingFakeApi();
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')));

      // The fake rejects on its first microtask, so the error frame is
      // already up by the first pump — there is no observable mid-fetch
      // spinner to assert on here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text("Couldn't load this session plan."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Session plan not found.'), findsNothing);

      // Retry must re-invoke the fetch; the fake keeps throwing, so prove
      // the refetch by call count rather than a transient spinner frame.
      expect(api.calls, 1);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.calls, 2);
      expect(find.text("Couldn't load this session plan."), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('a null (not-found) result stays distinct from the error state',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('session_detail_notfound');
    try {
      final api = _NotFoundFakeApi();
      final gym = await _gymStore(dir);
      await tester.pumpWidget(_wrap(SessionDetailScreen(
          api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Session plan not found.'), findsOneWidget);
      expect(find.text("Couldn't load this session plan."), findsNothing);
      expect(find.text('Retry'), findsNothing);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('follow-along runner', () {
    late Directory dir;
    late LocalGymStore gym;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('session_runner');
      gym = await _gymStore(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    testWidgets('the close button asks before abandoning', (tester) async {
      await _openRunner(tester, gym);
      expect(find.byType(BackButton), findsNothing);

      await tester.tap(find.byTooltip('Abandon'));
      await tester.pumpAndSettle();
      expect(find.text('Discard session?'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Cat-Cow'), findsOneWidget,
          reason: 'Resume keeps the session running');

      await tester.tap(find.byTooltip('Abandon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Cat-Cow'), findsNothing);
      expect(find.text('Start session'), findsOneWidget,
          reason: 'back on the plan page');
      expect(gym.workouts, isEmpty, reason: 'a discarded run is not logged');
    });

    testWidgets('the system back asks too', (tester) async {
      await _openRunner(tester, gym);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard session?'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.text('Cat-Cow'), findsOneWidget);
    });

    testWidgets('the runner controls clear a 48 dp navigation bar',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.reset);
      await _openRunner(tester, gym);

      final abandon = find.widgetWithText(TextButton, 'Abandon');
      await tester.ensureVisible(abandon);
      await tester.pumpAndSettle();
      for (final control in [
        find.widgetWithText(FilledButton, 'Done'),
        find.widgetWithText(OutlinedButton, 'Skip'),
        abandon,
      ]) {
        expect(tester.getRect(control).bottom, lessThanOrEqualTo(640 - 48),
            reason: '$control sits under the navigation bar');
      }
    });

    testWidgets('the title is not cut at 2x text on a 320 dp phone',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openRunner(tester, gym, scale: 2);
      expect(tester.takeException(), isNull);

      final heading = find.descendant(
          of: find.byType(PageHeading), matching: find.text(_longTitle));
      expect(heading, findsOneWidget);
      expect(tester.renderObject<RenderParagraph>(heading).didExceedMaxLines,
          isFalse);
      final abandon = find.widgetWithText(TextButton, 'Abandon');
      await tester.ensureVisible(abandon);
      await tester.pumpAndSettle();
      expect(tester.getRect(abandon).bottom, lessThanOrEqualTo(640));
    });
  });
}
