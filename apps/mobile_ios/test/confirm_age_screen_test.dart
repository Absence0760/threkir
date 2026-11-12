import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/confirm_age_screen.dart';

class _GateApi extends ApiClient {
  bool failConfirm = false;
  bool failSignOut = false;
  int confirmCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> confirmAgeAndTerms() async {
    confirmCalls++;
    if (failConfirm) throw Exception('network down');
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOut) throw Exception('network down');
  }
}

/// Pushes the gate from a launcher page and records what it popped with.
Future<List<bool?>> _pumpGate(WidgetTester tester, _GateApi api) async {
  final popped = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            popped.add(await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => ConfirmAgeScreen(apiClient: api),
              ),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return popped;
}

Future<void> _tickBoth(WidgetTester tester) async {
  await tester.tap(find.byType(Checkbox).at(0));
  await tester.pump();
  await tester.tap(find.byType(Checkbox).at(1));
  await tester.pump();
}

void main() {
  testWidgets('a failed stamp keeps the gate up and says so', (tester) async {
    final api = _GateApi()..failConfirm = true;
    final popped = await _pumpGate(tester, api);
    await _tickBoth(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(api.confirmCalls, 1);
    expect(popped, isEmpty);
    expect(find.byType(ConfirmAgeScreen), findsOneWidget);
    expect(find.textContaining('Could not record consent.'), findsOneWidget);
  });

  testWidgets('the system back gesture cannot dismiss the gate',
      (tester) async {
    final api = _GateApi();
    final popped = await _pumpGate(tester, api);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isEmpty);
    expect(find.byType(ConfirmAgeScreen), findsOneWidget);
  });

  testWidgets('signing out leaves the gate without recording anything',
      (tester) async {
    final api = _GateApi();
    final popped = await _pumpGate(tester, api);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(api.signOutCalls, 1);
    expect(api.confirmCalls, 0);
    expect(popped, [false]);
  });

  testWidgets('a failed sign-out keeps the gate up', (tester) async {
    final api = _GateApi()..failSignOut = true;
    final popped = await _pumpGate(tester, api);
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(popped, isEmpty);
    expect(find.byType(ConfirmAgeScreen), findsOneWidget);
  });
}
