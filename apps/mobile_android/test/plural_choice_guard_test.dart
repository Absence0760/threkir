// No string is chosen by comparing a count with 1 (decisions § 2497).
// `n == 1 ? l10n.xOne : l10n.xMany(n)` applies English plural rules to every
// locale: French and Brazilian Portuguese put 0 in the singular, and a
// "tomorrow" phrase is an exact match, not a plural. The count belongs in one
// ICU message (`{n, plural, =1{…} one{…} other{…}}`), which picks the branch
// with the active locale's rules. The web twin is
// apps/web/src/lib/i18n/plural_choice_guard.test.ts.
//
// The exemptions choose between two strings for a reason other than number.
// The map may only shrink: an entry whose choice is gone fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _exempt = {
  'lib/route_file_import.dart routesImported':
      'one import names the route; several give a count',
  'lib/widgets/upcoming_event_card.dart upcomingEventStartingNow':
      'a minute or less away is "starting now", not a count of minutes',
};

final _comparison = RegExp(r'(?:[!=]=|[<>]=?)\s*1\s*\?(?![.?])');
final _l10n = RegExp(r'\b(?:l10n|l|t|dl10n)\.([a-z]\w*)');

/// One operand of a conditional starting at [i]: up to the `:` (the
/// consequent) or to the first `,` `;` `)` `]` `}` at bracket depth 0 (the
/// alternate). Nested conditionals stay inside the operand.
String _operand(String s, int i, {required bool consequent}) {
  var depth = 0;
  String? quote;
  final start = i;
  for (; i < s.length; i++) {
    final c = s[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
    } else if ('([{'.contains(c)) {
      depth++;
    } else if (')]}'.contains(c)) {
      if (depth == 0) break;
      depth--;
    } else if (depth == 0 && (c == ',' || c == ';')) {
      break;
    } else if (depth == 0 && consequent && c == ':') {
      break;
    } else if (depth == 0 &&
        c == '?' &&
        i + 1 < s.length &&
        s[i + 1] != '.' &&
        s[i + 1] != '?') {
      final inner = _operand(s, i + 1, consequent: true);
      i += inner.length + 1;
    }
  }
  return s.substring(start, i);
}

/// Every conditional on a comparison with 1 whose two branches each read a
/// localized string, as `line: getter / getter`.
List<(int, String, String)> oneChoices(String src) {
  final out = <(int, String, String)>[];
  for (final m in _comparison.allMatches(src)) {
    final at = m.end;
    final yes = _operand(src, at, consequent: true);
    if (at + yes.length >= src.length || src[at + yes.length] != ':') continue;
    final no = _operand(src, at + yes.length + 1, consequent: false);
    final a = _l10n.firstMatch(yes);
    final b = _l10n.firstMatch(no);
    if (a != null && b != null) {
      final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      out.add((line, a.group(1)!, b.group(1)!));
    }
  }
  return out;
}

void main() {
  test('the scan finds a getter choice made by a count of 1', () {
    expect(oneChoices('n == 1 ? l10n.aOne : l10n.aMany(n)'), hasLength(1));
    expect(oneChoices('x(\n  n == 1\n    ? l10n.a\n    : l10n.b(n),\n)'),
        hasLength(1));
    expect(oneChoices('n > 1 ? l.b(n) : l.a'), hasLength(1));
    expect(oneChoices('l10n.a(n)'), isEmpty);
    expect(oneChoices("n == 1 ? 'x' : l10n.b(n)"), isEmpty);
    expect(oneChoices('n == 1 ? f(a ? 1 : 2) : g'), isEmpty);
  });

  test('no string is chosen by comparing a count with 1', () {
    final offenders = <String>[];
    final used = <String>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('/l10n/'));
    for (final f in files) {
      final path = f.path.replaceAll(r'\', '/');
      for (final (line, a, b) in oneChoices(f.readAsStringSync())) {
        final id = '$path $a';
        if (_exempt.containsKey(id)) {
          used.add(id);
        } else {
          offenders.add('$path:$line $a / $b');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Merge the pair into one ICU plural in every ARB '
            '({n, plural, one{…} other{…}}, =1{…} for an exact phrase) and '
            'pass the count.');
    expect(_exempt.keys.where((k) => !used.contains(k)), isEmpty,
        reason: 'A choice that is gone comes off the list.');
  });
}
