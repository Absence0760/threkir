// No derived metric reaches a runner without its definition (#902 §1 + §2).
//
// Dart twin of web's `metric_label_guard.test.ts`. The dashboard's fitness
// card carried plain-English copy for VO₂ max, VDOT, CTL, ATL and TSB in all
// seven locales; RPE, 1RM, age grade, vert, TRIMP and Riegel carried nothing
// at all, and there was no registry and no scan to notice. This file is the
// scan. It reads `kMetrics` from `lib/metrics.dart` itself, so there is no
// second list of terms here to fall out of step with the registry.
//
// Five rules, each with a fixture proving it can fail:
//
//  1. The registry's own halves agree: an `L10nKey('x', (l, a) => l.y)` whose
//     name and getter differ would let the guard hunt for a key no surface
//     resolves, and every registered key is in the English catalogue.
//  2. A registered catalogue key is never resolved in `lib/screens` or
//     `lib/widgets`. The registry resolves it, so `l10n.gymRpe` typed on a
//     surface is a render that bypassed the disclosure.
//  3. A registered term is never typed straight into a Dart string literal
//     (`'VDOT ${plan.vdot}'` — exactly what two plan surfaces did).
//  4. English copy that carries a term is a registered name, definition or
//     sentence, or an `allowedIn` exemption — and an exemption that stopped
//     carrying the term fails, so a reason cannot outlive its cause.
//  5. Every registered metric is disclosed somewhere: named by a
//     `MetricInfoButton`, a `MetricSentence`, or a `showMetricDefinition`
//     call. `metricText` renders the name with no disclosure beside it, and
//     is only allowed for a metric that has one.
//
// Where this differs from web, and why: web requires a `plain` render to have
// an interactive sibling in the SAME file, because a Svelte component IS the
// surface. `dashboard_screen.dart` is one file holding a dozen cards, so the
// same rule there would assert almost nothing; and a Flutter card that is
// already a tap target (the period card taps through to a period summary)
// cannot nest a second one the way a DOM node can. The Dart rule is therefore
// tree-wide: the definition is one surface away, not zero and not nowhere.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/metrics.dart';

