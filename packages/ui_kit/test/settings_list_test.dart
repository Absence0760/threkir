import 'package:flutter/material.dart';
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
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('ListRow', () {
    testWidgets('nav: chevron, icon and subtitle; tap fires', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        ListRow.nav(
          icon: Icons.lock,
          title: 'Privacy',
          subtitle: 'Who sees your runs',
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.text('Who sees your runs'), findsOneWidget);
      await tester.tap(find.text('Privacy'));
      expect(taps, 1);
    });

    testWidgets('nav with a null onTap is disabled, not a dead tap',
        (tester) async {
      await _pump(tester, const ListRow.nav(title: 'Gear', subtitle: 'why'));
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
    });

    testWidgets('nav external swaps the chevron for open-in-new',
        (tester) async {
      await _pump(
        tester,
        ListRow.nav(title: 'Terms', external: true, onTap: () {}),
      );
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('value: the value is the subtitle, the hint a second line',
        (tester) async {
      await _pump(
        tester,
        ListRow.value(
          title: 'Pace format',
          value: 'min/km',
          hint: 'Automatic is Detailed',
          onTap: () {},
        ),
      );
      expect(find.text('min/km'), findsOneWidget);
      expect(find.text('Automatic is Detailed'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byType(ListTile)).isThreeLine,
          isTrue);
    });

    testWidgets('value with enabled false is disabled even with a tap',
        (tester) async {
      await _pump(
        tester,
        ListRow.value(
          title: 'Week starts',
          value: 'Monday',
          enabled: false,
          onTap: () {},
        ),
      );
      expect(tester.widget<ListTile>(find.byType(ListTile)).enabled, isFalse);
    });

    testWidgets('info sits before the chevron and is its own target',
        (tester) async {
      var info = 0;
      var row = 0;
      await _pump(
        tester,
        ListRow.value(
          title: 'Target pace',
          value: 'Off',
          onTap: () => row++,
          info: IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () => info++,
          ),
        ),
      );
      final infoX = tester.getCenter(find.byIcon(Icons.info_outline)).dx;
      final chevronX = tester.getCenter(find.byIcon(Icons.chevron_right)).dx;
      expect(infoX, lessThan(chevronX));
      await tester.tap(find.byIcon(Icons.info_outline));
      expect(info, 1);
      expect(row, 0);
    });

    testWidgets('toggle: a switch that reports the new value', (tester) async {
      bool? got;
      await _pump(
        tester,
        ListRow.toggle(
          title: 'Dark mode',
          value: false,
          onChanged: (v) => got = v,
        ),
      );
      await tester.tap(find.byType(Switch));
      expect(got, isTrue);
    });

    testWidgets('toggle with a null onChanged is disabled', (tester) async {
      await _pump(
        tester,
        const ListRow.toggle(title: 'Dim', value: true, onChanged: null),
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
    });
  });

  group('SettingsList', () {
    List<SettingsSection> sections(int groups, int rows) => [
          for (var g = 0; g < groups; g++)
            SettingsSection(
              label: 'Group $g',
              rows: [
                for (var r = 0; r < rows; r++)
                  ListRow.nav(title: 'Row $g.$r', onTap: () {}),
              ],
            ),
        ];

    testWidgets('each group is one pinned eyebrow over its own rows',
        (tester) async {
      await _pump(tester, SettingsList(sections: sections(3, 4)),
          size: const Size(360, 4000));
      final headers = tester
          .widgetList<SliverPersistentHeader>(
              find.byType(SliverPersistentHeader))
          .toList();
      expect(headers, hasLength(3));
      expect(headers.every((h) => h.pinned), isTrue);
      expect(find.byType(SectionHeader), findsNWidgets(3));
    });

    testWidgets('pinned eyebrows do not stack while scrolling',
        (tester) async {
      await _pump(tester, SettingsList(sections: sections(4, 8)));
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      final top = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      final atTop = find.byType(SectionHeader).evaluate().where((e) {
        final box = e.renderObject! as RenderBox;
        final dy = box.localToGlobal(Offset.zero).dy;
        return dy >= top - 0.5 && dy < top + 30;
      });
      expect(atTop.length, lessThanOrEqualTo(1));
    });

    testWidgets('a section with no rows is left out, eyebrow and all',
        (tester) async {
      await _pump(
        tester,
        const SettingsList(sections: [
          SettingsSection(label: 'Empty', rows: []),
          SettingsSection(label: 'Full', rows: [Text('one')]),
        ]),
      );
      expect(find.text('EMPTY'), findsNothing);
      expect(find.text('FULL'), findsOneWidget);
    });

    testWidgets('header first, footer under its group', (tester) async {
      await _pump(
        tester,
        const SettingsList(
          header: [Text('head')],
          sections: [
            SettingsSection(
                label: 'G', rows: [Text('row')], footer: 'foot note'),
          ],
        ),
      );
      final head = tester.getTopLeft(find.text('head')).dy;
      final row = tester.getTopLeft(find.text('row')).dy;
      final foot = tester.getTopLeft(find.text('foot note')).dy;
      expect(head, lessThan(row));
      expect(row, lessThan(foot));
    });

    testWidgets('the eyebrow is not clipped at 2x text', (tester) async {
      await _pump(tester, SettingsList(sections: sections(2, 2)),
          size: const Size(320, 640), textScale: 2.0);
      expect(tester.takeException(), isNull);
      final label = tester.getRect(find.text('GROUP 0'));
      final header = tester.getRect(find
          .descendant(
            of: find.byType(SliverPersistentHeader).first,
            matching: find.byType(Container),
          )
          .first);
      expect(label.bottom, lessThanOrEqualTo(header.bottom + 0.5));
    });
  });
}
