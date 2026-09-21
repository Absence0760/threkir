import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/watch_route_visibility.dart';

Route _route(String id, String userId) => Route(
      id: id,
      userId: userId,
      name: id,
      waypoints: const [
        Waypoint(lat: 51.5, lng: -0.12),
        Waypoint(lat: 51.51, lng: -0.13),
      ],
      distanceMetres: 1000,
      isStarred: true,
    );

void main() {
  group('routesVisibleToWatch', () {
    test('keeps the viewer own routes', () {
      final kept = routesVisibleToWatch(
        [_route('a', 'me'), _route('b', 'me')],
        () => 'me',
      );
      expect(kept.map((r) => r.id), ['a', 'b']);
    });

    test('drops a starred route owned by someone else', () {
      // The leak this function exists for. `is_starred` is per-owner
      // curation the public view drops (20260703_001), so this row's star is
      // NOT the viewer's, and pushing it would put another owner's unclipped
      // waypoints on this runner's wrist.
      final kept = routesVisibleToWatch(
        [_route('mine', 'me'), _route('theirs', 'someone-else')],
        () => 'me',
      );
      expect(kept.map((r) => r.id), ['mine']);
    });

    test('keeps a locally-built route the sync cycle has not pushed yet', () {
      // Empty userId is the Route constructor default, not another owner.
      final kept = routesVisibleToWatch([_route('fresh', '')], () => 'me');
      expect(kept.map((r) => r.id), ['fresh']);
    });

    test('a signed-out viewer keeps only local routes', () {
      for (final viewer in <String?>[null, '']) {
        final kept = routesVisibleToWatch(
          [_route('local', ''), _route('theirs', 'someone-else')],
          () => viewer,
        );
        expect(kept.map((r) => r.id), ['local'], reason: 'viewer=$viewer');
      }
    });

    test('an empty viewer id never matches an owned route', () {
      // Guards the obvious bug in the other direction: `'' == r.userId` must
      // not make every server-owned route visible to a signed-out phone.
      final kept = routesVisibleToWatch([_route('theirs', 'someone-else')], () => '');
      expect(kept, isEmpty);
    });

    test('an unwired provider does not filter, matching the store itself', () {
      // LocalRouteStore._visibleToActiveOwner: "An UNWIRED provider (tests,
      // pre-bootstrap) means no filtering." Diverging here would empty the
      // picker on a device whose session wiring is simply not up yet, which
      // is a worse failure than the one this function prevents.
      final all = [_route('mine', 'me'), _route('theirs', 'someone-else')];
      expect(routesVisibleToWatch(all, null), same(all));
    });
  });
}
