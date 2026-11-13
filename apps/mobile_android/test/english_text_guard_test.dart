// A module that hands a reader a sentence hands it in the reader's language:
// the words live in the ARBs, and a pure helper returns a kind, an id or a
// number (`recoveryAdviceKind`, `computeReadiness().dominant`, the recap badge
// ids, `racePlanDescribe`'s AppLocalizations). This scan counts the English
// prose left in string literals across `lib/` (comments stripped, lines that
// log, assert or throw skipped) and fails on any file not listed below, or
// listed with a different count. Web twin:
// apps/web/src/lib/i18n/english_text_guard.test.ts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _prose = RegExp(r"^[A-Z][a-z’']+(?:[ ,]+[A-Za-z’'${}.—–-]+){2,}");
final _notProse = RegExp(r'https?:|[=<>]|\.\w+\(');
final _skipLine = RegExp(
    r'debugPrint|print\(|\bthrow\b|Exception\(|Error\(|\blog\(|developer\.log');
final _literal = RegExp(r'''(['"])((?:(?!\1)[^\\\n]|\\.){8,})\1''');

int _englishIn(String source) {
  var s = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  s = s.replaceAllMapped(
      RegExp(r'(^|[^:])//.*$', multiLine: true), (m) => m.group(1)!);
  final text = s.split('\n').where((l) => !_skipLine.hasMatch(l)).join('\n');
  var n = 0;
  for (final m in _literal.allMatches(text)) {
    final v = m.group(2)!;
    if (_prose.hasMatch(v) && !_notProse.hasMatch(v)) n++;
  }
  return n;
}

/// Text no reader sees in their own language, with the reason.
const _englishByDesign = <String, (int, String)>{
  'lib/park_courses.dart': (
    7,
    "place names and the trail data's licence and attribution, quoted as licensed"
  ),
  'lib/route_guide.dart': (
    11,
    "the route guide's canonical English, shared with web's JSON-LD (decisions § 2448)"
  ),
  'lib/import_failures.dart': (
    2,
    'the header row of a CSV file other tools parse, and a toString() check'
  ),
  'lib/screens/run_screen.dart': (1, 'an assert message'),
};

/// Reader-facing English still owed to the ARBs. May only shrink.
const _notYetLocalised = <String, int>{
  'lib/apple_watch_route_bridge.dart': 1,
  'lib/backup.dart': 3,
  'lib/csv_run_importer.dart': 6,
  'lib/exif_strip.dart': 1,
  'lib/goals.dart': 4,
  'lib/local_route_store.dart': 1,
  'lib/main.dart': 1,
  'lib/nutrition_targets.dart': 1,
  'lib/plan_serialize.dart': 7,
  'lib/quiet_location.dart': 2,
  'lib/screens/route_builder_screen.dart': 2,
  'lib/social_service.dart': 1,
  'lib/strava_importer.dart': 3,
  'lib/training_service.dart': 2,
};

Map<String, int> _scan() {
  final out = <String, int>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    if (f.path.startsWith('lib/l10n/')) continue;
    final n = _englishIn(f.readAsStringSync());
    if (n > 0) out[f.path] = n;
  }
  return out;
}

void main() {
  test('every module carrying English prose is accounted for, at its exact count',
      () {
    final found = _scan();
    final problems = <String>[];
    found.forEach((file, n) {
      final want = _englishByDesign[file]?.$1 ?? _notYetLocalised[file];
      if (want == null) {
        problems.add('$file: $n English string(s) a reader would see — '
            'move them to the ARBs');
      } else if (n > want) {
        problems.add('$file: $n English strings, $want allowed');
      } else if (n < want) {
        problems.add('$file: $n English strings, $want listed — lower it');
      }
    });
    for (final f in [..._englishByDesign.keys, ..._notYetLocalised.keys]) {
      if (!found.containsKey(f)) problems.add('$f: no English left — remove it');
    }
    expect(problems, isEmpty);
  });

  test('the localised helpers stay free of English', () {
    final found = _scan();
    for (final f in [
      'lib/recap.dart',
      'lib/race_plan_prefill.dart',
      'lib/fitness.dart',
      'lib/readiness.dart',
      'lib/recurrence.dart',
    ]) {
      expect(found[f] ?? 0, 0, reason: f);
    }
  });

  // A stored `activity_type` ("run", "hike") is a database value, not a word
  // for a reader: it reads as English on every locale, and "hike" is not even
  // what the app calls it (it says Trail run). A list shows
  // `activityTypeLabel` / `activityTypeLabelFor`, as written, never
  // lowercased in code, which turned "Run" into a value-looking "run" on the
  // run row and is wrong for German nouns (issue #1374, Training → Runs).
  test('no list shows a raw or code-lowercased activity type', () {
    final raw = RegExp(r"\$\{[\w.?!]*\.activityType\}");
    final lowered = RegExp(r'activityTypeLabel(?:For)?\([^)]*\)\.toLowerCase\(\)');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/l10n/')) continue;
      final src = f.readAsStringSync();
      for (final m in [...raw.allMatches(src), ...lowered.allMatches(src)]) {
        offenders.add('${f.path}: ${m.group(0)}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'show activityTypeLabelFor(l10n, value) as it is');
  });
}
