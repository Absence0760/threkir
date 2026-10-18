import 'dart:async';

import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show EmptyState, ListSkeleton;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/plan_library_screen.dart';
import '../lib/training_service.dart';
import '../lib/widgets/sign_in_required_state.dart';

TrainingPlanRow _plan(String id, String name) => TrainingPlanRow(
      id: id,
      userId: 'author-1',
      name: name,
      goalEvent: 'distance_full',
      goalDistanceM: 42195,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 8, 23),
      daysPerWeek: 5,
      status: 'completed',
      source: 'manual',
      isTemplate: true,
      isPublicTemplate: true,
    );

class _FakeTraining extends TrainingService {
  /// The library gates on the viewer id (an anon read of the template
  /// policy returns 0 rows, which used to render a false empty state),
  /// so a fake must declare who is looking.
  @override
  String? get currentUserId => 'u-viewer';

  String? clonedTemplateId;
  String lastQuery = '';

  @override
  Future<List<PublicPlanLibraryEntry>> fetchPublicPlanLibrary({
    String query = '',
  }) async {
    lastQuery = query;
    final all = [
      PublicPlanLibraryEntry(
        plan: _plan('tmpl-1', 'Sub-4 Marathon'),
        authorHandle: 'Coach Dana',
      ),
      PublicPlanLibraryEntry(
        plan: _plan('tmpl-2', 'Beginner Half'),
        authorHandle: null,
      ),
    ];
    if (query.trim().isEmpty) return all;
    return all
        .where((e) => e.plan.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  PlanOverlapAction? clonedOverlap;

  @override
  Future<List<TrainingPlanRow>> fetchActivePlans() async => const [];

  @override
  Future<String> clonePublicPlan({
    required String templateId,
    DateTime? startDate,
    PlanOverlapAction onOverlap = PlanOverlapAction.refuse,
  }) async {
    clonedTemplateId = templateId;
    clonedOverlap = onOverlap;
    return 'cloned-plan-id';
  }

  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async =>
          (plan: null, weeks: const <PlanWeekRow>[], workouts: const <PlanWorkoutRow>[]);
}

/// Answers each search only when the test completes its completer, so the
/// order answers land in is the test's to choose.
class _GatedTraining extends _FakeTraining {
  final bool signedIn;
  final Map<String, Completer<List<PublicPlanLibraryEntry>>> pending = {};
  int calls = 0;

  _GatedTraining({this.signedIn = true});

  @override
  String? get currentUserId => signedIn ? 'u-viewer' : null;

  @override
  Future<List<PublicPlanLibraryEntry>> fetchPublicPlanLibrary({
    String query = '',
  }) {
    calls++;
    lastQuery = query;
    return (pending[query] = Completer<List<PublicPlanLibraryEntry>>()).future;
  }
}

PublicPlanLibraryEntry _entry(String id, String name) =>
    PublicPlanLibraryEntry(plan: _plan(id, name), authorHandle: 'Coach Dana');

class _PreviewTraining extends _FakeTraining {
  @override
  Future<({TrainingPlanRow? plan, List<PlanWeekRow> weeks, List<PlanWorkoutRow> workouts})>
      fetchPlan(String id) async {
    PlanWorkoutRow w(String id, String kind, double? m) => PlanWorkoutRow(
          id: id,
          weekId: 'wk-0',
          scheduledDate: DateTime(2026, 6, 1),
          kind: kind,
          targetDistanceM: m,
          manuallyCompleted: false,
        );
    return (
      plan: null,
      weeks: const [
        PlanWeekRow(id: 'wk-0', planId: 'tmpl-1', weekIndex: 0, phase: 'base'),
      ],
      workouts: [
        w('a', 'easy', 5000),
        w('b', 'rest', null),
        w('c', 'long', 12000),
        w('d', 'rest', null),
      ],
    );
  }
}

Widget _host(TrainingService t) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlanLibraryScreen(training: t),
    );

void main() {
  testWidgets('library lists public plans with author handle + anonymous fallback',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    expect(find.text('Sub-4 Marathon'), findsOneWidget);
    expect(find.text('Beginner Half'), findsOneWidget);
    // Named author shown; the null-handle plan falls back to anonymous.
    expect(find.text('by Coach Dana'), findsOneWidget);
    expect(find.text('by a runner'), findsOneWidget);
  });

