import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/training_service.dart';
import '../lib/widgets/finish_plan_card.dart';

/// Finishing writes through TrainingService; a refusal keeps the card and
/// says so, rather than swallowing the failure.
class _Training extends TrainingService {
  _Training({this.fail = false});
  final bool fail;
  final finished = <String>[];
  @override
  Future<void> finishPlan(String id) async {
    if (fail) throw Exception('offline');
    finished.add(id);
  }
}

Future<void> _pump(WidgetTester tester, _Training training,
    {required void Function() onFinished}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: FinishPlanCard(
        training: training,
        planId: 'p1',
        planName: 'Spring Half',
        endDate: DateTime(2026, 4, 19),
        onFinished: () async => onFinished(),
      ),
    ),
  ));
}

void main() {
  setUpAll(() => initializeDateFormatting());

  test('shows only for an active plan past its end day', () {
    final now = DateTime(2026, 4, 20, 9);
    expect(
        FinishPlanCard.shows(
            status: 'active', endDate: DateTime(2026, 4, 19), now: now),
        isTrue);
    expect(
        FinishPlanCard.shows(
            status: 'active', endDate: DateTime(2026, 4, 20), now: now),
        isFalse);
    expect(
        FinishPlanCard.shows(
            status: 'paused', endDate: DateTime(2026, 4, 19), now: now),
        isFalse);
  });

  testWidgets('Finish plan files the plan and tells the host', (tester) async {
    final training = _Training();
    var told = 0;
    await _pump(tester, training, onFinished: () => told++);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.planFinishTitle('Spring Half')), findsOneWidget);

    await tester.tap(find.byKey(const Key('finishPlanButton')));
    await tester.pump();
    expect(training.finished, ['p1']);
    expect(told, 1);
    expect(find.text(l10n.planFinishDone('Spring Half')), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('a failed finish says so and leaves the button usable',
      (tester) async {
    final training = _Training(fail: true);
    var told = 0;
    await _pump(tester, training, onFinished: () => told++);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    await tester.tap(find.byKey(const Key('finishPlanButton')));
    await tester.pump();
    expect(told, 0);
    expect(find.text(l10n.planFinishFailed), findsOneWidget);
    final button =
        tester.widget<FilledButton>(find.byKey(const Key('finishPlanButton')));
    expect(button.onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 6));
  });
}
