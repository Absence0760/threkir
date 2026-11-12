import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/help_guides.dart';
import '../lib/help_loader.dart';
import '../lib/l10n/locale_support.dart';

/// An asset bundle holding exactly [files].
class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

String _guides(String lang, String title) => jsonEncode([
  {'id': 'g', 'lang': lang, 'title': title, 'sections': []},
]);

HelpLibrary _fixture() => HelpLibrary.parse(
  File('test/fixtures/help_guides.json').readAsStringSync(),
)!;

void main() {
  group('tokenizeHelpMarkup', () {
    test('plain text is one span', () {
      expect(tokenizeHelpMarkup('Just text.'), [const HelpSpan('Just text.')]);
    });

    test('bold is a UI label', () {
      expect(tokenizeHelpMarkup('Tap **Start race** now'), [
        const HelpSpan('Tap '),
        const HelpSpan('Start race', strong: true),
        const HelpSpan(' now'),
      ]);
    });

    test('single asterisks are emphasis', () {
      expect(tokenizeHelpMarkup('the *gun clock* runs'), [
        const HelpSpan('the '),
        const HelpSpan('gun clock', emphasis: true),
        const HelpSpan(' runs'),
      ]);
    });

    test('a guide link carries its id and label', () {
      expect(tokenizeHelpMarkup('See [[guide:following-live|following]].'), [
        const HelpSpan('See '),
        const HelpSpan('following', guideId: 'following-live'),
        const HelpSpan('.'),
      ]);
    });

    test('a route link carries its route id, brackets and all', () {
      expect(
        tokenizeHelpMarkup('[[route:/clubs/[slug]/events/[id]|the event]]'),
        [const HelpSpan('the event', route: '/clubs/[slug]/events/[id]')],
      );
    });

    test('a link inside bold keeps the bold', () {
      expect(tokenizeHelpMarkup('**Open [[route:/races|Races]] first**'), [
        const HelpSpan('Open ', strong: true),
        const HelpSpan('Races', strong: true, route: '/races'),
        const HelpSpan(' first', strong: true),
      ]);
    });

    test('emphasis nests inside bold', () {
      expect(tokenizeHelpMarkup('**a *b* c**'), [
        const HelpSpan('a ', strong: true),
        const HelpSpan('b', strong: true, emphasis: true),
        const HelpSpan(' c', strong: true),
      ]);
    });

    test('a link label is literal, not markup', () {
      expect(tokenizeHelpMarkup('[[guide:x|**not bold**]]'), [
        const HelpSpan('**not bold**', guideId: 'x'),
      ]);
    });

    group('malformed input renders as the text it is', () {
      for (final source in [
        'an **unclosed bold',
        'an *unclosed emphasis',
        '5 * 3 * 2',
        'empty **** bold',
        '[[guide:missing-label]]',
        '[[route:|label]]',
        '[[video:x|label]]',
        '[[guide:x|label',
        'stray ]] and [[',
        '***',
        '',
      ]) {
        test(source.isEmpty ? '(empty)' : source, () {
          final spans = tokenizeHelpMarkup(source);
          expect(spans.map((s) => s.text).join(), source);
          expect(spans.where((s) => s.isLink), isEmpty);
          expect(spans.where((s) => s.strong || s.emphasis), isEmpty);
        });
      }
    });

    test('a malformed link beside a good one keeps the good one', () {
      final spans = tokenizeHelpMarkup('[[guide:bad]] then [[guide:ok|Ok]]');
      expect(spans.last, const HelpSpan('Ok', guideId: 'ok'));
      expect(
        plainHelpText('[[guide:bad]] then [[guide:ok|Ok]]'),
        '[[guide:bad]] then Ok',
      );
    });

    test('plainHelpText strips every form', () {
      expect(
        plainHelpText('Tap **Go**, *then* [[guide:a|read]] [[route:/x|this]]'),
        'Tap Go, then read this',
      );
    });
  });

  group('parsing', () {
    test('drops a guide with no title and keeps the rest', () {
      final lib = _fixture();
      expect(lib.guides.map((g) => g.id), isNot(contains('no-title')));
      expect(lib.guides, hasLength(5));
    });

    test('missing optional fields default to empty', () {
      final g = Guide.fromJson({
        'id': 'bare',
        'title': 'Bare',
        'sections': [],
      })!;
      expect(g.summary, '');
      expect(g.requires, isEmpty);
      expect(g.routes, isEmpty);
      expect(g.related, isEmpty);
      expect(g.audience, isEmpty);
      expect(g.platforms, isEmpty);
      expect(g.lang, 'en', reason: 'a guide that names no language is English');
    });

    test('lang says which language the guide text is in', () {
      final g = Guide.fromJson({
        'id': 'g',
        'lang': 'pt-BR',
        'title': 'Título',
        'sections': [],
      })!;
      expect(g.lang, 'pt-BR');
    });

    test('an unknown block type is skipped, known ones keep their order', () {
      final g = _fixture().byId('racing-an-event')!;
      final blocks = g.sections.single.blocks;
      expect(blocks.map((b) => b.runtimeType), [
        GuideParagraph,
        GuideSteps,
        GuideList,
        GuideNote,
        GuideNote,
      ]);
      expect((blocks[3] as GuideNote).tone, GuideNoteTone.tip);
      expect((blocks[4] as GuideNote).tone, GuideNoteTone.caution);
    });

    test('a note with an unknown tone and a block of the wrong shape drop', () {
      final g = Guide.fromJson({
        'id': 'x',
        'title': 'X',
        'sections': [
          {
            'heading': 'H',
            'blocks': [
              {'type': 'note', 'tone': 'shout', 'text': 'loud'},
              {'type': 'steps', 'items': 'not a list'},
              {'type': 'p'},
              'not a block',
              {'type': 'p', 'text': 'kept'},
            ],
          },
          {'heading': 'no blocks'},
        ],
      })!;
      expect(g.sections, hasLength(1));
      expect(g.sections.single.blocks, hasLength(1));
    });

    test('non-string list entries are ignored', () {
      final g = Guide.fromJson({
        'id': 'x',
        'title': 'X',
        'audience': ['runner', 3, null, ''],
        'sections': [],
      })!;
      expect(g.audience, ['runner']);
    });

    test('a document that is not a JSON array is unavailable', () {
      expect(HelpLibrary.parse('{"id": "x"}'), isNull);
      expect(HelpLibrary.parse('not json'), isNull);
      expect(HelpLibrary.parse('[]')!.guides, isEmpty);
    });
  });

  group('lookups', () {
    test(
      'guidesForRoutes matches web guidesForRoute, getting-started first',
      () {
        final lib = _fixture();
        expect(
          lib.guidesForRoutes(['/clubs/[slug]/events/[id]']).map((g) => g.id),
          ['racing-an-event', 'paid-class-setup'],
        );
        expect(lib.guidesForRoutes(['/live/[id]']).map((g) => g.id), [
          'following-live',
        ]);
        expect(lib.guidesForRoutes(['/nowhere']), isEmpty);
      },
    );

    test('guidesForRoutes narrows by audience', () {
      expect(
        _fixture()
            .guidesForRoutes([
              '/clubs/[slug]/events/[id]',
            ], audience: 'participant')
            .map((g) => g.id),
        ['racing-an-event'],
      );
    });

    test('a guide for everyone matches every audience', () {
      final g = _fixture().byId('connect-strava')!;
      expect(matchesAudience(g, 'spectator'), isTrue);
      expect(matchesAudience(g, null), isTrue);
    });

    test('inCategory lists getting-started guides first', () {
      expect(_fixture().inCategory('races').map((g) => g.id), [
        'racing-an-event',
        'following-live',
      ]);
    });
  });

  group('search', () {
    test('ranks title over summary over body', () {
      expect(_fixture().search('race').map((g) => g.id), [
        'racing-an-event',
        'following-live',
        'paid-class-setup',
      ]);
    });

    test('a title hit outranks a summary hit', () {
      expect(_fixture().search('live').first.id, 'following-live');
    });

    test('every word must match', () {
      expect(_fixture().search('strava connect').map((g) => g.id), [
        'connect-strava',
      ]);
      expect(_fixture().search('race strava'), isEmpty);
    });

    test('searches the body with markup removed', () {
      expect(_fixture().search('gun clock').map((g) => g.id), [
        'racing-an-event',
      ]);
      expect(_fixture().search('route:'), isEmpty);
    });

    test('respects the audience filter', () {
      expect(
        _fixture().search('race', audience: 'spectator').map((g) => g.id),
        ['following-live'],
      );
    });

    test('a blank query has no results', () {
      expect(_fixture().search('   '), isEmpty);
    });
  });

  group('helpRouteToScreen', () {
    test('maps the surfaces a guide most often names', () {
      expect(
        helpRouteToScreen['/clubs/[slug]/events/[id]'],
        HelpDestination.clubs,
      );
      expect(
        helpRouteToScreen['/live/event/[id]/[instance]'],
        HelpDestination.clubs,
      );
      expect(helpRouteToScreen['/races'], HelpDestination.races);
      expect(
        helpRouteToScreen['/settings/integrations'],
        HelpDestination.integrations,
      );
      expect(
        helpRouteToScreen['/notifications'],
        HelpDestination.notifications,
      );
      expect(helpRouteToScreen['/runs/[id]'], HelpDestination.runs);
      expect(helpRouteToScreen['/no/such/route'], isNull);
    });

    test('every mapped route id exists under apps/web/src/routes', () {
      final routes = Directory('../web/src/routes');
      expect(
        routes.existsSync(),
        isTrue,
        reason: 'run from the app package root, beside apps/web',
      );
      final missing = [
        for (final id in helpRouteToScreen.keys)
          if (!File('${routes.path}$id/+page.svelte').existsSync()) id,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'a mapped route id names no web page — the guide link it '
            'serves can never be written against the contract',
      );
    });
  });

  group('per-locale guides', () {
    test('helpLocaleTag names the asset for each app locale', () {
      expect(helpLocaleTag(const Locale('de')), 'de');
      expect(helpLocaleTag(const Locale('pt', 'PT')), 'pt-PT');
      expect(helpLocaleTag(const Locale('pt')), 'pt-PT');
      expect(helpLocaleTag(const Locale('pt', 'BR')), 'pt-BR');
      expect(helpLocaleTag(const Locale('fr', 'CA')), 'fr');
      expect(helpGuidesAsset('ja'), 'assets/help/guides.ja.json');
    });

    test('loads the locale file, and English when it is missing or empty', () async {
      final bundle = _MapBundle({
        helpGuidesAsset('en'): _guides('en', 'Guide'),
        helpGuidesAsset('de'): _guides('de', 'Anleitung'),
        helpGuidesAsset('fr'): '[]',
      });
      Future<String?> titleIn(String tag) async =>
          (await loadHelpLibraryFromAssets(
            bundle: bundle,
            localeTag: tag,
          ))?.guides.single.title;
      expect(await titleIn('de'), 'Anleitung');
      expect(await titleIn('ja'), 'Guide');
      expect(await titleIn('fr'), 'Guide');
      expect(await titleIn('en'), 'Guide');
      expect(
        await loadHelpLibraryFromAssets(
          bundle: _MapBundle({}),
          localeTag: 'de',
        ),
        isNull,
      );
    });

    test('every app locale ships a guide file holding every English guide', () {
      final english = HelpLibrary.parse(
        File('assets/help/guides.en.json').readAsStringSync(),
      )!;
      expect(english.guides, isNotEmpty);
      for (final locale in supportedLocales) {
        final tag = localeToTag(locale);
        final file = File(helpGuidesAsset(tag));
        expect(file.existsSync(), isTrue, reason: '${file.path} is missing');
        final library = HelpLibrary.parse(file.readAsStringSync())!;
        expect(
          library.guides.map((g) => g.id).toSet(),
          english.guides.map((g) => g.id).toSet(),
          reason: '${file.path} must hold every guide, translated or not',
        );
        for (final g in library.guides) {
          expect(
            g.lang == tag || g.lang == 'en',
            isTrue,
            reason: '${file.path}: ${g.id} is in ${g.lang}',
          );
        }
      }
    });
  });
}
