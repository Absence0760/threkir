import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/coach_assist_consent.dart';

void main() {
  test('matches coach_assist_consent_current_version() in SQL', () {
    // The RPC refuses a version above its own maximum, so a client ahead of
    // the server could never save the switch, and one behind it would record
    // an acceptance of copy it never showed. The NEWEST definition is the
    // live one: migrations apply in filename order.
    final re = RegExp(
      r'create or replace function coach_assist_consent_current_version\(\)'
      r'[\s\S]*?select\s+(\d+)::smallint',
    );
    final files = Directory('../backend/supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    RegExpMatch? match;
    for (final f in files) {
      for (final m in re.allMatches(f.readAsStringSync())) {
        match = m;
      }
    }
    expect(match, isNotNull,
        reason: 'coach_assist_consent_current_version() must be in a migration');
    expect(int.parse(match!.group(1)!), kCoachAssistConsentVersion);
  });
}
