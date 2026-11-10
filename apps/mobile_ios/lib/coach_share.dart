/// An AI Coach answer shared into the athlete-coach thread (issue #1215
/// Phase 3, migration 20271210001215).
///
/// The server is authoritative on what is sent: `share_coach_message` copies
/// the picked paragraphs out of the athlete's own answer, by index, so the
/// card's AI label always sits on AI text. This splits an answer the same way
/// the server does, and turns a card's text into a few typed blocks drawn as
/// text, never as markup (decisions § 110).
///
/// Mirror of `apps/web/src/lib/social/coach_share.ts`
/// (docs/architecture/parity_pairs.md).
library;

/// Every `direct_messages.kind` the CHECK admits.
const List<String> kDmKinds = ['text', 'coach_share', 'ai_assisted'];

/// Must equal the 4000-character cap share_coach_message enforces.
const int kCoachShareMaxChars = 4000;

/// A row's `kind`, read at the boundary. Anything unknown is drawn as text.
String parseDmKind(Object? raw) =>
    raw == 'coach_share' || raw == 'ai_assisted' ? raw! as String : 'text';

final RegExp _edge = RegExp(r'^[ \t\n\r]+|[ \t\n\r]+$');

/// The paragraphs of an answer, as `private.coach_answer_paragraphs` splits
/// them: CRLF read as LF, split on a line holding only spaces or tabs, each
/// part trimmed of spaces, tabs and line breaks, empty parts dropped.
List<String> coachAnswerParagraphs(String content) => content
    .replaceAll('\r\n', '\n')
    .split(RegExp(r'\n[ \t]*\n'))
    .map((p) => p.replaceAll(_edge, ''))
    .where((p) => p.isNotEmpty)
    .toList();

/// The picked paragraphs, in answer order, as the card will hold them.
String coachShareExcerpt(List<String> paragraphs, Iterable<int> picked) {
  final idx = picked.toSet().where((i) => i >= 0 && i < paragraphs.length).toList()..sort();
  return idx.map((i) => paragraphs[i]).join('\n\n');
}

enum SharedSpanStyle { plain, bold, italic, code }

class SharedSpan {
  const SharedSpan(this.text, this.style);
  final String text;
  final SharedSpanStyle style;

  @override
  bool operator ==(Object other) => other is SharedSpan && other.text == text && other.style == style;

  @override
  int get hashCode => Object.hash(text, style);

  @override
  String toString() => 'SharedSpan($text, ${style.name})';
}

enum SharedBlockType { paragraph, heading, bullet, ordered }

class SharedBlock {
  const SharedBlock(this.type, this.spans, {this.marker});
  final SharedBlockType type;
  final List<SharedSpan> spans;

  /// The item number, as `2.`, on an ordered item; null otherwise.
  final String? marker;

  @override
  bool operator ==(Object other) =>
      other is SharedBlock &&
      other.type == type &&
      other.marker == marker &&
      other.spans.length == spans.length &&
      Iterable.generate(spans.length).every((i) => other.spans[i] == spans[i]);

  @override
  int get hashCode => Object.hash(type, marker, Object.hashAll(spans));

  @override
  String toString() => 'SharedBlock(${type.name}, $marker, $spans)';
}

final RegExp _link = RegExp(r'^\[([^\]\n]+)\]\(([^)\s]*)\)');

/// Inline marks: `**bold**`, `*italic*` and `` `code` ``, not nested. A link
/// keeps its text and loses its target, so nothing in the card is clickable.
/// An unclosed mark is literal text.
List<SharedSpan> parseSharedInline(String line) {
  final out = <SharedSpan>[];
  final plain = StringBuffer();
  void push(String text, SharedSpanStyle style) {
    if (style == SharedSpanStyle.plain) {
      plain.write(text);
      return;
    }
    if (plain.isNotEmpty) out.add(SharedSpan(plain.toString(), SharedSpanStyle.plain));
    plain.clear();
    out.add(SharedSpan(text, style));
  }

  var i = 0;
  while (i < line.length) {
    final rest = line.substring(i);
    if (rest.startsWith('`')) {
      final end = line.indexOf('`', i + 1);
      if (end > i + 1) {
        push(line.substring(i + 1, end), SharedSpanStyle.code);
        i = end + 1;
        continue;
      }
    } else if (rest.startsWith('**')) {
      final end = line.indexOf('**', i + 2);
      if (end > i + 2) {
        push(line.substring(i + 2, end), SharedSpanStyle.bold);
        i = end + 2;
        continue;
      }
    } else if (rest.startsWith('*') && rest.length > 1 && rest[1] != ' ') {
      final end = line.indexOf('*', i + 1);
      if (end > i + 1 && line[end - 1] != ' ') {
        push(line.substring(i + 1, end), SharedSpanStyle.italic);
        i = end + 1;
        continue;
      }
    } else if (rest.startsWith('[')) {
      final link = _link.firstMatch(rest);
      if (link != null) {
        push(link.group(1)!, SharedSpanStyle.plain);
        i += link.group(0)!.length;
        continue;
      }
    }
    push(line[i], SharedSpanStyle.plain);
    i += 1;
  }
  if (plain.isNotEmpty) out.add(SharedSpan(plain.toString(), SharedSpanStyle.plain));
  return out;
}

final RegExp _bullet = RegExp(r'^[-*+][ \t]+(.*)$');
final RegExp _ordered = RegExp(r'^(\d{1,3})[.)][ \t]+(.*)$');
final RegExp _heading = RegExp(r'^#{1,6}[ \t]+(.*)$');
final RegExp _quote = RegExp(r'^>[ \t]?(.*)$');

/// A card's text as blocks: list items, headings (drawn as bold lines), and
/// paragraphs whose single line breaks are kept. A quote marker is dropped,
/// since the whole card is already a quote.
List<SharedBlock> parseSharedMarkdown(String text) {
  final blocks = <SharedBlock>[];
  var para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    blocks.add(SharedBlock(SharedBlockType.paragraph, parseSharedInline(para.join('\n'))));
    para = <String>[];
  }

  for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
    final quoted = _quote.firstMatch(raw.trim());
    final line = (quoted != null ? quoted.group(1)! : raw).trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    final ordered = _ordered.firstMatch(line);
    final heading = _heading.firstMatch(line);
    if (bullet != null) {
      flush();
      blocks.add(SharedBlock(SharedBlockType.bullet, parseSharedInline(bullet.group(1)!)));
    } else if (ordered != null) {
      flush();
      blocks.add(SharedBlock(SharedBlockType.ordered, parseSharedInline(ordered.group(2)!),
          marker: '${ordered.group(1)}.'));
    } else if (heading != null) {
      flush();
      blocks.add(SharedBlock(SharedBlockType.heading, parseSharedInline(heading.group(1)!)));
    } else {
      para.add(line);
    }
  }
  flush();
  return blocks;
}
