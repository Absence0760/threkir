// Dart twin of web's `messages_parity.test.ts`. Reads every `app_*.arb`
// catalogue from disk and asserts each locale carries exactly the English
// template's key set, with no empty values and faithful `{placeholder}`
// sets. `runs.metadata` aside, the ARB files are the only cross-locale
// contract on mobile — this test is what stops a locale silently drifting
// a key (which would crash gen-l10n or leave a fallback-to-English hole).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

/// Pull the real message keys out of a parsed ARB map — drop `@@locale`
/// and the `@key` metadata entries.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Extract `{placeholder}` argument names from a message value so we can
/// check translations didn't drop or rename an interpolation arg.
///
/// Parses the ICU MessageFormat shape rather than pattern-matching it: an
/// argument is `{name}` or `{name, type ...}` where a `{` opens one, and the
/// `{...}` after a plural/select selector (`one{...}`, `=0{...}`) is a
/// nested MESSAGE, whose text is not an argument. A regex for "`{` then a
/// word then `,` or `}`" cannot tell the two apart, so branch wording that
/// happens to start with a word and a comma — `one{Filters, 1 on}` — read
/// as a placeholder named `Filters` and failed every faithful translation.
Set<String> _placeholders(String value) => _IcuArgs(value).parse();

/// Whether [value] uses ICU's `#` shorthand inside a plural branch. Flutter's
/// gen-l10n does not implement `#`: it emits the branch text verbatim, so
/// `{n, plural, other {# weeks}}` renders a literal "# weeks". Branches must
/// name the argument instead (`other {{n} weeks}`). Web's catalogue runtime
/// does support `#`, which is how the shorthand keeps arriving in ports.
bool _hashInPlural(String value) => (_IcuArgs(value)..parse()).hashInPlural;

/// The text of every `one{…}` branch of a `plural` (not `selectordinal`, not
/// `select`) argument in [value], paired with that argument's name.
List<(String, String)> _oneBranches(String value) =>
    (_IcuArgs(value)..parse()).oneBranches;

/// A `1` standing as a number of its own: not part of `10`, `1.5`, `1RM` or
/// `x1`. A literal count in a `one` branch is what this finds.
final _literalOne = RegExp(r'(?<![\p{L}\p{N}.,])1(?![\p{L}\p{N}.,])', unicode: true);

/// Whether [locale]'s CLDR `one` category, as gen-l10n's generated getters
/// resolve it through `Intl.pluralLogic`, covers a count other than 1. In
/// such a locale (`fr` and `pt` take 0 as well) a `one` branch that spells
/// out "1" renders "1 …" for a count of 0.
bool _oneCoversMoreThanOne(String locale) => [
  for (var n = 0; n <= 100; n++) n,
].any(
  (n) =>
      n != 1 &&
      Intl.pluralLogic(n, locale: locale, one: 'one', other: 'other') ==
          'one',
);

class _IcuArgs {
  _IcuArgs(this.s);

  final String s;
  final Set<String> names = {};
  final List<(String, String)> oneBranches = [];
  var i = 0;
  var _pluralDepth = 0;
  var hashInPlural = false;

  static final _word = RegExp(r'\w+');
  static const _branching = {'plural', 'select', 'selectordinal'};

  Set<String> parse() {
    _message(nested: false);
    return names;
  }

  void _message({required bool nested}) {
    while (i < s.length) {
      final c = s[i];
      if (c == '}' && nested) return;
      i++;
      if (c == '#' && _pluralDepth > 0) hashInPlural = true;
      if (c == '{') _argument();
    }
  }

  String? _token(RegExp re) {
    _ws();
    final m = re.matchAsPrefix(s, i);
    if (m == null) return null;
    i = m.end;
    return m.group(0);
  }

  void _ws() {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
  }

  void _skipToClose() {
    var depth = 1;
    while (i < s.length && depth > 0) {
      if (s[i] == '{') depth++;
      if (s[i] == '}') depth--;
      i++;
    }
  }

  void _argument() {
    final name = _token(_word);
    if (name == null) return _skipToClose();
    names.add(name);
    _ws();
    if (i < s.length && s[i] == '}') {
      i++;
      return;
    }
    if (i >= s.length || s[i] != ',') return _skipToClose();
    i++;
    final type = _token(_word);
    if (!_branching.contains(type)) return _skipToClose();
    final counts = type != 'select';
    if (counts) _pluralDepth++;
    try {
      _branches(type == 'plural' ? name : null);
    } finally {
      if (counts) _pluralDepth--;
    }
  }

