// A suite that boots Supabase must go through initializeTestSupabase
// (test/supabase_test_init.dart), which stubs the app_links channels first.
//
// Without the stub, supabase_flutter's deep-link listener throws a
// MissingPluginException on the real event loop, and it fails whichever test
// is turning that loop when it lands. The stub was copied into four suites one
// flake at a time while sixty-seven others booted the client bare and were
// merely lucky. The next suite is written by copying the one beside it, so
// the rule is a scan, not a comment.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_scan.dart';

const _testRoot = 'test';
const _helper = 'test/supabase_test_init.dart';

final _directInit = RegExp(r'Supabase\s*\.\s*initialize\s*\(');
final _helperCall = RegExp(r'\binitializeTestSupabase\s*\(');

int _lineOf(String src, int offset) =>
    '\n'.allMatches(src.substring(0, offset)).length + 1;

void main() {
  group('every suite boots Supabase through initializeTestSupabase', () {
    test('the scan still sees the tree it is scanning', () {
      expect(rootExists(_testRoot), isTrue,
          reason: 'the test root moved and this guard is checking nothing');
      expect(File(_helper).existsSync(), isTrue,
          reason: 'the helper every offender is pointed at has moved');
      final callers = dartFiles(_testRoot)
          .where((f) =>
              _helperCall.hasMatch(blankNonCode(f.readAsStringSync())) &&
              f.path != _helper)
          .length;
      expect(callers, greaterThan(50),
          reason: 'only $callers suites call initializeTestSupabase — the '
              'scan is not seeing the call sites it exists to protect');
    });

    test('the helper stubs app_links before it initializes', () {
      final src = blankNonCode(File(_helper).readAsStringSync());
      final stub = src.indexOf('setMockMethodCallHandler');
      final init = _directInit.firstMatch(src)?.start ?? -1;
      expect(stub, greaterThanOrEqualTo(0),
          reason: 'the helper no longer stubs the app_links channels');
      expect(init, greaterThan(stub),
          reason: 'the channels must be stubbed BEFORE Supabase.initialize '
              'opens the deep-link stream');
    });

    test('no other test file calls Supabase.initialize directly', () {
      final offenders = <String>[];
      for (final f in dartFiles(_testRoot)) {
        if (f.path == _helper) continue;
        final raw = f.readAsStringSync();
        for (final m in _directInit.allMatches(blankNonCode(raw))) {
          offenders.add('${f.path}:${_lineOf(raw, m.start)}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'call initializeTestSupabase() from '
              'test/supabase_test_init.dart instead. A bare '
              'Supabase.initialize leaves the app_links channels unstubbed, '
              'and the MissingPluginException fails whichever test is '
              'running when it lands:\n${offenders.join('\n')}');
    });
  });
}
