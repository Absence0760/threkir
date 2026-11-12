import 'dart:io';

import 'package:test/test.dart';

/// Which runner each Dart package in this workspace takes, checked rather than
/// asserted.
///
/// `dart test` cannot compile a package that reaches the Flutter SDK: the VM's
/// FFI transformer crashes with `type 'InvalidType' is not a subtype of type
/// 'FunctionType' in type cast`, naming no package, no dependency and no
/// runner. `run_recorder` and `ui_kit` at least declare `flutter: sdk: flutter`
/// in their own pubspec; `api_client` does NOT — it reaches the SDK through
/// `supabase_flutter`, so its pubspec reads as a pure-Dart package and the
/// crash reads as a broken tree. That cost a session a run to diagnose, and a
/// sentence in a document is only worth what keeps it true.
///
/// So the table in `docs/testing/testing.md` is the sentence and this is what
/// keeps it true. Three claims, and each catches a drift the other two miss:
/// every package holding tests is named exactly once, so a new package cannot
/// arrive with no documented runner; a package that declares the Flutter SDK
/// is in the `flutter test` column, DERIVED from its pubspec rather than
/// copied from the table; and the packages the table says CI runs are exactly
/// the ones CI runs — the `--scope=` list of the `test-packages` job, which is
/// the drift that once left `ui_kit` and `core_models` running nowhere, plus
/// any package the table hands to a job of its own (`apps/mobile_android`,
/// sharded in `test-mobile-android` since PR #1164's runner was shut down
/// mid-suite), which must exist and run `flutter test` in that package.
///
/// It cannot check the transitive case — nothing in this repo says
/// `supabase_flutter` is Flutter-only — which is precisely why that row is
/// written down.
void main() {
  final root = _repoRoot();
  final doc = File('${root.path}/docs/testing/testing.md');
  final ci = File('${root.path}/.github/workflows/ci.yml');

  late final Map<String, _RunnerRow> table;

  setUpAll(() {
    table = _parseRunnerTable(doc.readAsStringSync());
  });

  test('every package that owns tests has exactly one row', () {
    final onDisk = _packagesWithTests(root).toSet();
    expect(
      table.keys.toSet(),
      equals(onDisk),
      reason: 'docs/testing/testing.md § Which runner a package takes does not '
          'name the same packages the tree holds. A package with a pubspec and '
          'a test/ directory needs a row saying which runner it takes.',
    );
  });

  test('a package that declares the Flutter SDK is not offered to dart test', () {
    final wrong = <String>[];
    for (final entry in table.entries) {
      final pubspec =
          File('${root.path}/${entry.key}/pubspec.yaml').readAsStringSync();
      if (_declaresFlutterSdk(pubspec) && entry.value.dartTestWorks) {
        wrong.add(entry.key);
      }
    }
    expect(
      wrong,
      isEmpty,
      reason: 'these packages declare `flutter: sdk: flutter` in their own '
          'pubspec, so `dart test` crashes in the FFI transformer before a '
          'case runs — the table says otherwise',
    );
  });

  test('the CI column names exactly the jobs that run each package', () {
    final scopes = _testPackagesScopes(ci.readAsStringSync());
    final claimed = table.entries
        .where((e) => e.value.ciJob == 'test-packages')
        .map((e) => e.key.split('/').last)
        .toSet();
    expect(
      claimed,
      equals(scopes),
      reason: 'the `melos exec --scope=` list of ci.yml\'s test-packages job '
          'and the "Run in CI by" column disagree. A scope removed silently '
          'stops a whole suite; a scope added without a row leaves the doc '
          'claiming it runs nowhere.',
    );

    // A package the column hands to a job of its own must be run by it.
    final text = ci.readAsStringSync();
    final wrong = <String>[];
    for (final entry in table.entries) {
      final job = entry.value.ciJob;
      if (job == null || job == 'test-packages') continue;
      final block = _jobBlock(text, job);
      if (block == null) {
        wrong.add('${entry.key}: ci.yml has no job `$job`');
      } else if (!block.contains('working-directory: ${entry.key}') ||
          !block.contains('flutter test')) {
        wrong.add('${entry.key}: job `$job` does not run `flutter test` with '
            'working-directory ${entry.key}');
      }
    }
    expect(
      wrong,
      isEmpty,
      reason: 'the "Run in CI by" column names a job that does not run the '
          'package, so the suite it claims is covered runs nowhere',
    );
  });

  test('this package is documented as needing flutter test', () {
    // The row the crash that opened this file is about. Named outright rather
    // than left to the derivation above, which cannot reach it: nothing in
    // this repo says `supabase_flutter` pulls in the Flutter SDK.
    expect(table['packages/api_client']!.dartTestWorks, isFalse);
    expect(table['packages/api_client']!.ciJob, 'test-packages');
  });
}

