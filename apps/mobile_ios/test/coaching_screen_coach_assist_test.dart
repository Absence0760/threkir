import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/coach_assist_consent.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/coaching_screen.dart';

/// The athlete's per-coach coach-assistant consent (issue #1215 Phase 4).
/// Web twin: `CoachAssistConsent.svelte` on /coaching.
class _FakeApi extends ApiClient {
  _FakeApi(this.coaches);

  final List<CoachAthleteLink> coaches;
  final List<(String, int?)> consentCalls = [];
  Completer<int?>? reply;
  Object? consentError;

  @override
  String? get userId => 'athlete-1';

  @override
  Future<List<CoachAthleteLink>> fetchMyAthletes() async => const [];

  @override
  Future<List<PendingCoachInvite>> fetchPendingCoachInvites() async =>
      const [];

  @override
  Future<List<CoachAthleteLink>> fetchMyCoaches() async => coaches;

  @override
  Future<List<CoachRosterRow>> fetchCoachRosterSummary() async => const [];

  @override
  Future<int?> setCoachAiAssistConsent(String linkId, int? version) async {
    consentCalls.add((linkId, version));
    final pending = reply;
    if (pending != null) return pending.future;
    final error = consentError;
    if (error != null) throw error;
    return version;
  }
}

CoachAthleteLink _coach(String id, String name, {int? consent}) =>
    CoachAthleteLink(
      id: id,
      status: 'active',
      note: null,
      createdAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
      userId: 'coach-$id',
      displayName: name,
      avatarUrl: null,
      aiAssistConsentVersion: consent,
    );

late AppLocalizations l10n;

Future<void> _pump(
  WidgetTester tester,
  _FakeApi api, {
  required bool assist,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CoachingScreen(
        api: api,
        preferences: prefs,
        hrPrescription: false,
        loadCoachAssistAvailable: () async => assist,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _toggleOf(String linkId) => find.descendant(
      of: find.byKey(ValueKey('coach-assist-consent-$linkId')),
      matching: find.byType(Switch),
    );

bool _isOn(WidgetTester tester, String linkId) =>
    tester.widget<Switch>(_toggleOf(linkId)).value;

Future<void> _tap(WidgetTester tester, String linkId) async {
  await tester.ensureVisible(_toggleOf(linkId));
  await tester.pump();
  await tester.tap(_toggleOf(linkId));
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('with the capability off no switch is offered', (tester) async {
    final api = _FakeApi([_coach('l1', 'Kim')]);
    await _pump(tester, api, assist: false);

    expect(find.text('Kim'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text(l10n.coachAssistConsentToggle('Kim')), findsNothing);
  });

  testWidgets('with it on each coach gets a switch, off until allowed, and '
      'the copy of what it shares', (tester) async {
    final api = _FakeApi([
      _coach('l1', 'Kim'),
      _coach('l2', 'Lee', consent: kCoachAssistConsentVersion),
    ]);
    await _pump(tester, api, assist: true);

    expect(find.text(l10n.coachAssistConsentToggle('Kim')), findsOneWidget);
    expect(find.text(l10n.coachAssistConsentToggle('Lee')), findsOneWidget);
    expect(_isOn(tester, 'l1'), isFalse);
    expect(_isOn(tester, 'l2'), isTrue);

    final what = find.descendant(
      of: find.byKey(const ValueKey('coach-assist-consent-l1')),
      matching: find.text(l10n.coachAssistConsentWhat),
    );
    await tester.ensureVisible(what);
    await tester.pump();
    await tester.tap(what);
    await tester.pumpAndSettle();
    for (final line in [
      l10n.coachAssistConsentIntro('Kim'),
      '• ${l10n.coachAssistConsentBulletThread}',
      '• ${l10n.coachAssistConsentBulletPlan}',
      '• ${l10n.coachAssistConsentBulletRuns}',
      l10n.coachAssistConsentOutro('Kim'),
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(api.consentCalls, isEmpty);
  });

  testWidgets('turning it on sends the current version; off sends null',
      (tester) async {
    final api = _FakeApi([_coach('l1', 'Kim')]);
    await _pump(tester, api, assist: true);

    await _tap(tester, 'l1');
    expect(api.consentCalls, [('l1', kCoachAssistConsentVersion)]);
    expect(_isOn(tester, 'l1'), isTrue);

    await _tap(tester, 'l1');
    expect(api.consentCalls, [
      ('l1', kCoachAssistConsentVersion),
      ('l1', null),
    ]);
    expect(_isOn(tester, 'l1'), isFalse);
    expect(find.byKey(const ValueKey('coach-assist-consent-error')),
        findsNothing);
  });

  testWidgets('the switch holds while saving and cannot be tapped twice',
      (tester) async {
    final api = _FakeApi([_coach('l1', 'Kim')])..reply = Completer<int?>();
    await _pump(tester, api, assist: true);

    await _tap(tester, 'l1');
    expect(_isOn(tester, 'l1'), isTrue);
    expect(tester.widget<Switch>(_toggleOf('l1')).onChanged, isNull);
    await tester.tap(_toggleOf('l1'));
    await tester.pump();
    expect(api.consentCalls, hasLength(1));

    api.reply!.complete(kCoachAssistConsentVersion);
    await tester.pump();
    expect(_isOn(tester, 'l1'), isTrue);
    expect(tester.widget<Switch>(_toggleOf('l1')).onChanged, isNotNull);
  });

  testWidgets('a failed save reverts the switch and says so', (tester) async {
    final api = _FakeApi([_coach('l1', 'Kim')])
      ..consentError = const CoachAssistConsentRefused();
    await _pump(tester, api, assist: true);

    await _tap(tester, 'l1');
    expect(api.consentCalls, [('l1', kCoachAssistConsentVersion)]);
    expect(_isOn(tester, 'l1'), isFalse);
    expect(find.text(l10n.coachAssistConsentFailed), findsOneWidget);

    api.consentError = null;
    await _tap(tester, 'l1');
    expect(_isOn(tester, 'l1'), isTrue);
    expect(find.text(l10n.coachAssistConsentFailed), findsNothing);
  });

  testWidgets('a failed withdrawal leaves it on', (tester) async {
    final api = _FakeApi([
      _coach('l1', 'Kim', consent: kCoachAssistConsentVersion),
    ])..consentError = Exception('offline');
    await _pump(tester, api, assist: true);

    await _tap(tester, 'l1');
    expect(api.consentCalls, [('l1', null)]);
    expect(_isOn(tester, 'l1'), isTrue);
    expect(find.text(l10n.coachAssistConsentFailed), findsOneWidget);
  });
}