  testWidgets('search filters the list', (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'beginner');
    // Debounced 300ms.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(t.lastQuery, 'beginner');
    expect(find.text('Beginner Half'), findsOneWidget);
    expect(find.text('Sub-4 Marathon'), findsNothing);
  });

  testWidgets('tapping a plan opens preview and clone invokes clonePublicPlan',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sub-4 Marathon'));
    await tester.pumpAndSettle();

    // Preview screen shows the clone CTA.
    final cloneBtn = find.widgetWithText(FilledButton, 'Clone into my plans');
    expect(cloneBtn, findsOneWidget);

    await tester.tap(cloneBtn);
    await tester.pump();

    expect(t.clonedTemplateId, 'tmpl-1');
    // Nothing overlapped when the dialog looked, so the server is asked to
    // refuse rather than replace a plan created since (decisions § 2050).
    expect(t.clonedOverlap, PlanOverlapAction.refuse);
  });

  testWidgets('a card states its goal and length in the shared plan-facts string',
      (tester) async {
    await tester.pumpWidget(_host(_FakeTraining()));
    await tester.pumpAndSettle();

    expect(find.text('Marathon'), findsNWidgets(2));
    expect(find.text('12 weeks · 5 days/week'), findsNWidgets(2));
  });

  testWidgets('a search keeps the current results instead of a skeleton',
      (tester) async {
    final t = _GatedTraining();
    await tester.pumpWidget(_host(t));
    t.pending['']!.complete([_entry('tmpl-1', 'Sub-4 Marathon')]);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sub');
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ListSkeleton), findsNothing);
    expect(find.text('Sub-4 Marathon'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    t.pending['sub']!.complete([_entry('tmpl-1', 'Sub-4 Marathon')]);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a slow earlier search cannot overwrite a newer answer',
      (tester) async {
    final t = _GatedTraining();
    await tester.pumpWidget(_host(t));
    t.pending['']!.complete(const []);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'half');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'marathon');
    await tester.pump(const Duration(milliseconds: 350));

    t.pending['marathon']!.complete([_entry('tmpl-1', 'Sub-4 Marathon')]);
    await tester.pumpAndSettle();
    t.pending['half']!.complete([_entry('tmpl-2', 'Beginner Half')]);
    await tester.pumpAndSettle();

    expect(find.text('Sub-4 Marathon'), findsOneWidget);
    expect(find.text('Beginner Half'), findsNothing);
  });

  testWidgets('the clear button empties the search and reloads everything',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('planLibraryClearSearch')), findsNothing);

    await tester.enterText(find.byType(TextField), 'beginner');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Sub-4 Marathon'), findsNothing);

    await tester.tap(find.byKey(const Key('planLibraryClearSearch')));
    await tester.pumpAndSettle();

    expect(t.lastQuery, '');
    expect(find.text('Sub-4 Marathon'), findsOneWidget);
    expect(find.byKey(const Key('planLibraryClearSearch')), findsNothing);
  });

  testWidgets('signed out shows the sign-in state with no search field',
      (tester) async {
    final t = _GatedTraining(signedIn: false);
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    expect(find.byType(SignInRequiredState), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(t.calls, 0);
  });

  testWidgets('a search with no match uses the shared empty state',
      (tester) async {
    final t = _FakeTraining();
    await tester.pumpWidget(_host(t));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
  });

  testWidgets('the preview lists each week with its runs and distance, skipping rest days',
      (tester) async {
    await tester.pumpWidget(_host(_PreviewTraining()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sub-4 Marathon'));
    await tester.pumpAndSettle();

    expect(find.text('Week 1'), findsOneWidget);
    expect(find.text('2 runs · 17.00 km'), findsOneWidget);
    expect(find.text('1 week · 5 days/week'), findsOneWidget);
  });
}
