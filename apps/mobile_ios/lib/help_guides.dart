import 'dart:convert';

/// In-app help guides — the pure model behind the Help screens.
///
/// The source of truth is web: one TypeScript file per guide under
/// `apps/web/src/lib/help/guides/`, typed by `types.ts` in the folder above.
/// `scripts/gen_help_guides.mjs` writes them, with their translations laid
/// over them, to `assets/help/guides.<locale>.json` as one JSON array per
/// locale, and this file reads that array. Nothing here throws on
/// bad input: a guide missing a required field is dropped, an unknown block
/// type is skipped, and markup that does not parse renders as the text it is.
/// Help is an auxiliary surface — a malformed guide must never cost the app.

/// One inline block of a guide section.
sealed class GuideBlock {
  const GuideBlock();
}

class GuideParagraph extends GuideBlock {
  const GuideParagraph(this.text);
  final String text;
}

class GuideSteps extends GuideBlock {
  const GuideSteps(this.items);
  final List<String> items;
}

class GuideList extends GuideBlock {
  const GuideList(this.items);
  final List<String> items;
}

enum GuideNoteTone { tip, caution }

class GuideNote extends GuideBlock {
  const GuideNote(this.tone, this.text);
  final GuideNoteTone tone;
  final String text;
}

class GuideSection {
  const GuideSection({required this.heading, required this.blocks});
  final String heading;
  final List<GuideBlock> blocks;
}

/// The guide categories, in the order the Help home lists them.
const List<String> guideCategoryOrder = [
  'races',
  'paid-classes',
  'instructors',
  'clubs',
  'running',
  'account',
];

/// Every audience a guide may name, in the order the filter offers them.
const List<String> guideAudiences = [
  'everyone',
  'runner',
  'organiser',
  'participant',
  'spectator',
  'instructor',
  'club-admin',
];

class Guide {
  const Guide({
    required this.id,
    required this.title,
    required this.summary,
    required this.kind,
    required this.category,
    required this.audience,
    required this.requires,
    required this.platforms,
    required this.routes,
    required this.sections,
    required this.related,
    this.lang = 'en',
  });

  final String id;

  /// The language [title], [summary] and [sections] are in: the app's locale
  /// tag when the guide is translated, `en` when it fell back to English.
  final String lang;
  final String title;
  final String summary;
  final String kind;
  final String category;
  final List<String> audience;
  final List<String> requires;
  final List<String> platforms;
  final List<String> routes;
  final List<GuideSection> sections;
  final List<String> related;

  /// Parses one guide, or returns null when a required field is missing or
  /// the wrong shape. Optional lists default to empty.
  static Guide? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _string(json['id']);
    final title = _string(json['title']);
    final rawSections = json['sections'];
    if (id == null || title == null || rawSections is! List) return null;
    final sections = <GuideSection>[for (final s in rawSections) ?_section(s)];
    return Guide(
      id: id,
      title: title,
      summary: _string(json['summary']) ?? '',
      kind: _string(json['kind']) ?? 'how-to',
      category: _string(json['category']) ?? '',
      audience: _strings(json['audience']),
      requires: _strings(json['requires']),
      platforms: _strings(json['platforms']),
      routes: _strings(json['routes']),
      sections: sections,
      related: _strings(json['related']),
      lang: _string(json['lang']) ?? 'en',
    );
  }

  /// Every word a search can match in the body, markup removed.
  String get bodyText => [
    for (final s in sections) ...[
      for (final b in s.blocks)
        switch (b) {
          GuideParagraph(:final text) => plainHelpText(text),
          GuideNote(:final text) => plainHelpText(text),
          GuideSteps(:final items) => items.map(plainHelpText).join(' '),
          GuideList(:final items) => items.map(plainHelpText).join(' '),
        },
    ],
  ].join(' ');
}

