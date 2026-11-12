// Widget smoke tests for CoachAssistConsentSwitch (issue #1215 Phase 4): the
// switch shows the consent stored on the coaching link, a toggle saves at the
// current version (or withdraws with null), and a refused save puts the
// switch back and says so.

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/coach_assist_consent.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/widgets/coach_assist_consent_switch.dart';

class _FakeApiClient extends ApiClient {
  final calls = <(String, int?)>[];
  Object? errorToThrow;
  Completer<void>? gate;

  @override
  Future<int?> setCoachAiAssistConsent(String linkId, int? version) async {
    calls.add((linkId, version));
    if (gate != null) await gate!.future;
    if (errorToThrow != null) throw errorToThrow!;
    return version;
  }
}

final _l10n = AppLocalizationsEn();
final _toggle = find.byKey(const ValueKey('coach-assist-consent-toggle'));
final _error = find.byKey(const ValueKey('coach-assist-consent-error'));

CoachAthleteLink _link(int? version) => CoachAthleteLink(
      id: 'link-1',
      status: 'accepted',
      note: null,
      createdAt: DateTime.utc(2026, 11, 1),
      acceptedAt: DateTime.utc(2026, 11, 2),
      userId: 'coach-1',
      displayName: 'Sam',
      avatarUrl: null,
      aiAssistConsentVersion: version,
    );

Future<List<int?>> _mount(
  WidgetTester tester,
  ApiClient api, {
  int? version,
}) async {
  final changes = <int?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Host(api: api, initial: version, changes: changes),
      ),
    ),
  );
  return changes;
}

/// Holds the link the way the coaching screen does: a landed save replaces
/// it with the version the server stored.
class _Host extends StatefulWidget {
  const _Host({required this.api, required this.initial, required this.changes});

  final ApiClient api;
  final int? initial;
  final List<int?> changes;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late CoachAthleteLink link = _link(widget.initial);

  @override
  Widget build(BuildContext context) => CoachAssistConsentSwitch(
        api: widget.api,
        link: link,
        coachName: 'Sam',
        onChanged: (v) {
          widget.changes.add(v);
          setState(() => link = link.withAiAssistConsentVersion(v));
        },
      );
}

bool _value(WidgetTester tester) =>
    tester.widget<SwitchListTile>(_toggle).value;

void main() {
  testWidgets('shows off when the link holds no consent, named for the coach',
      (tester) async {
    await _mount(tester, _FakeApiClient());
    expect(_value(tester), isFalse);
    expect(find.text(_l10n.coachAssistConsentToggle('Sam')), findsOneWidget);
    expect(_error, findsNothing);
  });

  testWidgets('shows on when the link holds a consent', (tester) async {
    await _mount(tester, _FakeApiClient(), version: kCoachAssistConsentVersion);
    expect(_value(tester), isTrue);
  });

  testWidgets('turning it on saves the current version and stays on',
      (tester) async {
    final api = _FakeApiClient();
    final changes = await _mount(tester, api);
    await tester.tap(_toggle);
    await tester.pump();
    expect(api.calls, [('link-1', kCoachAssistConsentVersion)]);
    expect(changes, [kCoachAssistConsentVersion]);
    expect(_value(tester), isTrue);
    expect(_error, findsNothing);
  });

  testWidgets('turning it off withdraws with null', (tester) async {
    final api = _FakeApiClient();
    final changes =
        await _mount(tester, api, version: kCoachAssistConsentVersion);
    await tester.tap(_toggle);
    await tester.pump();
    expect(api.calls, [('link-1', null)]);
    expect(changes, [null]);
    expect(_value(tester), isFalse);
  });

  testWidgets('while a save is in flight the switch shows it and locks',
      (tester) async {
    final api = _FakeApiClient()..gate = Completer<void>();
    await _mount(tester, api);
    await tester.tap(_toggle);
    await tester.pump();
    expect(_value(tester), isTrue);
    expect(tester.widget<SwitchListTile>(_toggle).onChanged, isNull);
    api.gate!.complete();
    await tester.pump();
    expect(tester.widget<SwitchListTile>(_toggle).onChanged, isNotNull);
  });

  testWidgets('a refused save puts the switch back and says so',
      (tester) async {
    final api = _FakeApiClient()..errorToThrow = Exception('offline');
    final changes = await _mount(tester, api);
    await tester.tap(_toggle);
    await tester.pump();
    expect(api.calls, hasLength(1));
    expect(changes, isEmpty);
    expect(_value(tester), isFalse);
    expect(_error, findsOneWidget);
    expect(find.text(_l10n.coachAssistConsentFailed), findsOneWidget);

    // The next attempt clears the message before it tries again.
    api.errorToThrow = null;
    await tester.tap(_toggle);
    await tester.pump();
    expect(_error, findsNothing);
    expect(_value(tester), isTrue);
  });

  testWidgets('the explainer names every lane the drafting endpoint sends',
      (tester) async {
    await _mount(tester, _FakeApiClient());
    await tester.tap(find.text(_l10n.coachAssistConsentWhat));
    await tester.pumpAndSettle();
    for (final bullet in [
      _l10n.coachAssistConsentBulletThread,
      _l10n.coachAssistConsentBulletPlan,
      _l10n.coachAssistConsentBulletRuns,
    ]) {
      expect(find.text('• $bullet'), findsOneWidget);
    }
    expect(find.text(_l10n.coachAssistConsentIntro('Sam')), findsOneWidget);
    expect(find.text(_l10n.coachAssistConsentOutro('Sam')), findsOneWidget);
  });
}