/// Dart source with comments blanked out, newlines kept so offsets and line
/// numbers stay the file's own. String literals are stepped over, so a `//`
/// inside a URL does not swallow the rest of the line.
String stripDartComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == '/' && i + 1 < source.length && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      while (i < source.length && !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        out.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      out.write('  ');
      i += 2;
    } else if (c == "'" || c == '"') {
      final end = _endOfLiteral(source, i);
      out.write(source.substring(i, end));
      i = end;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Index just past the string literal opening at [start] (single, double or
/// triple quoted; raw or not). Interpolations are stepped over as text, which
/// is enough for a scan that only asks what a literal SAYS.
int _endOfLiteral(String source, int start) {
  final quote = source[start];
  final triple = source.startsWith(quote * 3, start);
  final close = triple ? quote * 3 : quote;
  var i = start + close.length;
  while (i < source.length) {
    if (source[i] == r'\') {
      i += 2;
      continue;
    }
    if (source.startsWith(close, i)) return i + close.length;
    if (!triple && source[i] == '\n') return i;
    i++;
  }
  return source.length;
}

/// Every string literal in [source], quotes included — the quotes are what
/// stops a `'vert'` map key reading as the word a runner sees.
List<String> stringLiterals(String source) {
  final code = stripDartComments(source);
  final out = <String>[];
  var i = 0;
  while (i < code.length) {
    final c = code[i];
    if (c == "'" || c == '"') {
      final end = _endOfLiteral(code, i);
      out.add(code.substring(i, end));
      i = end;
    } else {
      i++;
    }
  }
  return out;
}

/// Lines where `l10n.<key>` (or any `.key`) is resolved, comments excluded.
List<int> keyMentions(String source, String key) {
  if (!source.contains(key)) return const [];
  final code = stripDartComments(source);
  final re = RegExp(r'\.' + RegExp.escape(key) + r'\b');
  final lines = <int>[];
  for (final m in re.allMatches(code)) {
    lines.add('\n'.allMatches(code.substring(0, m.start)).length + 1);
  }
  return lines;
}

List<File> _dartFiles(List<String> roots) => [
      for (final root in roots)
        ...Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
    ];

const _surfaceRoots = ['lib/screens', 'lib/widgets'];

final _entries = kMetrics.entries.toList();

Map<String, String> _englishCatalogue() {
  final arb =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in arb.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

/// Every catalogue key the registry owns, metric id included for the message.
Map<String, Metric> _ownedKeys() {
  final owned = <String, Metric>{};
  for (final entry in _entries) {
    for (final k in [
      ...metricNameKeys(entry.value),
      entry.value.definition,
      ...entry.value.sentences.values,
    ]) {
      owned[k.name] = entry.key;
    }
  }
  return owned;
}

void main() {
  final catalogue = _englishCatalogue();
  final surfaces = _dartFiles(_surfaceRoots)
      .map((f) => (path: f.path, source: f.readAsStringSync()))
      .toList();

  test('the scan reaches the surfaces', () {
    expect(surfaces.length, greaterThan(100),
        reason: 'the walk reached only ${surfaces.length} files');
  });

  // ─────────── Fixtures: each scanner can fail ───────────

  test('fixture: comments are blanked and literals survive', () {
    expect(stringLiterals("// VDOT here\nfinal a = 'VDOT 1';"), ["'VDOT 1'"]);
    expect(stringLiterals("/* RPE */ final a = 1;"), isEmpty);
    expect(stringLiterals(r"final u = 'https://x/y'; // RPE"), ["'https://x/y'"]);
    expect(keyMentions("// l10n.gymRpe\nfinal a = 1;", 'gymRpe'), isEmpty);
    expect(keyMentions("final a = l10n.gymRpe;", 'gymRpe'), [1]);
    expect(keyMentions("final a = l10n.gymRpeExtra;", 'gymRpe'), isEmpty);
  });

  test('fixture: a quoted map key is not the word a runner reads', () {
    final vert = kMetrics[Metric.vert]!.term!;
    expect(vert.hasMatch('{value} vert'), isTrue, reason: 'a catalogue value');
    expect(vert.hasMatch("'a vert climb'"), isTrue, reason: 'copy in a literal');
    expect(vert.hasMatch("'vert'"), isFalse, reason: 'a placeholder name');
    expect(vert.hasMatch('vertMetres'), isFalse);
  });

  // ─────────── Rule 1 ───────────

  test('rule 1: the registry names the same getter it resolves', () {
    final source = File('lib/metrics.dart').readAsStringSync();
    final declared = RegExp(r"L10nKey\(\s*'(\w+)',\s*\(l, a\) =>\s*l\.(\w+)")
        .allMatches(source)
        .toList();
    expect(declared.length, greaterThanOrEqualTo(_ownedKeys().length),
        reason: 'the L10nKey scan did not see every entry in kMetrics');
    final mismatched = [
      for (final m in declared)
        if (m.group(1) != m.group(2)) '${m.group(1)} resolves l.${m.group(2)}',
    ];
    expect(mismatched, isEmpty,
        reason: 'an L10nKey must name the getter it resolves, or the guard '
            'hunts for a key no surface uses');
  });

  test('rule 1: every registered key is in the English catalogue', () {
    final missing = [
      for (final e in _ownedKeys().entries)
        if (!catalogue.containsKey(e.key)) '${e.key} (${e.value.name})',
    ];
    expect(missing, isEmpty, reason: 'registered but not in app_en.arb');
  });

  // ─────────── Rule 2 ───────────

  test('rule 2: no registered catalogue key is resolved on a surface', () {
    final offenders = <String>[];
    for (final e in _ownedKeys().entries) {
      for (final f in surfaces) {
        for (final line in keyMentions(f.source, e.key)) {
          offenders.add('${f.path}:$line ${e.key} (${e.value.name})');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Render a registered metric through metricText / '
            'MetricSentence / MetricInfoButton, which resolve its name and '
            'definition from lib/metrics.dart. A key resolved here bypasses '
            'the disclosure:\n  ${offenders.join('\n  ')}');
  });

  // ─────────── Rule 3 ───────────

  test('rule 3: no registered term is typed into a Dart string literal', () {
    final offenders = <String>[];
    for (final entry in _entries) {
      final term = entry.value.term;
      if (term == null) continue;
      for (final f in surfaces) {
        for (final literal in stringLiterals(f.source)) {
          if (term.hasMatch(literal)) {
            offenders.add('${f.path} ${entry.key.name}: $literal');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'A registered term is copy with a definition waiting for it. '
            'Put it in the catalogue and render it through the registry:\n  '
            '${offenders.join('\n  ')}');
  });

  // ─────────── Rule 4 ───────────

  test('rule 4: English copy never carries a term without an explanation', () {
    final owned = _ownedKeys();
    final offenders = <String>[];
    for (final entry in _entries) {
      final term = entry.value.term;
      if (term == null) continue;
      final allowed = {
        for (final k in owned.entries)
          if (k.value == entry.key) k.key,
        ...entry.value.allowedIn.keys,
      };
      for (final c in catalogue.entries) {
        if (term.hasMatch(c.value) && !allowed.contains(c.key)) {
          offenders.add('${c.key} (${entry.key.name}): ${c.value}');
        }
      }
      for (final k in entry.value.allowedIn.keys) {
        final value = catalogue[k];
        if (value == null) {
          offenders.add('$k (${entry.key.name}): exempted but gone from the catalogue');
        } else if (!term.hasMatch(value)) {
          offenders.add('$k (${entry.key.name}): exempted but no longer carries $term');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Copy that names a registered metric must be its label, a '
            'variant, its definition, a registered sentence, or an allowedIn '
            'exemption whose reason still holds:\n  ${offenders.join('\n  ')}');
  });

  // ─────────── Rule 5 ───────────

  test('rule 5: every metric is disclosed, and no plain render is orphaned', () {
    final disclosed = <String>{};
    final plain = <String, String>{};
    // Derived, not listed: a disclosure is whatever `widgets/metric_label.dart`
    // exports, so adding one there is enough and renaming one cannot leave a
    // stale name here quietly passing.
    final labelSource = File('lib/widgets/metric_label.dart').readAsStringSync();
    final names = [
      ...RegExp(r'^class (\w+) extends StatelessWidget', multiLine: true)
          .allMatches(labelSource)
          .map((m) => m.group(1)!),
      ...RegExp(r'^void (\w+)\(BuildContext', multiLine: true)
          .allMatches(labelSource)
          .map((m) => m.group(1)!),
    ];
    expect(names, contains('MetricInfoButton'),
        reason: 'the discloser scan did not read metric_label.dart');
    final disclosures = [
      RegExp('(?:${names.join('|')})\\((?:[^();]{0,200}?)Metric\\.(\\w+)'),
    ];
    for (final f in surfaces) {
      final code = stripDartComments(f.source);
      for (final re in disclosures) {
        for (final m in re.allMatches(code)) {
          disclosed.add(m.group(1)!);
        }
      }
      for (final m in RegExp(r'metricText\([^,]+,\s*Metric\.(\w+)').allMatches(code)) {
        plain.putIfAbsent(m.group(1)!, () => f.path);
      }
    }
    final offenders = <String>[];
    for (final entry in _entries) {
      if (!disclosed.contains(entry.key.name)) {
        offenders.add('${entry.key.name}: registered but never disclosed');
      }
    }
    for (final e in plain.entries) {
      if (!disclosed.contains(e.key)) {
        offenders.add('${e.value}: metricText(Metric.${e.key}) with no '
            'disclosure for that metric anywhere in the tree');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
