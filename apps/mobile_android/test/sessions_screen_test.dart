import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show ListSkeleton;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gym_store.dart';
import '../lib/screens/session_detail_screen.dart';
import '../lib/screens/sessions_screen.dart';
import '../lib/widgets/official_badge.dart';
import 'worst_case_layout.dart';

SessionPlanRow _plan(String id, String title,
        {String? discipline, int? estMin}) =>
    SessionPlanRow(
      id: id,
      authorId: 'u1',
      title: title,
      discipline: discipline,
      estDurationMin: estMin,
      isPublic: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

SessionPlanItemRow _item(
  String id, {
  required int position,
  required String name,
  String kind = 'hold',
  int? durationS,
  int? reps,
  bool perSide = false,
  String? cue,
}) =>
    SessionPlanItemRow(
      id: id,
      planId: 'p1',
      position: position,
      movementName: name,
      kind: kind,
      durationS: durationS,
      reps: reps,
      perSide: perSide,
      cue: cue,
    );

class _FakeApi extends ApiClient {
  _FakeApi({
    this.plans = const [],
    this.items = const [],
    this.officialIds = const {},
  });

  final List<SessionPlanRow> plans;
  final Set<String> officialIds;
  final List<SessionPlanItemRow> items;

  @override
  Future<List<({SessionPlanRow plan, bool isOfficial})>>
      fetchSessionPlans() async => [
            for (final p in plans) (plan: p, isOfficial: officialIds.contains(p.id)),
          ];

  @override
  Future<({
    SessionPlanRow plan,
    List<SessionPlanBlockRow> blocks,
    List<SessionPlanItemRow> items,
    bool isOfficial,
  })?> fetchSessionPlan(String id) async {
    final p = plans.where((e) => e.id == id).firstOrNull;
    if (p == null) return null;
    return (
      plan: p,
      blocks: const <SessionPlanBlockRow>[],
      items: items,
      isOfficial: false,
    );
  }
}

class _FailingApi extends ApiClient {
  @override
  Future<List<({SessionPlanRow plan, bool isOfficial})>>
      fetchSessionPlans() async {
    throw Exception('network down');
  }
}

class _FailThenSucceedApi extends ApiClient {
  _FailThenSucceedApi(this.plans);

  final List<SessionPlanRow> plans;
  int calls = 0;

  @override
  Future<List<({SessionPlanRow plan, bool isOfficial})>>
      fetchSessionPlans() async {
    calls++;
    if (calls == 1) throw Exception('network down');
    return [for (final p in plans) (plan: p, isOfficial: false)];
  }
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
  testWidgets('empty list renders the self-hiding empty state', (tester) async {
    final dir = Directory.systemTemp.createTempSync('sessions_empty');
    try {
      final gym = await _gymStore(dir);
      await tester.pumpWidget(
          _wrap(SessionsScreen(api: _FakeApi(), gymStore: gym)));
      await tester.pumpAndSettle();
      expect(find.text('No session plans yet.'), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('populated list shows a row with discipline + est duration',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('sessions_list');
    try {
      final gym = await _gymStore(dir);
      final api = _FakeApi(plans: [
        _plan('p1', 'Morning Flow', discipline: 'Vinyasa', estMin: 30),
      ]);
      await tester
          .pumpWidget(_wrap(SessionsScreen(api: api, gymStore: gym)));
      await tester.pumpAndSettle();
      expect(find.text('Morning Flow'), findsOneWidget);
      expect(find.textContaining('Vinyasa'), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('an official plan carries the Official badge; a personal one not',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('sessions_official');
    try {
      final gym = await _gymStore(dir);
      final api = _FakeApi(
        plans: [
          _plan('p1', 'Organiser Flow', discipline: 'Vinyasa'),
          _plan('p2', 'My Flow', discipline: 'Yin'),
        ],
        officialIds: const {'p1'},
      );
      await tester
          .pumpWidget(_wrap(SessionsScreen(api: api, gymStore: gym)));
      await tester.pumpAndSettle();
      final official = find.byType(OfficialBadge);
      expect(official, findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: official, matching: find.byType(ListTile)),
          matching: find.text('Organiser Flow'),
        ),
        findsOneWidget,
      );
      expect(find.text('Official'), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'fetch failure renders the error state instead of a stuck spinner',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('sessions_error');
    try {
      final gym = await _gymStore(dir);
      await tester.pumpWidget(
          _wrap(SessionsScreen(api: _FailingApi(), gymStore: gym)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(ListSkeleton), findsNothing);
      expect(find.text("Couldn't load sessions."), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('tapping retry after a failure re-fetches and shows the list',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('sessions_retry');
    try {
      final gym = await _gymStore(dir);
      final api = _FailThenSucceedApi([_plan('p1', 'Morning Flow')]);
      await tester.pumpWidget(_wrap(SessionsScreen(api: api, gymStore: gym)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Couldn't load sessions."), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("Couldn't load sessions."), findsNothing);
      expect(find.text('Morning Flow'), findsOneWidget);
      expect(api.calls, 2);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('detail expands a per-side hold into Left/Right steps',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('sessions_detail');
    try {
      final gym = await _gymStore(dir);
      final api = _FakeApi(
        plans: [_plan('p1', 'Morning Flow')],
        items: [
          _item('i0', position: 0, name: 'Downward Dog', durationS: 30),
          _item('i1',
              position: 1, name: 'Low Lunge', durationS: 45, perSide: true),
          _item('i2',
              position: 2, name: 'The Hundred', kind: 'reps', reps: 100),
        ],
      );
      await tester.pumpWidget(
        _wrap(SessionDetailScreen(
            api: api, gymStore: gym, planId: 'p1', titleHint: 'Morning Flow')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Low Lunge (Left)'), findsOneWidget);
      expect(find.textContaining('Low Lunge (Right)'), findsOneWidget);
      expect(find.textContaining('100 reps'), findsOneWidget);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  final longPlans = [
    _plan('p1', 'Sunrise vinyasa with a long hip-opening sequence to finish',
        discipline: 'Vinyasa', estMin: 45),
    _plan('p2', 'Reformer core', discipline: 'Reformer Pilates', estMin: 30),
  ];
  final longItems = [
    _item('i0',
        position: 0,
        name: 'Downward-facing dog with a slow pedal',
        durationS: 60,
        cue: 'Press the floor away and lengthen through the spine'),
    _item('i1',
        position: 1, name: 'Low lunge twist', durationS: 45, perSide: true),
    _item('i2', position: 2, name: 'The Hundred', kind: 'reps', reps: 100),
  ];

  worstCaseTestWidgets('the session plan list', (tester, locale) async {
    final dir = Directory.systemTemp.createTempSync('sessions_wc_list');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gym = await tester.runAsync(() => _gymStore(dir));
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: SessionsScreen(
        api: _FakeApi(plans: longPlans, officialIds: const {'p2'}),
        gymStore: gym!,
      ),
    ));
    await tester.pump();
    await tester.pump();
    await walkScrollable(tester, primaryScrollable(), 'Sessions');
  });

  worstCaseTestWidgets('a session plan and its follow-along runner',
      (tester, locale) async {
    final dir = Directory.systemTemp.createTempSync('sessions_wc_detail');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gym = await tester.runAsync(() => _gymStore(dir));
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: SessionDetailScreen(
        api: _FakeApi(plans: longPlans, items: longItems),
        gymStore: gym!,
        planId: 'p1',
        titleHint: longPlans.first.title,
      ),
    ));
    await tester.pump();
    await tester.pump();
    await walkScrollable(tester, primaryScrollable(), 'Session plan');

    // The FAB scales in once the plan has loaded.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expectNoOverflow(tester, 'Session runner');
    // Leave the runner through its close button and discard, so its timer
    // is cancelled before the test ends.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 400));
    expectNoOverflow(tester, 'Session runner, abandon dialog');
  });
}
