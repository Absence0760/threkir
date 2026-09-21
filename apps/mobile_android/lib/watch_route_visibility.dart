import 'package:core_models/core_models.dart';

/// The routes a watch picker may carry for the viewer holding the phone.
///
/// `routes.is_starred` is **per-owner** curation state: migration
/// `20260703_001_public_routes_view.sql` drops the column from `public_routes`
/// precisely because it "shouldn't surface on non-owner reads". So a starred
/// route belonging to somebody else is not this runner's curation — it is the
/// owner's, reaching the device through a club-member read or a row tagged
/// before the account switched — and pushing it to a wrist would ship
/// `Route.waypoints` straight past the privacy-zone boundary that
/// `clip_route_for_viewer` exists to hold (decisions § 33). The route-detail
/// screen already clips for a non-owner; both watch bridges sent the raw
/// column, on both wrists.
///
/// Dropping the route is the fail-closed answer rather than clipping it here:
/// clipping is a per-route RPC on a path that runs on every store change, and
/// a picker row whose geometry the viewer was never entitled to see has no
/// business on their wrist in the first place.
///
/// [viewerIdProvider] is [LocalRouteStore.currentUserIdProvider] itself, not
/// its result, so this reads ownership by the store's own three-state rule
/// rather than a second one: an UNWIRED provider (tests, pre-bootstrap) means
/// no filtering, a wired provider returning null means signed out, and an
/// empty `Route.userId` is a locally-built route the sync cycle has not
/// pushed yet — the constructor's default — which belongs to whoever holds
/// the phone.
List<Route> routesVisibleToWatch(
  List<Route> routes,
  String? Function()? viewerIdProvider,
) {
  if (viewerIdProvider == null) return routes;
  final viewerId = viewerIdProvider();
  final signedIn = viewerId != null && viewerId.isNotEmpty;
  return [
    for (final r in routes)
      if (r.userId.isEmpty || (signedIn && r.userId == viewerId)) r,
  ];
}
