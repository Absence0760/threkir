import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

// Issue #1374 FS-12: toggles rebuilt the route by hand and dropped `clubId`
// (route detail) and `official` (the Routes list). copyWith keeps every field.
final _full = Route(
  id: 'r1',
  userId: 'u1',
  name: 'River loop',
  waypoints: const [Waypoint(lat: 51.5, lng: -0.1)],
  distanceMetres: 5000,
  elevationGainMetres: 42,
  isPublic: true,
  createdAt: DateTime.utc(2026, 1, 2),
  surface: 'trail',
  tags: const ['loop'],
  featured: true,
  runCount: 3,
  isStarred: true,
  clubId: 'c1',
  description: 'Along the river',
  official: true,
  officialDistanceMetres: 5000,
);

Object? _json(Route r) => jsonDecode(jsonEncode(r.toJson()));

void main() {
  test('the fixture sets every field away from its default', () {
    // A field added to Route and left out of this fixture would let copyWith
    // forget it unnoticed, so the fixture must exercise all of them.
    final defaults = Route(id: '', name: '', waypoints: const [], distanceMetres: 0);
    final full = _json(_full) as Map<String, dynamic>;
    final empty = _json(defaults) as Map<String, dynamic>;
    for (final key in full.keys) {
      expect(full[key], isNot(equals(empty[key])),
          reason: '$key is at its default in the fixture');
    }
  });

  test('copyWith() keeps every field', () {
    expect(_json(_full.copyWith()), _json(_full));
  });

  test('a toggle changes only its own field', () {
    final starred = _full.copyWith(isStarred: false);
    final a = _json(starred) as Map<String, dynamic>;
    final b = _json(_full) as Map<String, dynamic>;
    expect(a['isStarred'], isFalse);
    a.remove('isStarred');
    b.remove('isStarred');
    expect(a, b);
  });
}
