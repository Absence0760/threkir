// ignore_for_file: avoid_relative_lib_imports
// The suggested-plan-change card on mobile (issue #1215 Phase 2, decisions
// § 2382): the coach approves the ticked lines or declines with a note; the
// athlete withdraws (after confirming) or applies it themselves. Mirrors the
// web Playwright spec plans/plan-change-request.spec.ts.
import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/plan_change_requests.dart';
import 'pump_until.dart';

const _coach = 'coach-1';
const _athlete = 'athlete-1';

PlanChangeRequestRow _request({
  String status = 'pending',
  String? note,
  bool edited = false,
}) =>
    PlanChangeRequestRow(
      id: 'req-1',
      planId: 'plan-1',
      athleteId: _athlete,
      coachId: _coach,
      status: status,
      includeFollowing: false,
      workouts: const [
        {'id': 'w-easy', 'scheduled_date': '2027-11-17'},
        {'id': 'w-tempo', 'target_distance_m': 7000},
      ],
      weeks: const [],
      editedByCoach: edited,
      coachNote: note,
      createdAt: DateTime.utc(2027, 11, 15),
      decidedAt: status == 'pending' ? null : DateTime.utc(2027, 11, 15, 9),
    );

class _FakeApi extends ApiClient {
  _FakeApi(this.viewer, this.requests);

  final String viewer;
  List<PlanChangeRequestRow> requests;
  Object? loadError;
  int loads = 0;
  final List<Map<String, Object?>> decisions = [];
  final List<String> withdrawn = [];
  final List<String> appliedMyself = [];

  @override
  String? get userId => viewer;

  @override
  Future<List<PlanChangeRequestRow>> fetchPlanChangeRequests({
    String? planId,
    String? partnerId,
  }) async {
    loads++;
    final e = loadError;
    if (e != null) throw e;
    return requests;
  }

  @override
  Future<({List<Map<String, dynamic>> workouts, List<Map<String, dynamic>> weeks})>
      fetchPlanChangeTargets(List<String> workoutIds, List<String> weekIds) async => (
            workouts: [
              {
                'id': 'w-easy',
                'scheduled_date': '2027-11-16',
                'kind': 'easy',
                'target_distance_m': 8000,
                'target_duration_seconds': null,
                'skipped_at': null,
              },
              {
                'id': 'w-tempo',
                'scheduled_date': '2027-11-18',
                'kind': 'tempo',
                'target_distance_m': 8000,
                'target_duration_seconds': null,
                'skipped_at': null,
              },
            ],
            weeks: const <Map<String, dynamic>>[],
          );

  @override
  Future<void> decidePlanChange({
    required String requestId,
    required bool approve,
    required String todayIso,
    List<String>? workoutIds,
    List<String>? weekIds,
    String? note,
  }) async {
    decisions.add({
      'id': requestId,
      'approve': approve,
      'today': todayIso,
      'workouts': workoutIds,
      'weeks': weekIds,
      'note': note,
    });
    requests = [_request(status: approve ? 'approved' : 'declined', note: note)];
  }

  @override
  Future<void> withdrawPlanChange(String requestId) async {
    withdrawn.add(requestId);
    requests = [_request(status: 'withdrawn')];
  }

  @override
  Future<void> applyPlanChangeMyself(String requestId, String todayIso) async {
    appliedMyself.add('$requestId@$todayIso');
    requests = [_request(status: 'overridden')];
  }
}

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: PlanChangeRequestsSection(
          api: api,
          partnerId: api.viewer == _coach ? _athlete : _coach,
          now: () => DateTime(2027, 11, 15, 10),
        ),
      ),
    ),
  ));
  await pumpUntil(tester, () => find.byKey(const Key('plan-change-request')).evaluate().isNotEmpty ||
      find.byKey(const Key('plan-change-load-failed')).evaluate().isNotEmpty, describe: 'the card to settle');
}

Future<void> _settleBanner(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
}

