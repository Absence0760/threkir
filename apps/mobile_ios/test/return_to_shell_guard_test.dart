// Every "go back to the shell" walks the stack through `returnToShell`, which
// pops one route at a time with `maybePop` so a `PopScope` (a `DiscardGuard`
// form, a live session's leave dialog) is asked first. `Navigator.popUntil`
// calls `pop`, which never asks, so a notification tap closed a half-filled
// form with no prompt (issue #1374 NS-1, decisions § 2484).
//
// The one file allowed to call it is `return_to_shell.dart`, whose `topRoute`
// uses a predicate that holds at once to read the top route without popping.
// Anything else that needs the top route calls `topRoute`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _home = 'lib/return_to_shell.dart';

void main() {
  test('no popUntil outside returnToShell', () {
    final offenders = <String>[];
    final call = RegExp(r'\.popUntil\s*\(');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == _home || path.contains('/l10n/gen/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (call.hasMatch(code)) offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use returnToShell (or topRoute to read the top route): '
            'popUntil pops past a PopScope without asking it.');
  });

  test('the helper still holds the one allowed call', () {
    expect(RegExp(r'\.popUntil\s*\(').hasMatch(File(_home).readAsStringSync()),
        isTrue,
        reason: 'return_to_shell.dart moved; point _home at its new path');
  });
}
