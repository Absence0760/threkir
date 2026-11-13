// Source-scan guard for issue #666 C18: card-list separators.
//
// The finding read "8 dp everywhere except `clubs_screen.dart:236` (10)". The
// exception is three files, not one: `clubs_screen` and `plans_screen` at 10
// and `feed_screen` at 12, against nine lists at 8. Two sibling tabs of the
// same hub disagreeing by 2 dp is exactly the drift a reader cannot name but
// can feel when switching between them.
//
// A `Divider` separator is a different thing — a drawn rule, not a gap — and
// four lists use one deliberately, so this measures only the `SizedBox` form.

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _roots = ['lib'];
const _gap = 8;

final _sizedBoxSeparator = RegExp(
  r'separatorBuilder:\s*\([^)]*\)\s*=>\s*(?:const\s+)?SizedBox\(\s*height:\s*(\d+|AppInsets\.\w+|AppSpace\.\w+)',
  dotAll: true,
);

/// A separator written with a spacing token (issue #1374) is measured as the
/// value the token names, so moving a list onto the tokens keeps it counted.
const _tokens = {'AppInsets.itemGap': 8, 'AppSpace.sm': 8};

int? _height(String raw) => int.tryParse(raw) ?? _tokens[raw];

/// The span of the call whose `(` opens at [open], to its matching `)`.
String _callSpan(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return src.substring(open, i + 1);
  }
  return src.substring(open);
}

/// A card built straight into a separated list. Its own margin would add to
/// the separator, so it must say `margin:` (issue #1374: the plan library's
/// 8 dp separator plus the theme's 4 + 4 dp card margin put its cards 16 dp
/// apart, twice the gap of every other list).
final _listCard = RegExp(r'\b(?:ListCard(?:\.row|\.flush)?|PlanListCard)\(');

/// The brace-delimited body that follows [from]: a class's or a method's.
String _bodyAfter(String src, int from) {
  final open = src.indexOf('{', from);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}' && --depth == 0) return src.substring(open, i + 1);
  }
  return src.substring(open);
}

/// The source a separated list builds its items from: the list's own call,
/// plus the body of every widget class and helper method of the same file
/// that the call names (`_LibraryCard(…)`, `_card(…)`), one level deep.
List<(int, String)> _itemSources(String src, int open, String span) {
  final out = <(int, String)>[(open, span)];
  final named = RegExp(r'\b(_\w+)\(').allMatches(span).map((m) => m.group(1)!);
  for (final name in named.toSet()) {
    final decl =
        RegExp('(?:class\\s+$name\\b|Widget\\??\\s+$name\\s*\\()')
            .firstMatch(src);
    if (decl == null) continue;
    final body = _bodyAfter(src, decl.end);
    out.add((src.indexOf(body, decl.end), body));
  }
  return out;
}

/// Whether the call span names [arg] among its own arguments, not inside a
/// nested call or collection.
bool _hasOwnArg(String span, String arg) {
  var depth = 0;
  for (var i = 0; i < span.length; i++) {
    final c = span[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (depth == 1 &&
        span.startsWith(arg, i) &&
        (i == 0 || !RegExp(r'\w').hasMatch(span[i - 1]))) {
      return true;
    }
  }
  return false;
}

void main() {
  test('every list separator is the same gap', () {
    final offenders = <String>[];
    var measured = 0;

    for (final root in _roots.where(rootExists)) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final m in _sizedBoxSeparator.allMatches(src)) {
          measured++;
          if (_height(m.group(1)!) == _gap) continue;
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line height: ${m.group(1)}');
        }
      }
    }

    // §534: the assertion must not pass over an empty set.
    expect(measured, greaterThan(8),
        reason: 'found only $measured SizedBox separators — the scan is '
            'probably broken rather than the lists having gone away');
    expect(offenders..sort(), isEmpty,
        reason: 'these lists separate their rows by something other than '
            '$_gap dp. A Divider is a different thing and is not measured '
            'here; a gap is a gap.');
  });

  // The gap between two cards comes from one place. A separated list's
  // separator is that gap, so a card built into it says `margin:` (zero, as
  // a rule): left to the theme's 4 + 4 dp card margin it doubles the gap.
  test('a card in a separated list does not add its margin to the separator',
      () {
    final offenders = <String>[];
    var cards = 0;
    for (final root in _roots.where(rootExists)) {
      for (final file in dartFiles(root)) {
        final src = blankNonCode(file.readAsStringSync());
        for (final list in RegExp(r'ListView\.separated\(').allMatches(src)) {
          final open = list.end - 1;
          final span = _callSpan(src, open);
          if (!_sizedBoxSeparator.hasMatch(span)) continue;
          for (final (base, text) in _itemSources(src, open, span)) {
            for (final card in _listCard.allMatches(text)) {
              cards++;
              final call = _callSpan(text, card.end - 1);
              if (_hasOwnArg(call, 'margin:')) continue;
              final at = base + card.start;
              final line = '\n'.allMatches(src.substring(0, at)).length + 1;
              offenders.add('${file.path}:$line ${card.group(0)}');
            }
          }
        }
      }
    }
    expect(cards, greaterThan(4),
        reason: 'found only $cards cards in separated lists — the scan is '
            'probably broken');
    expect(offenders..sort(), isEmpty,
        reason: 'these cards sit in a list spaced by its separator and keep '
            "the theme's card margin, so they sit twice the gap apart. Pass "
            '`margin: EdgeInsets.zero`.');
  });
}
