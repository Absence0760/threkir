import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// fixtures/activity_speed_caps.json is the table every other port's tests
// read (Go, TS, Deno, Kotlin, Swift, Rust), so this enum and that file must
// agree. `dart test` runs with the package root as cwd.
Map<String, dynamic> _fixture() => jsonDecode(
      File('../../fixtures/activity_speed_caps.json').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  test('every ActivityType cap matches fixtures/activity_speed_caps.json', () {
    final caps = (_fixture()['capsMps'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as num).toDouble()));
    expect(
      caps.keys.toSet(),
      ActivityType.values.map((t) => t.name).toSet(),
    );
    for (final t in ActivityType.values) {
      expect(t.maxSpeedMps, caps[t.name], reason: t.name);
    }
  });

  test('the fixture names an activity it has a cap for as the fallback', () {
    final fx = _fixture();
    expect(
      (fx['capsMps'] as Map<String, dynamic>).containsKey(fx['unknownActivityCap']),
      isTrue,
    );
  });
}
