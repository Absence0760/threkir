import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(360, 640),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: ListView(children: [child])),
      ),
    ),
  );
}

EdgeInsetsGeometry _innerPadding(WidgetTester tester, String text) {
  final pad = find
      .ancestor(of: find.text(text), matching: find.byType(Padding))
      .first;
  return tester.widget<Padding>(pad).padding;
}

void main() {
  group('ListCard', () {
    testWidgets(
      'pads its child with the card inset, dense with the dense one',
      (tester) async {
        await _pump(tester, const ListCard(child: Text('Body')));
        expect(_innerPadding(tester, 'Body'), AppInsets.card);

        await _pump(tester, const ListCard(dense: true, child: Text('Body')));
        expect(_innerPadding(tester, 'Body'), AppInsets.cardDense);
      },
    );

    testWidgets('flush has no padding of its own', (tester) async {
      await _pump(tester, const ListCard.flush(child: Text('Map')));
      expect(_innerPadding(tester, 'Map'), EdgeInsets.zero);
    });

    testWidgets('a tap and a long press reach the callbacks', (tester) async {
      var taps = 0;
      var holds = 0;
      await _pump(
        tester,
        ListCard.row(
          title: 'Morning loop',
          onTap: () => taps++,
          onLongPress: () => holds++,
        ),
      );
      await tester.tap(find.text('Morning loop'));
      await tester.longPress(find.text('Morning loop'));
      expect((taps, holds), (1, 1));
    });

    testWidgets(
      'the row is one button node; trailing and actions are not in it',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(
          tester,
          ListCard.row(
            title: 'Riverside 10k',
            subtitle: '12 Oct · 10 km',
            onTap: () {},
            trailing: IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share),
              onPressed: () {},
            ),
            actions: [TextButton(onPressed: () {}, child: const Text('Train'))],
          ),
        );
        final row = find.semantics
            .byLabel(RegExp('Riverside 10k'))
            .evaluate()
            .single;
        expect(row.label, contains('Riverside 10k'));
        expect(row.label, contains('12 Oct · 10 km'));
        expect(row.label, isNot(contains('Share')));
        expect(row.label, isNot(contains('Train')));
        expect(row, containsSemantics(isButton: true, hasTapAction: true));
        expect(find.byTooltip('Share'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('a semantic label replaces the texts it covers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        ListCard(
          semanticLabel: '5.2 kilometre run, 12 October',
          onTap: () {},
          child: const Text('5.2 km'),
        ),
      );
      expect(
        find.bySemanticsLabel('5.2 kilometre run, 12 October'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('5.2 km'), findsNothing);
      handle.dispose();
    });

    testWidgets('selecting shows the selection glyph in the leading slot', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const ListCard.row(
          title: 'A',
          leading: Icon(Icons.route),
          selecting: true,
          selected: true,
        ),
      );
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byIcon(Icons.route), findsNothing);
      expect(
        find.semantics.byLabel(RegExp(r'^A$')).evaluate().single,
        containsSemantics(isSelected: true),
      );
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, isNotNull);

      await _pump(
        tester,
        const ListCard.row(
          title: 'A',
          leading: Icon(Icons.route),
          selecting: true,
        ),
      );
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a disabled card is a disabled button that ignores taps', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await _pump(
        tester,
        ListCard(
          semanticLabel: 'Half marathon',
          semanticHint: 'Starts Monday',
          enabled: false,
          onTap: () => taps++,
          child: const Text('Half'),
        ),
      );
      await tester.tap(find.text('Half'));
      expect(taps, 0);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Half marathon')),
        matchesSemantics(
          label: 'Half marathon',
          hint: 'Starts Monday',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          isFocusable: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('chevron is drawn but not read', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        ListCard.row(title: 'Gear', chevron: true, onTap: () {}),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a long title, a badge and a trailing value fit 320 dp at 2x', (
      tester,
    ) async {
      await _pump(
        tester,
        ListCard.row(
          title: 'Schwarzwald-Halbmarathon mit Bergwertung und Zielverpflegung',
          badge: const StatusPill(
            label: 'Abgeschlossen',
            foreground: Colors.green,
          ),
          subtitle: 'Sonntag, 12. Oktober · 21,1 km · Freiburg im Breisgau',
          leading: const Icon(Icons.flag),
          trailing: const Text('1:42:10'),
          chevron: true,
          onTap: () {},
          actions: [
            OutlinedButton(onPressed: () {}, child: const Text('Trainieren')),
            OutlinedButton(onPressed: () {}, child: const Text('Anmelden')),
          ],
        ),
        size: const Size(320, 640),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });

    group('the badge sits inline after the title (issue #1374)', () {
      const globe = Icon(Icons.public, key: Key('globe'), size: 16);
      // The owner's screenshot: a two-line route name with the public globe
      // alone on a third line under it.
      Future<void> pumpRoute(WidgetTester tester, String title,
              {double scale = 1, int maxLines = 2}) =>
          _pump(
            tester,
            ListCard.row(
              title: title,
              titleMaxLines: maxLines,
              badge: globe,
              subtitle: '21.32 km · 189 m',
              leading: const SizedBox(width: 64, height: 40),
              trailing: IconButton(
                  onPressed: () {}, icon: const Icon(Icons.star_border)),
              onTap: () {},
            ),
            size: const Size(320, 640),
            textScale: scale,
          );

      for (final scale in [1.0, 2.0]) {
        testWidgets('a title that wraps carries the badge on its last line, '
            'at ${scale}x', (tester) async {
          await pumpRoute(tester, 'Pocahontas Lakeview Loop', scale: scale);
          expect(tester.takeException(), isNull);
          final title = tester.getRect(find.text('Pocahontas Lakeview Loop'));
          final badge = tester.getRect(find.byKey(const Key('globe')));
          // One line of titleMedium (16 px, height 1.5) at this scale.
          final line = 16 * 1.5 * scale;
          expect(title.height, greaterThan(line * 1.5),
              reason: 'the title wraps, which is the case that broke');
          expect(badge.bottom, lessThanOrEqualTo(title.bottom + 0.5),
              reason: 'the badge sits inside the title block, not under it');
          expect(badge.top, greaterThanOrEqualTo(title.bottom - line - 0.5),
              reason: 'on the title\'s last line');
          expect(badge.left, greaterThan(title.left),
              reason: 'beside a word, never alone at the line start');
          expect(badge.right, lessThanOrEqualTo(title.right + 0.5));
        });
      }

      testWidgets('a title cut by the ellipsis keeps the badge', (tester) async {
        await pumpRoute(
            tester,
            'Pocahontas State Park Lakeview Loop by the Swift Creek Reservoir '
            'and back over the dam',
            scale: 2,
            maxLines: 2);
        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.textContaining('Pocahontas'));
        final badge = tester.getRect(find.byKey(const Key('globe')));
        expect(title.contains(badge.center), isTrue,
            reason: 'the badge is drawn inside the two lines');
      });

      testWidgets('the title is found and read as the title it is',
          (tester) async {
        final handle = tester.ensureSemantics();
        await pumpRoute(tester, 'Buttermilk Trail');
        expect(find.text('Buttermilk Trail'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Buttermilk Trail')),
            findsWidgets);
        handle.dispose();
      });
    });

    testWidgets('a wide leading or trailing is capped, not pushed off the row',
        (tester) async {
      await _pump(
        tester,
        ListCard.row(
          title: 'Parkrun',
          leading: const Text('Samstag, 12. Oktober 2026, 09:00'),
          trailing: const Text('Offizielle Quelle des Veranstalters'),
          onTap: () {},
        ),
        size: const Size(320, 640),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byType(Card)).width;
      expect(tester.getSize(find.text('Samstag, 12. Oktober 2026, 09:00')).width,
          lessThanOrEqualTo(card * ListCard.maxLeadingFraction));
      expect(
          tester.getSize(find.text('Offizielle Quelle des Veranstalters')).width,
          lessThanOrEqualTo(card * ListCard.maxTrailingFraction));
    });

    testWidgets('outline replaces the theme hairline', (tester) async {
      await _pump(
          tester, const ListCard(outline: Colors.teal, child: Text('Week')));
      final shape =
          tester.widget<Card>(find.byType(Card)).shape as RoundedRectangleBorder;
      expect(shape.side.color, Colors.teal);
    });
  });
}
