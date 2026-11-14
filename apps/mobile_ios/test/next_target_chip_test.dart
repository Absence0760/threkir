// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/next_target_chip.dart';
import 'worst_case_layout.dart';

/// Issue #1374 TO-4: the gym "Next target" chip overflowed a 320 dp card in
/// English at 1.0x. It wraps as one paragraph inside the card now, at the
/// worst case in every locale, with the longest reasons the catalogue has.
void main() {
  worstCaseTestWidgets('The gym next-target chips', (tester, locale) async {
    final l10n = l10nFor(locale);
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final (exercise, delta, reason, deload) in [
                ('Barbell back squat', null, l10n.gymRoutineNextTargetEstablishBaseline, false),
                ('Romanian deadlift', '+2.5 kg', l10n.gymRoutineNextTargetIncreaseWeight, false),
                ('Bulgarian split squat', '+1', l10n.gymRoutineNextTargetIncreaseReps, false),
                ('Overhead press', '-10%', l10n.gymRoutineNextTargetDeload, true),
              ])
                NextTargetChip(
                  exercise: exercise,
                  delta: delta,
                  reason: reason,
                  deload: deload,
                ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    for (final chip in find.byType(NextTargetChip).evaluate()) {
      final r = tester.getRect(find.byWidget(chip.widget));
      expect(r.right, lessThanOrEqualTo(kWorstCasePhone.width - 16 + 0.5),
          reason: 'a chip runs past the card');
    }
  });
}
