import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/return_to_shell.dart';
import '../lib/widgets/confirm_discard.dart';

class _Form extends StatelessWidget {
  const _Form({required this.dirty, required this.label});

  final bool dirty;
  final String label;

  @override
  Widget build(BuildContext context) => DiscardGuard(
        isDirty: () => dirty,
        child: Scaffold(body: Text(label)),
      );
}

late NavigatorState _nav;

Future<void> _pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (context) {
      _nav = Navigator.of(context);
      return const Scaffold(body: Text('shell'));
    }),
  ));
}

void _push(Widget page) =>
    _nav.push(MaterialPageRoute<void>(builder: (_) => page));

Future<void> _answer(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog), matching: find.text(label)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('pops every unguarded route back to the shell', (tester) async {
    await _pumpShell(tester);
    _push(const Scaffold(body: Text('a')));
    _push(const _Form(dirty: false, label: 'b'));
    await tester.pumpAndSettle();

    bool? result;
    returnToShell(_nav).then((r) => result = r);
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    expect(find.text('b'), findsNothing);
  });

  testWidgets('a dirty form asks first, and Cancel keeps it and stops',
      (tester) async {
    await _pumpShell(tester);
    _push(const Scaffold(body: Text('below')));
    _push(const _Form(dirty: true, label: 'form'));
    await tester.pumpAndSettle();

    bool? result;
    returnToShell(_nav).then((r) => result = r);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Discard changes?'), findsOneWidget);

    await _answer(tester, 'Cancel');
    expect(result, isFalse);
    expect(find.text('form'), findsOneWidget);
    expect(find.text('Discard changes?'), findsNothing);
  });

  testWidgets('Discard lets it go and the walk carries on to the shell',
      (tester) async {
    await _pumpShell(tester);
    _push(const Scaffold(body: Text('below')));
    _push(const _Form(dirty: true, label: 'form'));
    await tester.pumpAndSettle();

    bool? result;
    returnToShell(_nav).then((r) => result = r);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _answer(tester, 'Discard');
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('form'), findsNothing);
    expect(find.text('below'), findsNothing);
  });

  testWidgets('a route that refuses without asking stops the walk',
      (tester) async {
    await _pumpShell(tester);
    _push(const PopScope<Object?>(
        canPop: false, child: Scaffold(body: Text('busy'))));
    await tester.pumpAndSettle();

    bool? result;
    returnToShell(_nav).then((r) => result = r);
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(find.text('busy'), findsOneWidget);
  });

  testWidgets('topRoute reads the top route without popping it',
      (tester) async {
    await _pumpShell(tester);
    _push(const Scaffold(body: Text('a')));
    await tester.pumpAndSettle();
    expect(topRoute(_nav)?.isFirst, isFalse);
    expect(find.text('a'), findsOneWidget);
  });
}
