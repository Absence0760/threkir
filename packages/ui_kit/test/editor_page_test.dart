import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _bar = 48.0;

Future<void> _open(
  WidgetTester tester, {
  Size size = const Size(360, 740),
  double keyboard = 0,
  double textScale = 1,
  List<Widget>? fields,
  EditorSave? save,
  Widget? secondary,
  Widget? status,
  Widget? placeholder,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: _bar);
  // The engine reports `padding` net of the keyboard, which covers the bar.
  tester.view.padding = FakeViewPadding(bottom: keyboard > 0 ? 0 : _bar);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => EditorPage(
                  title: 'New gear',
                  fields:
                      fields ??
                      [
                        const TextField(),
                        for (var i = 0; i < 30; i++) Text('row $i'),
                      ],
                  save: save ?? EditorSave(label: 'Save', onPressed: () {}),
                  secondary: secondary,
                  status: status,
                  placeholder: placeholder,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

Finder get _save => find.widgetWithText(FilledButton, 'Save');

void main() {
  testWidgets('the app bar carries a close button, the title is said in the '
      'body, and there is no Save in the bar', (tester) async {
    await _open(tester);
    expect(find.byType(CloseButton), findsOneWidget);
    // The heading at the top of the form says the title in full; the bar's
    // copy stays hidden until that heading scrolls away.
    expect(
      find.descendant(
        of: find.byType(PageHeader),
        matching: find.text('New gear'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.descendant(
                of: find.byType(AppBar),
                matching: find.text('New gear'),
              ),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity,
      0,
    );
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Save')),
      findsNothing,
    );
  });

  testWidgets(
    'Save is pinned above a 3-button nav bar while the body scrolls',
    (tester) async {
      await _open(tester);
      expect(find.text('row 29').hitTestable(), findsNothing);
      expect(_save.hitTestable(), findsOneWidget);
      expect(tester.getRect(_save).bottom, lessThanOrEqualTo(740 - _bar));
    },
  );

  testWidgets('with the keyboard up Save sits just above it', (tester) async {
    await _open(tester, keyboard: 300);
    final rect = tester.getRect(_save);
    expect(rect.bottom, lessThanOrEqualTo(740 - 300));
    expect(rect.bottom, greaterThan(740 - 300 - 48));
    expect(_save.hitTestable(), findsOneWidget);
  });

  testWidgets(
    'a short form at 320 dp, 2x text and the keyboard up does not overflow '
    'and keeps Save tappable (IK-11)',
    (tester) async {
      await _open(
        tester,
        size: const Size(320, 568),
        keyboard: 260,
        textScale: 2,
        fields: const [
          Text('Enter the invite code you were sent'),
          TextField(),
          Text('The code is case sensitive'),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(_save.hitTestable(), findsOneWidget);
      expect(tester.getRect(_save).bottom, lessThanOrEqualTo(568 - 260));
    },
  );

  testWidgets(
    'a long Save beside a Delete stacks rather than clipping at 320 dp and '
    '2x (TO-7)',
    (tester) async {
      await _open(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        save: EditorSave(label: 'Enregistrer et pointer', onPressed: () {}),
        secondary: TextButton(onPressed: () {}, child: const Text('Supprimer')),
      );
      expect(tester.takeException(), isNull);
      final save = tester.getRect(
        find.widgetWithText(FilledButton, 'Enregistrer et pointer'),
      );
      final delete = tester.getRect(
        find.widgetWithText(TextButton, 'Supprimer'),
      );
      expect(save.right, lessThanOrEqualTo(320));
      expect(save.left, greaterThanOrEqualTo(0));
      expect(save.top, greaterThanOrEqualTo(delete.bottom));
    },
  );

  testWidgets('busy disables Save and keeps its label', (tester) async {
    var taps = 0;
    await _open(
      tester,
      save: EditorSave(label: 'Save', onPressed: () => taps++, busy: true),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(_save, warnIfMissed: false);
    expect(taps, 0);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
  });

  testWidgets('status sits in the bar above the actions', (tester) async {
    await _open(tester, status: const Text('12 weeks, ends 3 May'));
    final status = tester.getRect(find.text('12 weeks, ends 3 May'));
    expect(status.bottom, lessThanOrEqualTo(tester.getRect(_save).top));
    expect(find.text('12 weeks, ends 3 May').hitTestable(), findsOneWidget);
  });

  testWidgets('a placeholder replaces the fields and the bar', (tester) async {
    await _open(tester, placeholder: const Center(child: Text('Loading')));
    expect(find.text('Loading'), findsOneWidget);
    expect(_save, findsNothing);
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('the close button asks the route to maybePop', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(EditorPage), findsNothing);
  });
}