  void _branches(String? pluralArg) {
    _ws();
    if (i < s.length && s[i] == ',') i++;
    while (true) {
      _ws();
      if (i >= s.length) return;
      if (s[i] == '}') {
        i++;
        return;
      }
      final selector = _token(RegExp(r'[^\s{}]+'));
      if (selector != null && selector.startsWith('offset:')) continue;
      _ws();
      if (selector == null || i >= s.length || s[i] != '{') {
        return _skipToClose();
      }
      i++;
      final start = i;
      _message(nested: true);
      if (pluralArg != null && selector == 'one') {
        oneBranches.add((pluralArg, s.substring(start, i)));
      }
      if (i < s.length) i++;
    }
  }
}

Map<String, dynamic> _readArb(String tag) {
  final raw = File('lib/l10n/app_$tag.arb').readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// The shortest run of 3+ characters that appears twice back-to-back in [s],
/// or null when none does. "your your run" yields "your ".
String? _adjacentRepeat(String s) {
  for (var len = 3; len <= s.length ~/ 2; len++) {
    for (var i = 0; i + 2 * len <= s.length; i++) {
      if (s.substring(i, i + len) == s.substring(i + len, i + 2 * len)) {
        return s.substring(i, i + len);
      }
    }
  }
  return null;
}

void main() {
  // Every catalogue file present in lib/l10n. `pt` and `pt_BR` are BOTH real
  // shipped locales — European and Brazilian Portuguese, 247 of whose 3478
  // strings genuinely differ. `pt` was long described here as a gen-l10n base
  // fallback, and was in fact unreachable at runtime until `supportedLocales`
  // learned it (see `locale_negotiation_test.dart`).
  const localeTags = ['en', 'de', 'fr', 'es', 'ja', 'pt', 'pt_BR'];

  final en = _readArb('en');
  final enKeys = _messageKeys(en);

  test('English template has keys', () {
    expect(enKeys, isNotEmpty);
  });

  test('placeholder extraction follows ICU structure, not branch wording', () {
    expect(_placeholders('Hi {name}'), {'name'});
    expect(
      _placeholders(
        '{count, plural, one{Filters, 1 on} other{Filters, {count} on}}',
      ),
      {'count'},
    );
    expect(_placeholders('{n, plural, =0{none} other{{n} by {who}}} {when}'), {
      'n',
      'who',
      'when',
    });
    expect(_placeholders('{kind, select, a{A, {x}} other{B}}'), {'kind', 'x'});
    expect(_placeholders('{d, date, yMMMd}'), {'d'});
  });

  test('the plural-# scan finds # only inside a plural branch', () {
    expect(_hashInPlural('{n, plural, one {# week} other {# weeks}}'), isTrue);
    expect(_hashInPlural('{n, selectordinal, other {#th}}'), isTrue);
    expect(
      _hashInPlural('{n, plural, other {{k, select, a {# x} other {y}}}}'),
      isTrue,
    );
    expect(
      _hashInPlural('{n, plural, one {{n} week} other {{n} weeks}}'),
      isFalse,
    );
    expect(_hashInPlural('Lap #3 {n}'), isFalse);
    expect(_hashInPlural('{k, select, a {#1} other {x}}'), isFalse);
  });

  test('the one-branch scan reads plural one{} branches only', () {
    expect(_oneBranches('{n, plural, one{1 run} other{{n} runs}}'), [
      ('n', '1 run'),
    ]);
    expect(
      _oneBranches('{a} {n, plural, =1{x} one{{n} y} other{z}}'),
      [('n', '{n} y')],
    );
    expect(_oneBranches('{n, selectordinal, one{#st} other{#th}}'), isEmpty);
    expect(_oneBranches('{k, select, one{1} other{2}}'), isEmpty);
    expect(_literalOne.hasMatch('Filtres, 1 actif'), isTrue);
    expect(_literalOne.hasMatch('1 minute'), isTrue);
    for (final ok in ['10 km', '1.5 km', '1RM', 'x1', '{count} actif']) {
      expect(_literalOne.hasMatch(ok), isFalse, reason: ok);
    }
  });

  test('one-category locales are derived from the plural rules', () {
    // Pins the derivation the plural guard below rests on, so a change in
    // intl's rules cannot quietly empty the set it checks.
    expect(
      [
        for (final tag in localeTags)
          if (_oneCoversMoreThanOne(tag)) tag,
      ],
      containsAll(['fr', 'pt', 'pt_BR']),
    );
    expect(_oneCoversMoreThanOne('en'), isFalse);
    expect(_oneCoversMoreThanOne('de'), isFalse);
  });

  test('no catalogue declares the same key twice', () {
    // `jsonDecode` silently keeps the LAST of a duplicated key, so every other
    // assertion in this file is blind to one — while gen-l10n takes the
    // getter's POSITION from the first occurrence and its value + description
    // from the last, so the two halves of a duplicate can disagree and only
    // one of them ships. `privacyZonesTitle` was declared twice in all seven
    // catalogues, under two different descriptions (decisions § 754).
    for (final tag in localeTags) {
      final counts = <String, int>{};
      for (final line in File('lib/l10n/app_$tag.arb').readAsLinesSync()) {
        final m = RegExp(r'^  "(@{0,2}[A-Za-z0-9_]+)"\s*:').firstMatch(line);
        if (m != null) {
          counts[m.group(1)!] = (counts[m.group(1)!] ?? 0) + 1;
        }
      }
      // The scan keys on the catalogue's two-space top-level indent. Pin that
      // it really did see every entry, so a reformat makes this test fail
      // rather than pass vacuously.
      expect(
        counts.keys.toSet(),
        _readArb(tag).keys.toSet(),
        reason:
            'the duplicate scan did not see app_$tag.arb the way '
            'jsonDecode does',
      );
      final dupes =
          counts.entries.where((e) => e.value > 1).map((e) => e.key).toList()
            ..sort();
      expect(dupes, isEmpty, reason: 'app_$tag.arb declares these keys twice');
    }
  });

  for (final tag in localeTags) {
    group('locale $tag', () {
      final arb = _readArb(tag);
      final keys = _messageKeys(arb);

      test('declares its @@locale', () {
        expect(
          arb['@@locale'],
          isNotNull,
          reason: 'app_$tag.arb is missing the @@locale marker',
        );
      });

      test('key set matches the English template exactly', () {
        final missing = enKeys.difference(keys);
        final extra = keys.difference(enKeys);
        expect(missing, isEmpty, reason: 'app_$tag.arb is missing keys');
        expect(extra, isEmpty, reason: 'app_$tag.arb has keys not in en');
      });

      test('no value is empty or whitespace-only', () {
        for (final key in keys) {
          final value = arb[key];
          expect(value, isA<String>(), reason: '$key is not a string');
          expect(
            (value as String).trim(),
            isNotEmpty,
            reason: '$key is empty in app_$tag.arb',
          );
        }
      });

      test('placeholder sets are faithful to the English value', () {
        for (final key in enKeys) {
          if (!keys.contains(key)) continue;
          final expected = _placeholders(en[key] as String);
          final actual = _placeholders(arb[key] as String);
          expect(
            actual,
            equals(expected),
            reason: '$key placeholders differ in app_$tag.arb',
          );
        }
      });

      test('no plural branch uses the # shorthand gen-l10n cannot render', () {
        final offenders = [
          for (final key in keys)
            if (_hashInPlural(arb[key] as String)) key,
        ]..sort();
        expect(
          offenders,
          isEmpty,
          reason:
              'app_$tag.arb uses # inside a plural; gen-l10n prints it '
              'literally. Name the argument instead: other {{n} weeks}',
        );
      });

      // gen-l10n resolves a plural through `Intl.pluralLogic` for the
      // catalogue's locale, and in fr and pt CLDR's `one` covers 0 as well
      // as 1. A `one` branch that copies the English "1" therefore renders
      // "Filtres, 1 actif" when no filter is on. Name the argument instead:
      // one{{count} actif}. Locales whose `one` is exactly 1 are exempt.
      test('no plural one branch spells out a literal 1', () {
        if (!_oneCoversMoreThanOne(tag)) return;
        final offenders = [
          for (final key in keys)
            for (final (arg, text) in _oneBranches(arb[key] as String))
              if (_literalOne.hasMatch(text)) '$key ($arg): $text',
        ]..sort();
        expect(
          offenders,
          isEmpty,
          reason:
              'app_$tag.arb: `one` also covers counts other than 1 here, so '
              'a literal 1 is wrong for them. Use the argument: one{{n} …}',
        );
      });

      // `profileNotifYourRun` is the {dist} fallback for a notification whose
      // run distance is unknown, and every template that consumes {dist}
      // already supplies the possessive ("your {dist}", "deinem {dist}",
      // "à sua {dist}", "あなたの{dist}"). A fallback that carries its own
      // therefore renders it twice — "gave kudos to your your run" — which
      // shipped in all seven locales until it was measured.
      //
      // Pinned as a derivation rather than per-locale copy: substitute the
      // fallback in and assert nothing in the result repeats back-to-back.
      // That is language-agnostic, needs no possessive vocabulary, and holds
      // for the space-free ja catalogue too.
      test('the {dist} fallback does not double the template possessive', () {
        final fallback = arb['profileNotifYourRun'] as String;
        for (final key in ['profileNotifKudos', 'profileNotifComment']) {
          final rendered = (arb[key] as String)
              .replaceAll('{name}', 'Ana')
              .replaceAll('{dist}', fallback);
          final repeat = _adjacentRepeat(rendered);
          expect(
            repeat,
            isNull,
            reason: '$key repeats "$repeat" in app_$tag.arb: $rendered',
          );
        }
      });
    });
  }
}
