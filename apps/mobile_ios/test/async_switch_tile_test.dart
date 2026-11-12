import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/async_switch_tile.dart';

const _key = Key('s');

Future<({List<bool> changes, List<int> retries})> _pump(
  WidgetTester tester, {
  bool? value,
  bool failed = false,
  bool saving = false,
}) async {
  final changes = <bool>[];
  final retries = <int>[];
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AsyncSwitchTile(
        switchKey: _key,
        title: 'Private profile',
        subtitle: 'Only followers see your runs',
        value: value,
        failed: failed,
        saving: saving,
        onChanged: changes.add,
        onRetry: () => retries.add(1),
      ),
    ),
  ));
  return (changes: changes, retries: retries);
}

void main() {
  testWidgets('loading shows a disabled switch', (tester) async {
    await _pump(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(_key)).onChanged, isNull);
  });

  testWidgets('a failed read shows no switch and the row retries',
      (tester) async {
    final calls = await _pump(tester, value: false, failed: true);
    final l10n = AppLocalizations.of(tester.element(find.byType(ListTile)));
    expect(find.byKey(_key), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text(l10n.asyncSwitchLoadFailed), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    expect(calls.retries, [1]);
  });

  testWidgets('a loaded value is shown and toggles', (tester) async {
    final calls = await _pump(tester, value: true);
    expect(tester.widget<SwitchListTile>(find.byKey(_key)).value, isTrue);
    await tester.tap(find.byKey(_key));
    expect(calls.changes, [false]);
  });

  testWidgets('a save in flight disables the switch', (tester) async {
    await _pump(tester, value: true, saving: true);
    expect(tester.widget<SwitchListTile>(find.byKey(_key)).onChanged, isNull);
  });
}
