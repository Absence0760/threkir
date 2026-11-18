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
  Widget? page,
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
                builder: (_) =>
                    page ??
                    EditorPage(
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

  group('dismissible / closeEnabled', () {
    testWidgets('a gate that is not dismissible draws no close or back '
        'button', (tester) async {
      await _open(
        tester,
        page: EditorPage(
          title: 'Confirm your age',
          dismissible: false,
          fields: const [Text('lede')],
          save: EditorSave(label: 'Save', onPressed: () {}),
        ),
      );
      expect(find.byType(CloseButton), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading,
        isFalse,
      );
    });

    testWidgets('closeEnabled: false draws the close button disabled and a '
        'tap does not pop', (tester) async {
      await _open(
        tester,
        page: EditorPage(
          title: 'Crop photo',
          closeEnabled: false,
          fields: const [Text('stage')],
          save: EditorSave(label: 'Save', onPressed: null),
        ),
      );
      final close = find.widgetWithIcon(IconButton, Icons.close);
      expect(close, findsOneWidget);
      expect(tester.widget<IconButton>(close).onPressed, isNull);
      expect(
        tester.widget<IconButton>(close).tooltip,
        const DefaultMaterialLocalizations().closeButtonTooltip,
      );
      await tester.tap(close, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(EditorPage), findsOneWidget);
    });
  });

  group('header', () {
    testWidgets('stays put under the app bar while the fields scroll', (
      tester,
    ) async {
      await _open(
        tester,
        page: EditorPage(
          title: 'Set up',
          header: const SizedBox(height: 24, child: Text('dots')),
          fields: [for (var i = 0; i < 60; i++) Text('row $i')],
          save: EditorSave(label: 'Save', onPressed: () {}),
        ),
      );
      final before = tester.getRect(find.text('dots'));
      final appBar = tester.getRect(find.byType(AppBar));
      expect(before.top, greaterThanOrEqualTo(appBar.bottom));
      final row0 = tester.getRect(find.text('row 0')).top;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('dots')), before);
      expect(tester.getRect(find.text('row 0')).top, lessThan(row0));
      // The fields scroll under the header, not over it.
      expect(
        tester.getRect(find.byType(SingleChildScrollView)).top,
        greaterThanOrEqualTo(before.bottom),
      );
    });

    testWidgets('the bar title comes in once the heading scrolls under the '
        'header', (tester) async {
      await _open(
        tester,
        page: EditorPage(
          title: 'Set up',
          header: const SizedBox(height: 40, child: Text('dots')),
          fields: [for (var i = 0; i < 60; i++) Text('row $i')],
          save: EditorSave(label: 'Save', onPressed: () {}),
        ),
      );
      double barOpacity() => tester
          .widget<AnimatedOpacity>(
            find.ancestor(
              of: find.descendant(
                of: find.byType(AppBar),
                matching: find.text('Set up'),
              ),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(barOpacity(), 0);
      // Far enough that the heading is under the header's bottom edge but not
      // yet under the app bar: the header is the edge it scrolls under.
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .jumpTo(60);
      await tester.pumpAndSettle();
      final heading = tester.getRect(
        find.descendant(
          of: find.byType(PageHeader),
          matching: find.text('Set up'),
        ),
      );
      expect(
        heading.bottom,
        lessThan(tester.getRect(find.text('dots')).bottom),
      );
      expect(
        heading.bottom,
        greaterThan(tester.getRect(find.byType(AppBar)).bottom),
      );
      expect(barOpacity(), 1);
    });
  });

  group('custom bar', () {
    const bandKey = Key('band');
    Widget band() => Container(
      key: bandKey,
      height: 64,
      color: const Color(0xFF00FF00),
      child: TextButton(onPressed: () {}, child: const Text('Log set')),
    );

    testWidgets('replaces the standard bar and clears a 48 dp nav bar', (
      tester,
    ) async {
      await _open(
        tester,
        page: EditorPage(
          title: 'Session',
          fields: [for (var i = 0; i < 40; i++) Text('row $i')],
          bar: band(),
        ),
      );
      expect(find.byType(EditorActionBar), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      final rect = tester.getRect(find.byKey(bandKey));
      expect(rect.bottom, lessThanOrEqualTo(740 - _bar));
      expect(rect.bottom, greaterThan(740 - _bar - 1));
      expect(find.text('Log set').hitTestable(), findsOneWidget);
      // Under the fields, which end above it.
      expect(find.text('row 39').hitTestable(), findsNothing);
    });

    testWidgets('rises above the keyboard', (tester) async {
      await _open(
        tester,
        keyboard: 300,
        page: EditorPage(
          title: 'Session',
          fields: const [TextField(), Text('reps')],
          bar: band(),
        ),
      );
      final rect = tester.getRect(find.byKey(bandKey));
      expect(rect.bottom, lessThanOrEqualTo(740 - 300));
      expect(rect.bottom, greaterThan(740 - 300 - 1));
      expect(find.text('Log set').hitTestable(), findsOneWidget);
    });

    testWidgets('a bar taller than the room is held to its share of the body, '
        'leaving the fields room above it', (tester) async {
      await _open(
        tester,
        keyboard: 300,
        page: EditorPage(
          title: 'Session',
          fields: const [TextField(key: Key('reps'))],
          bar: Column(
            key: bandKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: SingleChildScrollView(child: SizedBox(height: 1000)),
              ),
              TextButton(onPressed: () {}, child: const Text('Log set')),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final appBar = tester.getRect(find.byType(AppBar)).bottom;
      final body = 740 - 300 - appBar;
      final band = tester.getRect(find.byKey(bandKey));
      expect(band.height, closeTo(body * EditorPage.maxBarShare, 0.01));
      expect(band.bottom, 740 - 300);
      expect(find.text('Log set').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('reps')));
      await tester.pump();
      expect(find.byKey(const Key('reps')).hitTestable(), findsOneWidget);
    });

    testWidgets('at 320 dp and 2x text it does not overflow', (tester) async {
      await _open(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        page: EditorPage(
          title: 'Session',
          fields: const [TextField(), Text('reps')],
          bar: TextButton(onPressed: () {}, child: const Text('Log set')),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.text('Log set')).bottom,
        lessThanOrEqualTo(568 - _bar),
      );
    });
  });

  group('EditorPage.fixed', () {
    testWidgets('lays its child out with bounded constraints between the app '
        'bar and the Save bar, and says the title in the bar', (tester) async {
      BoxConstraints? seen;
      await _open(
        tester,
        page: EditorPage.fixed(
          title: 'Crop photo',
          save: EditorSave(label: 'Save', onPressed: () {}),
          child: LayoutBuilder(
            builder: (context, box) {
              seen = box;
              return const SizedBox.expand(key: Key('stage'));
            },
          ),
        ),
      );
      expect(seen, isNotNull);
      expect(seen!.hasBoundedHeight, isTrue);
      expect(seen!.hasBoundedWidth, isTrue);
      expect(find.byType(Scrollable), findsNothing);
      final stage = tester.getRect(find.byKey(const Key('stage')));
      expect(stage.top, tester.getRect(find.byType(AppBar)).bottom);
      expect(stage.bottom, lessThanOrEqualTo(tester.getRect(_save).top));
      expect(tester.getRect(_save).bottom, lessThanOrEqualTo(740 - _bar));
      expect(find.byType(PageHeader), findsNothing);
      final barTitle = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Crop photo'),
          ),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(barTitle.opacity, 1);
    });

    testWidgets('shrinks with the keyboard and keeps a custom bar above it', (
      tester,
    ) async {
      BoxConstraints? seen;
      await _open(
        tester,
        keyboard: 300,
        page: EditorPage.fixed(
          title: 'Crop photo',
          header: const SizedBox(height: 20),
          bar: const SizedBox(key: Key('band'), height: 40),
          child: LayoutBuilder(
            builder: (context, box) {
              seen = box;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      final appBar = tester.getRect(find.byType(AppBar)).bottom;
      expect(seen!.maxHeight, 740 - 300 - 40 - 20 - appBar);
      expect(tester.getRect(find.byKey(const Key('band'))).bottom, 740 - 300);
    });

    testWidgets('a pan gesture on the stage reaches the child', (tester) async {
      var panned = Offset.zero;
      await _open(
        tester,
        page: EditorPage.fixed(
          title: 'Crop photo',
          save: EditorSave(label: 'Save', onPressed: () {}),
          child: GestureDetector(
            key: const Key('stage'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => panned += d.delta,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.drag(find.byKey(const Key('stage')), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(panned.dy, lessThan(-40));
    });
  });
}
