import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/help_guides.dart';
import '../lib/help_illustration.dart';
import '../lib/help_loader.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/help_screen.dart';

Guide _guideWith(List<Object?> blocks) => Guide.fromJson({
  'id': 'zones',
  'title': 'Zones',
  'summary': 'S',
  'sections': [
    {'heading': 'H', 'blocks': blocks},
  ],
})!;

void main() {
  test('the palette matches ILLUSTRATION_PALETTE in the web contract', () {
    final source = File(
      '../web/src/lib/help/illustration.ts',
    ).readAsStringSync();
    final block = RegExp(
      r'ILLUSTRATION_PALETTE = \{([^}]*)\}',
    ).firstMatch(source)!.group(1)!;
    final web = {
      for (final m in RegExp(
        r"'?([a-z-]+)'?: '#([0-9a-f]{6})'",
      ).allMatches(block))
        m.group(1)!: int.parse(m.group(2)!, radix: 16),
    };
    expect(web, helpIllustrationPalette);
  });

  test('an illustration block parses, and a bad id or empty alt drops it', () {
    final g = _guideWith([
      {'type': 'illustration', 'id': 'privacy-zones', 'alt': 'A circle.'},
      {'type': 'illustration', 'id': '../secrets', 'alt': 'x'},
      {'type': 'illustration', 'id': 'a', 'alt': ' '},
    ]);
    final blocks = g.sections.single.blocks;
    expect(blocks, hasLength(1));
    final ill = blocks.single as GuideIllustration;
    expect([ill.id, ill.alt], ['privacy-zones', 'A circle.']);
    expect(g.bodyText, contains('A circle.'));
  });

  test('the colour mapper swaps each placeholder and keeps its alpha', () {
    final mapper = HelpIllustrationColorMapper({
      'accent': const Color(0xff112233),
    });
    expect(
      mapper.substitute(null, 'path', 'stroke', const Color(0xffff00a1)),
      const Color(0xff112233),
    );
    final tinted = mapper.substitute(
      null,
      'circle',
      'fill',
      const Color(0x40ff00a1),
    );
    expect(tinted.toARGB32() & 0xffffff, 0x112233);
    expect(tinted.a, closeTo(0x40 / 255, 0.01));
    const other = Color(0xff00ff00);
    expect(mapper.substitute(null, 'path', 'fill', other), other);
  });

  test('every token has a theme colour, in light and dark', () {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      expect(
        helpIllustrationColors(theme).keys.toSet(),
        helpIllustrationPalette.keys.toSet(),
      );
    }
  });

  test('every shipped illustration compiles under flutter_svg', () async {
    final dir = Directory('assets/help/illustrations');
    final files = dir.existsSync()
        ? dir.listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))
        : const <File>[];
    for (final file in files) {
      final info = await vg.loadPicture(
        SvgStringLoader(
          file.readAsStringSync(),
          colorMapper: HelpIllustrationColorMapper(
            helpIllustrationColors(ThemeData.light()),
          ),
        ),
        null,
      );
      expect(
        info.size.aspectRatio,
        closeTo(helpIllustrationAspectRatio, 0.001),
        reason: file.path,
      );
      info.picture.dispose();
    }
  });

  testWidgets(
    'the guide screen renders an illustration with its alt as the label',
    (tester) async {
      final library = HelpLibrary([
        _guideWith([
          {'type': 'p', 'text': 'Before.'},
          {
            'type': 'illustration',
            'id': 'privacy-zones',
            'alt': 'A route starting inside a circle.',
          },
        ]),
      ]);
      helpLibraryLoader = (_) => Future.value(library);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GuideScreen(guideId: 'zones'),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('help-illustration-privacy-zones')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('A route starting inside a circle.'),
        findsOneWidget,
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      handle.dispose();
    },
  );
}
