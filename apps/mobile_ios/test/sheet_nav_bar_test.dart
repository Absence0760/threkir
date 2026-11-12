import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/widgets/park_course_report_sheet.dart';
import '../lib/widgets/plan_details_sheet.dart';
import '../lib/widgets/report_sheet.dart';
import 'three_button_nav_bar.dart';

/// Issue #1374 IK-1: these sheets padded for the keyboard only, so on a phone
/// with 3-button navigation their Save / Submit row drew under the bar.
final _l10n = AppLocalizationsEn();

Finder _button(String label) => find
    .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
    .first;

final _plan = TrainingPlanRow(
  id: 'plan-1',
  userId: 'user-a',
  name: 'Spring Half',
  goalEvent: 'distance_half',
  goalDistanceM: 21097.5,
  startDate: DateTime(2026, 3, 9),
  endDate: DateTime(2026, 3, 22),
  daysPerWeek: 4,
  status: 'active',
  source: 'generated',
  rules: const [],
  isTemplate: false,
  isPublicTemplate: false,
);

void main() {
  testWidgets('the content report sheet', (tester) async {
    await openSheetOverNavBar(
      tester,
      (context) => showReportSheet(context,
          api: ApiClient(), targetKind: 'user', targetId: 'u1'),
    );
    expectAboveNavBar(tester, _button(_l10n.reportSubmit));
  });

  testWidgets('the park course report sheet', (tester) async {
    await openSheetOverNavBar(
      tester,
      (context) => showParkCourseReportSheet(context,
          api: ApiClient(), courseId: 'c1', courseName: 'Swift Creek'),
    );
    expectAboveNavBar(
        tester, find.byKey(const Key('park-course-report-submit')));
  });

  testWidgets('the plan details sheet', (tester) async {
    await openSheetOverNavBar(
        tester, (context) => showPlanDetailsSheet(context, _plan));
    expectAboveNavBar(tester, find.byKey(const Key('planDetailsSave')));
  });
}