void main() {
  testWidgets('the coach approves only the lines left ticked', (tester) async {
    final api = _FakeApi(_coach, [_request()]);
    await _pump(tester, api);

    expect(find.text('Your athlete is waiting for your answer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan-change-line-w-tempo')));
    await tester.pump();
    expect(find.text('Approve selected'), findsOneWidget);
    await tester.tap(find.byKey(const Key('plan-change-approve')));
    await pumpUntil(tester, () => find.text('Approved by the coach and applied').evaluate().isNotEmpty, describe: 'the card to settle');

    expect(api.decisions, [
      {
        'id': 'req-1',
        'approve': true,
        'today': '2027-11-15',
        'workouts': ['w-easy'],
        'weeks': <String>[],
        'note': '',
      },
    ]);
    expect(find.byKey(const Key('plan-change-approve')), findsNothing);
    await _settleBanner(tester);
  });

  testWidgets('the coach declines with a note, and the decided card shows it', (tester) async {
    final api = _FakeApi(_coach, [_request()]);
    await _pump(tester, api);

    await tester.enterText(find.byKey(const Key('plan-change-note-input')), 'Keep the tempo.');
    await tester.tap(find.byKey(const Key('plan-change-decline')));
    await pumpUntil(tester, () => find.text('Declined by the coach').evaluate().isNotEmpty, describe: 'the card to settle');

    expect(api.decisions.single['approve'], false);
    expect(api.decisions.single['note'], 'Keep the tempo.');
    expect(api.decisions.single['workouts'], isNull);
    expect(find.text("Coach's note: Keep the tempo."), findsOneWidget);
    await _settleBanner(tester);
  });

  testWidgets('unticking every line leaves nothing to approve', (tester) async {
    final api = _FakeApi(_coach, [_request()]);
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('plan-change-line-w-easy')));
    await tester.tap(find.byKey(const Key('plan-change-line-w-tempo')));
    await tester.pump();
    final approve = tester.widget<FilledButton>(find.byKey(const Key('plan-change-approve')));
    expect(approve.onPressed, isNull);
  });

  testWidgets('the athlete withdraws only after confirming', (tester) async {
    final api = _FakeApi(_athlete, [_request()]);
    await _pump(tester, api);

    expect(find.text('Waiting for your coach to answer'), findsOneWidget);
    expect(find.byKey(const Key('plan-change-line-w-easy')), findsNothing);
    await tester.tap(find.byKey(const Key('plan-change-withdraw')));
    await tester.pump();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(find.descendant(of: dialog, matching: find.text('Keep it')));
    await tester.pump();
    expect(api.withdrawn, isEmpty);

    await tester.tap(find.byKey(const Key('plan-change-withdraw')));
    await tester.pump();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Withdraw'),
    ));
    await pumpUntil(tester, () => find.text('Withdrawn by the athlete').evaluate().isNotEmpty, describe: 'the card to settle');
    expect(api.withdrawn, ['req-1']);
    await _settleBanner(tester);
  });

  testWidgets('the athlete applies it themselves', (tester) async {
    final api = _FakeApi(_athlete, [_request()]);
    await _pump(tester, api);

    await tester.tap(find.byKey(const Key('plan-change-apply-myself')));
    await pumpUntil(tester, () => find.text('Applied by the athlete without the coach').evaluate().isNotEmpty, describe: 'the card to settle');
    expect(api.appliedMyself, ['req-1@2027-11-15']);
    await _settleBanner(tester);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final api = _FakeApi(_athlete, [_request()])..loadError = Exception('offline');
    await _pump(tester, api);

    expect(find.byKey(const Key('plan-change-load-failed')), findsOneWidget);
    api.loadError = null;
    await tester.tap(find.text('Try again'));
    await pumpUntil(tester, () => find.byKey(const Key('plan-change-request')).evaluate().isNotEmpty, describe: 'the card to settle');
    expect(api.loads, 2);
  });

  testWidgets('no requests renders nothing', (tester) async {
    final api = _FakeApi(_athlete, const []);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PlanChangeRequestsSection(api: api, planId: 'plan-1')),
    ));
    await pumpUntil(tester, () => api.loads > 0, describe: 'the card to settle');
    await tester.pump();
    expect(find.byKey(const Key('plan-change-request')), findsNothing);
    expect(find.byKey(const Key('plan-change-load-failed')), findsNothing);
  });
}
