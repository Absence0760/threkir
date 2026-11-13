import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/screens/plan_detail_screen.dart' show PublishClubPicker;
import '../lib/social_service.dart' show ClubView;
import '../lib/widgets/finisher_certificate_card.dart';
import '../lib/widgets/message_actions_sheet.dart';
import '../lib/widgets/park_course_report_sheet.dart';
import '../lib/widgets/plan_details_sheet.dart';
import '../lib/widgets/report_sheet.dart';
import 'three_button_nav_bar.dart';

/// Issue #1374 IK-1: these sheets padded for the keyboard only, so on a phone
/// with 3-button navigation their Save / Submit row drew under the bar. The
/// second group opens one sheet of each kind (a menu, a form with the
/// keyboard up, a share preview, a list) on the narrowest phone at the
/// largest text size, where an overflow fails the test too.
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

  group('each kind of sheet at 320 dp and text scale 2.0', () {
    testWidgets('a menu: the message actions', (tester) async {
      await openSheetOverNavBar(
        tester,
        (context) => showMessageActionsSheet(context,
            mine: true, editable: true, canReact: true),
        size: kNarrowPhone,
        textScale: 2,
      );
      expectAboveNavBar(
          tester, find.byKey(const ValueKey('message-action-unsend')));
    });

    testWidgets('a form with the keyboard up: the content report',
        (tester) async {
      await openSheetOverNavBar(
        tester,
        (context) => showReportSheet(context,
            api: ApiClient(), targetKind: 'user', targetId: 'u1'),
        size: kNarrowPhone,
        textScale: 2,
        keyboard: 300,
      );
      expectAboveNavBar(tester, _button(_l10n.reportSubmit));
    });

    testWidgets('a share preview: the finisher certificate', (tester) async {
      await openSheetOverNavBar(
        tester,
        (context) => showFinisherCertificateSheet(
          context,
          eventTitle: 'Swift Creek 10K',
          finisherName: 'Ada',
          durationS: 2700,
          distanceM: 10000,
          rank: 4,
          date: DateTime(2026, 5, 3),
        ),
        size: kNarrowPhone,
        textScale: 2,
      );
      final share = _button(_l10n.clubEventCertificateShare);
      await tester.ensureVisible(share);
      await tester.pumpAndSettle();
      expectAboveNavBar(tester, share);
    });

    testWidgets('a list: the club picker', (tester) async {
      await openSheetOverNavBar(
        tester,
        (context) => showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => PublishClubPicker(clubs: [
            for (var i = 0; i < 12; i++) _club('c$i', 'Club $i'),
          ]),
        ),
        size: kNarrowPhone,
        textScale: 2,
      );
      expectAboveNavBar(tester, _button(_l10n.planDetailPublishCancel));
    });
  });
}

ClubView _club(String id, String name) => ClubView(
      row: ClubRow(
        shadowHidden: false,
        id: id,
        ownerId: 'owner',
        name: name,
        slug: id,
        joinPolicy: 'open',
        memberCount: 5,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: 5,
      viewerRole: 'admin',
      viewerStatus: 'active',
      joinPolicy: 'open',
    );
