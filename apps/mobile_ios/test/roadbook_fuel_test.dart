import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/roadbook_screen.dart';

Route _route() {
  final wps = <Waypoint>[];
  for (var i = 0; i <= 18; i++) {
    wps.add(Waypoint(
      lat: 51.5 + i * 0.001,
      lng: -0.12,
      elevationMetres: i > 9 ? (i - 9) * 30.0 : 0.0,
    ));
  }
  return Route(
    id: 'route-1',
    name: 'Test Course',
    waypoints: wps,
    distanceMetres: 2000,
  );
}

RouteMarkerRow _marker(String kind, String label, double pos,
    Map<String, dynamic> meta) {
  return RouteMarkerRow(
    id: '$kind-$label',
    routeId: 'route-1',
    userId: 'owner',
    kind: kind,
    label: label,
    lat: 51.5,
    lng: -0.12,
    positionM: pos,
    meta: meta,
    createdAt: DateTime.parse('2026-01-01T00:00:00Z'),
    updatedAt: DateTime.parse('2026-01-01T00:00:00Z'),
  );
}

class _WeightApi extends ApiClient {
  final DateTime? consentAt;
  final double? weightKg;
  _WeightApi({this.consentAt, this.weightKg});

  @override
  String? get userId => 'owner';

  @override
  Future<UserProfileRow?> fetchMyProfile() async => UserProfileRow(profilePrivate: false, 
        id: 'owner',
        shadowHidden: false,
        healthDataConsentAt: consentAt,
      );

  @override
  Future<double?> fetchLatestBodyWeightKg() async => weightKg;
}

Widget _host(List<RouteMarkerRow> markers,
    {Preferences? prefs, ApiClient? api}) {
  final r = _route();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: RoadbookScreen(
      route: r,
      waypoints: r.waypoints,
      api: api,
      preferences: prefs,
      initialMarkers: markers,
    ),
  );
}

void main() {
  testWidgets('fueling toggle reveals per-leg carbs and a carry hint',
      (tester) async {
    await tester.pumpWidget(_host([
      _marker('aid_station', 'Aid 1', 1000, const {'services': ['water', 'food']}),
    ]));
    await tester.pump();

    // Fuel figures hidden until the toggle is on.
    expect(find.textContaining('Carbs:'), findsNothing);

    await tester.tap(find.text('Fuel'));
    await tester.pump();

    // Heat toggle only appears once fueling is on.
    expect(find.text('Heat'), findsOneWidget);

    // Per-leg carbs render.
    expect(find.textContaining('Carbs:'), findsWidgets);
    // The start leg carries fuel out to the first refill (Aid 1).
    expect(find.textContaining('carry'), findsWidgets);
  });

  testWidgets('fueling uses the carbs/hr preference, not the flat default',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs60 = Preferences();
    await prefs60.init(); // defaults to 60 g/hr
    final prefs90 = Preferences();
    await prefs90.init();
    await prefs90.setCarbsPerHourG(90);

    final markers = [
      _marker('aid_station', 'Aid 1', 1000, const {'services': ['water', 'food']}),
    ];
    List<String> carbsTexts() => tester
        .widgetList<Text>(find.textContaining('Carbs:'))
        .map((t) => t.data ?? '')
        .toList();

    await tester.pumpWidget(_host(markers, prefs: prefs60));
    await tester.pump();
    await tester.tap(find.text('Fuel'));
    await tester.pump();
    final at60 = carbsTexts();

    await tester.pumpWidget(_host(markers, prefs: prefs90));
    await tester.pump();
    await tester.tap(find.text('Fuel'));
    await tester.pump();
    final at90 = carbsTexts();

    // Same course + goal; only the rate differs, so every leg's carbs scale
    // up — proving the screen reads the preference, not the flat constant.
    expect(at60, isNotEmpty);
    expect(at90, isNot(equals(at60)));
  });

  final aid = [
    _marker('aid_station', 'Aid 1', 1000, const {'services': ['water', 'food']}),
  ];

  testWidgets(
      'with consent and a weight, opting in uses the weight-based fluid rate',
      (tester) async {
    await tester.pumpWidget(_host(aid,
        api: _WeightApi(consentAt: DateTime.utc(2026, 8, 1), weightKg: 90)));
    await tester.pump();
    await tester.tap(find.text('Fuel'));
    await tester.pump();

    final toggle = find.byKey(const Key('roadbook-weight-fluid'));
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
    await tester.tap(toggle);
    await tester.pump();

    // 500 × 90 / 70 = 642.9 → 650 ml/h (decisions § 1976).
    expect(find.text('Fluid: 650 ml per hour from your body weight.'),
        findsOneWidget);
  });

  testWidgets('a weight without the Art 9 stamp is never offered or used',
      (tester) async {
    await tester.pumpWidget(_host(aid, api: _WeightApi(weightKg: 90)));
    await tester.pump();
    await tester.tap(find.text('Fuel'));
    await tester.pump();

    final toggle = find.byKey(const Key('roadbook-weight-fluid'));
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(find.textContaining('give health-data consent'), findsOneWidget);
    expect(find.textContaining('from your body weight'), findsNothing);
  });
}