String? _string(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

List<String> _strings(Object? v) =>
    v is List ? [for (final e in v) ?_string(e)] : const [];

GuideSection? _section(Object? json) {
  if (json is! Map) return null;
  final heading = _string(json['heading']);
  final rawBlocks = json['blocks'];
  if (heading == null || rawBlocks is! List) return null;
  return GuideSection(
    heading: heading,
    blocks: [for (final b in rawBlocks) ?_block(b)],
  );
}

GuideBlock? _block(Object? json) {
  if (json is! Map) return null;
  switch (json['type']) {
    case 'p':
      final text = _string(json['text']);
      return text == null ? null : GuideParagraph(text);
    case 'steps':
      final items = _strings(json['items']);
      return items.isEmpty ? null : GuideSteps(items);
    case 'list':
      final items = _strings(json['items']);
      return items.isEmpty ? null : GuideList(items);
    case 'note':
      final text = _string(json['text']);
      final tone = switch (json['tone']) {
        'tip' => GuideNoteTone.tip,
        'caution' => GuideNoteTone.caution,
        _ => null,
      };
      return text == null || tone == null ? null : GuideNote(tone, text);
    default:
      return null;
  }
}

/// A run of guide text with the styling and link the markup gave it.
class HelpSpan {
  const HelpSpan(
    this.text, {
    this.strong = false,
    this.emphasis = false,
    this.guideId,
    this.route,
  });

  final String text;
  final bool strong;
  final bool emphasis;

  /// Set for `[[guide:<id>|label]]`.
  final String? guideId;

  /// Set for `[[route:<route id>|label]]` — a SvelteKit route id.
  final String? route;

  bool get isLink => guideId != null || route != null;

  @override
  bool operator ==(Object other) =>
      other is HelpSpan &&
      other.text == text &&
      other.strong == strong &&
      other.emphasis == emphasis &&
      other.guideId == guideId &&
      other.route == route;

  @override
  int get hashCode => Object.hash(text, strong, emphasis, guideId, route);

  @override
  String toString() =>
      'HelpSpan(${jsonEncode(text)}'
      '${strong ? ', strong' : ''}${emphasis ? ', emphasis' : ''}'
      '${guideId != null ? ', guide: $guideId' : ''}'
      '${route != null ? ', route: $route' : ''})';
}

final _link = RegExp(r'^(guide|route):([^|]+)\|(.+)$');

/// Splits guide markup into styled spans.
///
/// The contract's four forms are `**label**`, `*emphasis*`,
/// `[[guide:<id>|label]]` and `[[route:<route id>|label]]`. A link may sit
/// inside bold or emphasis; a link label is literal. Anything that does not
/// close, or closes on nothing, is kept as the characters it was.
List<HelpSpan> tokenizeHelpMarkup(String source) =>
    _merge(_parse(source, strong: false, emphasis: false));

/// [source] with its markup removed — what a search or a screen reader gets.
String plainHelpText(String source) =>
    tokenizeHelpMarkup(source).map((s) => s.text).join();

List<HelpSpan> _parse(
  String s, {
  required bool strong,
  required bool emphasis,
}) {
  final out = <HelpSpan>[];
  final text = StringBuffer();
  void flush() {
    if (text.isEmpty) return;
    out.add(HelpSpan(text.toString(), strong: strong, emphasis: emphasis));
    text.clear();
  }

  var i = 0;
  while (i < s.length) {
    if (s.startsWith('[[', i)) {
      final close = s.indexOf(']]', i + 2);
      final m = close < 0 ? null : _link.firstMatch(s.substring(i + 2, close));
      final target = m?.group(2)!.trim() ?? '';
      final label = m?.group(3)!.trim() ?? '';
      if (m != null && target.isNotEmpty && label.isNotEmpty) {
        flush();
        final isGuide = m.group(1) == 'guide';
        out.add(
          HelpSpan(
            label,
            strong: strong,
            emphasis: emphasis,
            guideId: isGuide ? target : null,
            route: isGuide ? null : target,
          ),
        );
        i = close + 2;
        continue;
      }
      text.write('[[');
      i += 2;
      continue;
    }
    if (!strong && s.startsWith('**', i)) {
      final close = s.indexOf('**', i + 2);
      if (close > i + 2) {
        flush();
        out.addAll(
          _parse(s.substring(i + 2, close), strong: true, emphasis: emphasis),
        );
        i = close + 2;
        continue;
      }
      text.write('**');
      i += 2;
      continue;
    }
    if (!emphasis && s[i] == '*' && !s.startsWith('**', i)) {
      final close = s.indexOf('*', i + 1);
      final inner = close > i + 1 ? s.substring(i + 1, close) : '';
      if (inner.isNotEmpty &&
          inner.trim() == inner &&
          !s.startsWith('**', close)) {
        flush();
        out.addAll(_parse(inner, strong: strong, emphasis: true));
        i = close + 1;
        continue;
      }
    }
    text.write(s[i]);
    i++;
  }
  flush();
  return out;
}

List<HelpSpan> _merge(List<HelpSpan> spans) {
  final out = <HelpSpan>[];
  for (final s in spans) {
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        !last.isLink &&
        !s.isLink &&
        last.strong == s.strong &&
        last.emphasis == s.emphasis) {
      out[out.length - 1] = HelpSpan(
        last.text + s.text,
        strong: s.strong,
        emphasis: s.emphasis,
      );
    } else {
      out.add(s);
    }
  }
  return out;
}

