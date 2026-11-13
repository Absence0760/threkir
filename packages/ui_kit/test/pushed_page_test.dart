import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _long = 'Calendrier du plan d’entraînement partagé avec le club';

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

double _barOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(find.descendant(
        of: find.byType(PageBarTitle), matching: find.byType(AnimatedOpacity)))
    .opacity;

Finder _inBar(String text) =>
    find.descendant(of: find.byType(AppBar), matching: find.text(text));

void main() {
  testWidgets('the title is said in the body, wrapping, and the bar repeats '
      'it only once the heading has scrolled away', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      PushedPage(
        title: _long,
        body: ListView(children: [
          const PageHeader(title: _long),
          for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
        ]),
      ),
      scale: 2,
    ));
    await tester.pump();

    final heading = find.descendant(
        of: find.byType(PageHeader), matching: find.text(_long));
    expect(tester.renderObject<RenderParagraph>(heading).didExceedMaxLines,
        isFalse);
    expect(_barOpacity(tester), 0);
    expect(tester.getSemantics(_inBar(_long)),
        isNot(matchesSemantics(label: _long)),
        reason: 'a screen reader reads the heading, not the hidden bar');
    final element = tester.element(find.byType(PageBarTitle));
    expect(PageTitleScope.hasInBodyTitle(element), isTrue);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 1);

    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(_barOpacity(tester), 0);
  });

  testWidgets('a page with no heading in its body shows the title in the bar',
      (tester) async {
    await tester.pumpWidget(_app(
      PushedPage(title: 'Plain', body: ListView(children: const [Text('x')])),
    ));
    await tester.pump();
    expect(_barOpacity(tester), 1);
    expect(PageTitleScope.hasInBodyTitle(tester.element(find.byType(PageBarTitle))),
        isFalse);
  });

  testWidgets('a placeholder titles the bar', (tester) async {
    await tester.pumpWidget(_app(
      const DetailPage.placeholder(title: 'Loading', child: SizedBox()),
    ));
    await tester.pump();
    expect(_inBar('Loading'), findsOneWidget);
    expect(_barOpacity(tester), 1);
  });

  testWidgets('a detail page shows two actions beside the overflow and never '
      'a destructive one', (tester) async {
    var reported = false;
    await tester.pumpWidget(_app(
      DetailPage(
        title: 'Run',
        actions: [
          AppBarAction(
              icon: const Icon(Icons.share), label: 'Share', onPressed: () {}),
          AppBarAction(
              icon: const Icon(Icons.edit), label: 'Edit', onPressed: () {}),
          AppBarAction(
              icon: const Icon(Icons.add_road),
              label: 'Save as route',
              onPressed: () {}),
          AppBarAction(
              key: const ValueKey('report'),
              icon: const Icon(Icons.flag),
              label: 'Report',
              destructive: true,
              onPressed: () => reported = true),
        ],
        body: ListView(children: const [DetailHero(title: 'Run')]),
      ),
    ));
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Save as route'), findsNothing);
    expect(find.byTooltip('Report'), findsNothing);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Save as route'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report')));
    await tester.pumpAndSettle();
    expect(reported, isTrue);
  });

  testWidgets('a busy overflow is a labelled spinner', (tester) async {
    await tester.pumpWidget(_app(
      DetailPage(
        title: 'Run',
        busyLabel: 'Deleting',
        actions: [
          AppBarAction(
              icon: const Icon(Icons.delete),
              label: 'Delete',
              destructive: true,
              onPressed: () {}),
        ],
        body: const SizedBox(),
      ),
    ));
    expect(find.byTooltip('More'), findsNothing);
    expect(find.bySemanticsLabel('Deleting'), findsOneWidget);
  });

  group('DetailHero', () {
    testWidgets('lays out its parent chip, meta and action at 320 dp and 2x',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var parent = 0;
      var joined = 0;
      await tester.pumpWidget(_app(
        DetailPage(
          title: _long,
          body: ListView(children: [
            DetailHero(
              title: _long,
              leading: const CircleAvatar(radius: 28),
              parent: DetailParentChip(
                  label: 'Riverside Running Club',
                  icon: Icons.groups,
                  onPressed: () => parent++),
              badges: const [Text('Official')],
              meta: const [
                DetailMeta(icon: Icons.event, text: 'Saturday 14 November'),
                DetailMeta(icon: Icons.place, text: 'Art Museum steps'),
              ],
              cta: HeroCta(
                  key: const ValueKey('join'),
                  label: 'Join the club',
                  onPressed: () => joined++,
                  secondary:
                      TextButton(onPressed: () {}, child: const Text('Invite'))),
            ),
          ]),
        ),
        scale: 2,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Riverside Running Club'));
      await tester.ensureVisible(find.byKey(const ValueKey('join')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('join')));
      expect((parent, joined), (1, 1));
      expect(tester.getSize(find.byKey(const ValueKey('join'))).width,
          320 - 2 * AppInsets.gutter,
          reason: 'the primary action is full width');
    });

    testWidgets('a busy action is disabled and keeps its label',
        (tester) async {
      await tester.pumpWidget(_app(
        DetailPage(
          title: 'Club',
          body: ListView(children: [
            DetailHero(
              title: 'Club',
              cta: HeroCta(
                  key: const ValueKey('join'),
                  label: 'Joining…',
                  busy: true,
                  onPressed: () {}),
            ),
          ]),
        ),
      ));
      final button =
          tester.widget<FilledButton>(find.byKey(const ValueKey('join')));
      expect(button.onPressed, isNull);
      expect(find.text('Joining…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('a root page header wraps its title beside its actions',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      Scaffold(
        body: PageHeader(
          title: 'Aujourd’hui et demain',
          actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert))],
        ),
      ),
      scale: 2,
    ));
    expect(tester.takeException(), isNull);
    final title = find.text('Aujourd’hui et demain');
    expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
        isFalse);
    expect(find.bySemanticsLabel('Aujourd’hui et demain'), findsOneWidget);
  });
}
