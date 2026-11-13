// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/race_service.dart';
import '../lib/widgets/course_alerts_section.dart';
import 'worst_case_layout.dart';

class _AlertsService extends RaceService {
  _AlertsService(this.alerts);

  final List<CourseAlertView> alerts;

  @override
  bool get isSignedIn => true;

  @override
  bool get isReady => true;

  @override
  Future<List<CourseAlertView>> fetchCourseAlerts(
          {String? listingId, String? routeId, int limit = 20}) async =>
      alerts;

  @override
  Future<List<OrganiserClub>> fetchMyOrganiserClubs() async =>
      const [OrganiserClub(id: 'club-1', name: 'Moab Trail Club')];
}

void main() {
  worstCaseTestWidgets('the course alert cards', (tester, locale) async {
    final service = _AlertsService(const [
      CourseAlertView(
        id: 'alert-0',
        clubId: 'club-1',
        listingId: 'listing-1',
        routeId: null,
        kind: 'closure',
        message: 'The river path is closed between mile 4 and the bridge; '
            'follow the marshals onto the road.',
        createdAt: '2036-10-01T09:00:00Z',
      ),
    ]);
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CourseAlertsSection(
              service: service,
              listingId: 'listing-1',
              clubId: 'club-1',
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('course-alert-alert-0')), findsOneWidget);
    expect(find.byKey(const Key('course-alert-remove-alert-0')), findsOneWidget);
    await walkScrollable(tester, primaryScrollable(), 'Course alerts');
  });
}
