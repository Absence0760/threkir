import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// One row of the routes_intersecting_track RPC.
void main() {
  test('reads the RPC row, widening integer metres to doubles', () {
    final c = RouteMatchCandidate.fromJson({
      'id': 'r1',
      'name': 'River loop',
      'distance_m': 5000,
      'start_offset_m': 12.5,
      'end_offset_m': 40,
    });
    expect(c.id, 'r1');
    expect(c.name, 'River loop');
    expect(c.distanceM, 5000.0);
    expect(c.distanceM, isA<double>());
    expect(c.startOffsetM, 12.5);
    expect(c.endOffsetM, 40.0);
  });

  test('a row missing a required field is refused, not defaulted', () {
    expect(
        () => RouteMatchCandidate.fromJson({
              'id': 'r1',
              'name': 'River loop',
              'start_offset_m': 0,
              'end_offset_m': 0,
            }),
        throwsA(isA<TypeError>()));
  });
}
