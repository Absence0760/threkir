import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart' show AppTheme, SheetScaffold;

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/l10n/gen/app_localizations_en.dart';
import '../lib/widgets/form_sheet.dart';

/// Issue #1374 NS-13: a sheet holding typed text closed on a swipe, a tap on
/// the barrier or Back, and the text was gone. A swipe on a framework sheet
/// closes through `Navigator.pop`, which no `PopScope` can stop, so
/// `showFormSheet` drives the swipe itself through `SheetDiscardGuard`.
final _l10n = AppLocalizationsEn();

class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SheetDiscardGuard(
        isDirty: () => _note.text.trim().isNotEmpty,
        child: SheetScaffold(
          title: const Text('Note'),
          body: TextField(key: const Key('note'), controller: _note),
          actions: Row(
            children: [
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _note.text),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
}

/// Pumps a phone, opens the sheet and returns what it resolves to.
Future<List<String?>> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <String?>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => results.add(await showFormSheet<String>(
              context,
              builder: (_) => const _NoteSheet(),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _type(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('note')), 'Course flooded');
  await tester.pump();
}

final _sheet = find.byType(_NoteSheet);
final _prompt = find.text(_l10n.discardChangesTitle);
final _handle = find.byKey(const ValueKey('form-sheet-handle'));

Future<void> _swipeDown(WidgetTester tester) async {
  await tester.fling(_handle, const Offset(0, 300), 1500);
  await tester.pumpAndSettle();
}

Future<void> _tapBarrier(WidgetTester tester) async {
  await tester.tapAt(const Offset(180, 20));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens scroll-controlled under the status bar, with one handle',
      (tester) async {
    await _open(tester);
    final route = ModalRoute.of(tester.element(_sheet))!;
    expect(route, isA<ModalBottomSheetRoute<String>>());
    final sheetRoute = route as ModalBottomSheetRoute<String>;
    expect(sheetRoute.isScrollControlled, isTrue);
    expect(sheetRoute.useSafeArea, isTrue);
    expect(sheetRoute.enableDrag, isFalse);
    // The theme's handle would close the sheet without asking; the guard
    // draws the only one.
    expect(sheetRoute.showDragHandle, isFalse);
    expect(_handle, findsOneWidget);
  });

  group('with nothing typed, every way out closes at once', () {
    for (final (name, close) in [
      ('a swipe down', _swipeDown),
      ('a tap on the barrier', _tapBarrier),
      ('Back', _back),
    ]) {
      testWidgets(name, (tester) async {
        final results = await _open(tester);
        await close(tester);
        expect(_prompt, findsNothing);
        expect(_sheet, findsNothing);
        expect(results, [null]);
      });
    }
  });

  group('with text typed, every way out asks first', () {
    for (final (name, close) in [
      ('a swipe down', _swipeDown),
      ('a tap on the barrier', _tapBarrier),
      ('Back', _back),
      (
        'the sheet\'s own Close button',
        (WidgetTester tester) async {
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        }
      ),
    ]) {
      testWidgets('$name, and keeping the text keeps the sheet',
          (tester) async {
        await _open(tester);
        await _type(tester);
        await close(tester);
        expect(_prompt, findsOneWidget);
        await tester.tap(find.text(_l10n.discardChangesCancel));
        await tester.pumpAndSettle();
        expect(_sheet, findsOneWidget);
        expect(find.text('Course flooded'), findsOneWidget);
      });

      testWidgets('$name, and discarding closes it', (tester) async {
        final results = await _open(tester);
        await _type(tester);
        await close(tester);
        await tester.tap(find.text(_l10n.discardChangesDiscard));
        await tester.pumpAndSettle();
        expect(_sheet, findsNothing);
        expect(results, [null]);
      });
    }
  });

  testWidgets('Save closes without asking and returns the text',
      (tester) async {
    final results = await _open(tester);
    await _type(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_prompt, findsNothing);
    expect(results, ['Course flooded']);
  });

  testWidgets('the sheet follows the finger and springs back when let go short',
      (tester) async {
    await _open(tester);
    final top = tester.getTopLeft(_sheet).dy;
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    expect(tester.getTopLeft(_sheet).dy, greaterThan(top));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_sheet).dy, moreOrLessEquals(top));
    expect(_sheet, findsOneWidget);
  });

  test('FieldSnapshot reports a change against the opening text', () {
    final a = TextEditingController(text: 'Spring Half');
    final b = TextEditingController();
    final start = FieldSnapshot([a, b]);
    expect(start.changed, isFalse);
    a.text = 'Spring Half ';
    expect(start.changed, isFalse, reason: 'surrounding space is not an edit');
    b.text = '42';
    expect(start.changed, isTrue);
    a.dispose();
    b.dispose();
  });
}