class _RunnerRow {
  const _RunnerRow({required this.dartTestWorks, required this.ciJob});

  final bool dartTestWorks;

  /// The ci.yml job the "Run in CI by" cell names, or null when it names none.
  final String? ciJob;
}

Directory _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/docs/testing/testing.md').existsSync() &&
        File('${dir.path}/melos.yaml').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found above ${Directory.current.path}');
    }
    dir = parent;
  }
}

Map<String, _RunnerRow> _parseRunnerTable(String markdown) {
  final lines = markdown.split('\n');
  final header = lines.indexWhere(
    (l) => l.startsWith('| Package | Runner | Run in CI by |'),
  );
  if (header < 0) {
    throw StateError(
      'docs/testing/testing.md no longer holds the runner table this guard '
      'reads (a "| Package | Runner | Run in CI by |" header row).',
    );
  }
  final rows = <String, _RunnerRow>{};
  for (var i = header + 2; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('|')) break;
    final cells = line
        .split('|')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (cells.length != 3) {
      throw StateError('malformed runner-table row: ${lines[i]}');
    }
    final path = cells[0].replaceAll('`', '');
    final runner = cells[1];
    final dartTestWorks = runner.contains('`dart test`');
    final flutterOnly = runner == '`flutter test` only';
    if (!dartTestWorks && !flutterOnly) {
      throw StateError('unrecognised runner cell: $runner');
    }
    rows[path] = _RunnerRow(
      dartTestWorks: dartTestWorks,
      ciJob: RegExp(r'`([a-z0-9-]+)`').firstMatch(cells[2])?.group(1),
    );
  }
  if (rows.isEmpty) throw StateError('the runner table has no rows');
  return rows;
}

Iterable<String> _packagesWithTests(Directory root) sync* {
  for (final parent in const ['packages', 'apps']) {
    final dir = Directory('${root.path}/$parent');
    if (!dir.existsSync()) continue;
    final children = dir.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final child in children) {
      final name = child.path.split('/').last;
      if (!File('${child.path}/pubspec.yaml').existsSync()) continue;
      final tests = Directory('${child.path}/test');
      if (!tests.existsSync()) continue;
      final hasDart = tests
          .listSync(recursive: true)
          .whereType<File>()
          .any((f) => f.path.endsWith('_test.dart'));
      if (hasDart) yield '$parent/$name';
    }
  }
}

bool _declaresFlutterSdk(String pubspec) {
  final lines = pubspec.split('\n');
  for (var i = 0; i < lines.length - 1; i++) {
    if (lines[i].trimRight() != '  flutter:') continue;
    if (lines[i + 1].trim() == 'sdk: flutter') return true;
  }
  return false;
}

/// The lines of one top-level job under `jobs:`, or null if there is none.
String? _jobBlock(String ci, String job) {
  final lines = ci.split('\n');
  final start = lines.indexOf('  $job:');
  if (start < 0) return null;
  final header = RegExp(r'^(  [A-Za-z0-9_-]+:\s*$|\S)');
  var end = start + 1;
  while (end < lines.length && !header.hasMatch(lines[end])) {
    end++;
  }
  return lines.sublist(start, end).join('\n');
}

Set<String> _testPackagesScopes(String ci) {
  final invocations = ci
      .split('\n')
      .where((l) => l.contains('melos exec') && l.contains('flutter test'))
      .toList();
  if (invocations.length != 1) {
    throw StateError(
      'expected exactly one `melos exec … flutter test` line in ci.yml, '
      'found ${invocations.length} — this guard reads the scope list off it.',
    );
  }
  return RegExp(r'--scope="([^"]+)"')
      .allMatches(invocations.single)
      .map((m) => m.group(1)!)
      .toSet();
}
