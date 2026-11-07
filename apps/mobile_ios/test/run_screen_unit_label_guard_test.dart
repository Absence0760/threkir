// Source-scan guard for #1300 section 1: the live Elevation tile printed raw
// metres beside a hardcoded "m" for a runner on imperial units. A tile whose
// quantity follows the distance preference must take its unit from
// `UnitFormat`, so only units that never change with that preference may come
// straight from the ARB catalogue.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _preferenceIndependentUnits = {'runUnitKcal', 'runUnitSpm', 'runUnitBpm'};

void main() {
  test('live stat tiles take preference-dependent units from UnitFormat', () {
    final source = File('lib/screens/run_screen.dart').readAsStringSync();
    final hardcoded = RegExp(r'unit:\s*l10n\.(\w+)')
        .allMatches(source)
        .map((m) => m.group(1)!)
        .where((key) => !_preferenceIndependentUnits.contains(key))
        .toList();
    expect(hardcoded, isEmpty,
        reason: 'Format these with UnitFormat so imperial runners see their '
            'own unit, or add a unit that never converts to the allowlist.');
    expect(source, contains('UnitFormat.elevationLabel(_unit)'));
  });
}