/// The mobile surface a web route id opens.
///
/// A guide names screens by their SvelteKit route id because web is the
/// source of truth. Mobile has no URL router, so each id is mapped to an
/// INTENT the shell resolves with the dependencies it already holds (the same
/// seam as `SettingsDestination`, decisions § 710). A guide link cannot carry
/// a club slug or an event id, so a route addressing one entity opens the list
/// that entity is found in.
enum HelpDestination {
  clubs,
  races,
  runs,
  notifications,
  integrations,
  preferences,
  safety,
  account,
  pro,
}

/// Web route id → the mobile destination a `[[route:...]]` link opens. A route
/// not listed here renders as plain text: a link that goes nowhere is worse
/// than no link. Every key must exist under `apps/web/src/routes`, which
/// `help_guides_test.dart` checks against the tree.
const Map<String, HelpDestination> helpRouteToScreen = {
  '/clubs': HelpDestination.clubs,
  '/clubs/[slug]': HelpDestination.clubs,
  '/clubs/[slug]/events/[id]': HelpDestination.clubs,
  '/live/event/[id]/[instance]': HelpDestination.clubs,
  '/races': HelpDestination.races,
  '/runs': HelpDestination.runs,
  '/runs/[id]': HelpDestination.runs,
  '/notifications': HelpDestination.notifications,
  '/settings/integrations': HelpDestination.integrations,
  '/settings/notifications': HelpDestination.preferences,
  '/settings/preferences': HelpDestination.preferences,
  '/settings/safety': HelpDestination.safety,
  '/settings/account': HelpDestination.account,
  '/settings/upgrade': HelpDestination.pro,
};

/// Every guide, with the lookups the Help screens need.
class HelpLibrary {
  HelpLibrary(List<Guide> guides)
    : guides = List.unmodifiable(guides),
      _byId = {for (final g in guides) g.id: g};

  final List<Guide> guides;
  final Map<String, Guide> _byId;

  /// Parses the generated JSON array. Null when the document is not a JSON
  /// array at all; individual malformed guides are dropped, not fatal.
  static HelpLibrary? parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    return HelpLibrary([for (final g in decoded) ?Guide.fromJson(g)]);
  }

  Guide? byId(String id) => _byId[id];

  /// Guides whose `routes` include any of [routes] — the same lookup as web's
  /// `guidesForRoute`, widened to a set because one mobile screen can stand
  /// for several web routes. [audience] narrows to guides written for that
  /// reader (or for everyone).
  List<Guide> guidesForRoutes(Iterable<String> routes, {String? audience}) {
    final wanted = routes.toSet();
    return _ordered([
      for (final g in guides)
        if (g.routes.any(wanted.contains) && matchesAudience(g, audience)) g,
    ]);
  }

  /// [category]'s guides in display order: getting-started guides first, then
  /// by title.
  List<Guide> inCategory(String category, {String? audience}) => _ordered([
    for (final g in guides)
      if (g.category == category && matchesAudience(g, audience)) g,
  ]);

  /// Guides matching every word of [query], best first.
  ///
  /// A word scores most in the title, then the summary, then a section
  /// heading, then the body; a title word that STARTS with it scores extra, so
  /// "race" ranks "Racing an event" above a guide that only mentions races.
  /// A guide missing any one word is not a result.
  List<Guide> search(String query, {String? audience}) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return const [];
    final scored = <(Guide, int)>[];
    for (final g in guides) {
      if (!matchesAudience(g, audience)) continue;
      final title = g.title.toLowerCase();
      final titleWords = title.split(RegExp(r'[^a-z0-9]+'));
      final summary = g.summary.toLowerCase();
      final headings = g.sections.map((s) => s.heading.toLowerCase()).join(' ');
      final body = g.bodyText.toLowerCase();
      var total = 0;
      for (final t in terms) {
        var score = 0;
        if (title.contains(t)) score += 8;
        if (titleWords.any((w) => w.startsWith(t))) score += 4;
        if (summary.contains(t)) score += 4;
        if (headings.contains(t)) score += 2;
        if (body.contains(t)) score += 1;
        if (score == 0) {
          total = 0;
          break;
        }
        total += score;
      }
      if (total > 0) scored.add((g, total));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : a.$1.title.compareTo(b.$1.title);
    });
    return [for (final s in scored) s.$1];
  }

  static List<Guide> _ordered(List<Guide> list) => list
    ..sort((a, b) {
      final aStart = a.kind == 'start' ? 0 : 1;
      final bStart = b.kind == 'start' ? 0 : 1;
      return aStart != bStart
          ? aStart.compareTo(bStart)
          : a.title.compareTo(b.title);
    });
}

/// Whether [guide] is written for [audience]. A null audience is "all", and a
/// guide for everyone matches every audience.
bool matchesAudience(Guide guide, String? audience) =>
    audience == null ||
    guide.audience.contains(audience) ||
    guide.audience.contains('everyone');
