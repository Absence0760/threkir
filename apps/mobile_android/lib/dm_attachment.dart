/// What a message bubble renders, given the typed route attachment
/// (`direct_messages.route_id`, migration `20270619_001`) and how far its
/// resolution has got.
///
/// Mirrors `apps/web/src/lib/social/dm_attachment.ts` — keep both in
/// lockstep. The mirror suite is `test/dm_attachment_test.dart`.
///
/// `unavailable` never collapses to `text`: a route the reader may not see
/// would then render as an ordinary message whose body is a share URL that
/// opens nothing, and "this route is gone" would read as "someone typed a
/// link". `pending` never collapses to `card`: a card drawn before the route
/// resolves is a route with no name and no trace, which reads as broken.
library;

class DmRouteCard {
  const DmRouteCard({
    required this.id,
    required this.name,
    required this.distanceM,
    required this.waypoints,
  });

  final String id;

  /// Null when the row's name is blank, so the render supplies a localized
  /// fallback. `routes.name` is `not null` with no length CHECK.
  final String? name;
  final double? distanceM;
  final List<({double lat, double lng})> waypoints;
}

sealed class DmAttachmentResolution {
  const DmAttachmentResolution();
}

class DmAttachmentPending extends DmAttachmentResolution {
  const DmAttachmentPending();
}

class DmAttachmentResolved extends DmAttachmentResolution {
  const DmAttachmentResolved(this.route);
  final DmRouteCard? route;
}

sealed class DmAttachmentView {
  const DmAttachmentView();
}

class DmAttachmentText extends DmAttachmentView {
  const DmAttachmentText();
}

class DmAttachmentLoading extends DmAttachmentView {
  const DmAttachmentLoading();
}

class DmAttachmentCard extends DmAttachmentView {
  const DmAttachmentCard(this.route);
  final DmRouteCard route;
}

class DmAttachmentUnavailable extends DmAttachmentView {
  const DmAttachmentUnavailable();
}

/// An empty or whitespace id is not an attachment.
bool hasDmRouteAttachment(String? routeId) =>
    routeId != null && routeId.trim().isNotEmpty;

DmAttachmentView dmAttachmentView(
  String? routeId,
  DmAttachmentResolution? resolution,
) {
  if (!hasDmRouteAttachment(routeId)) return const DmAttachmentText();
  if (resolution == null || resolution is DmAttachmentPending) {
    return const DmAttachmentLoading();
  }
  final route = (resolution as DmAttachmentResolved).route;
  return route == null ? const DmAttachmentUnavailable() : DmAttachmentCard(route);
}

/// Whether the message body says nothing the card does not already say.
///
/// The send keeps the route's share URL in the body because the inbox
/// preview and the Art 20 export read the body and resolve no attachment
/// (decisions § 772). On screen it duplicates the card, so it is suppressed
/// there — and only when it is an absolute URL pointing at THIS route's own
/// share or detail path. Anything a human could have typed renders beside
/// the card.
bool bodyRestatesAttachment(String body, String routeId) {
  final trimmed = body.trim();
  final id = routeId.trim().toLowerCase();
  if (trimmed.isEmpty || id.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '').toLowerCase();
  return path == '/share/route/$id' || path == '/routes/$id';
}

/// Narrow a route read through `ApiClient.fetchRouteById` into what the card
/// draws. The waypoints handed over are already the reader's own view of the
/// line — unclipped for the owner, privacy-zone-clipped by
/// `clip_route_for_viewer` for everyone else — so this never widens a read.
///
/// [waypoints] is a list of `(lat:, lng:)` records or the `{lat, lng}` maps
/// the wire carries; anything else in it is dropped.
DmRouteCard dmRouteCardFrom({
  required String id,
  Object? name,
  Object? distanceM,
  Object? waypoints,
}) {
  final trimmed = name is String ? name.trim() : '';
  final distance = switch (distanceM) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };
  return DmRouteCard(
    id: id,
    name: trimmed.isEmpty ? null : trimmed,
    distanceM:
        distance != null && distance.isFinite && distance > 0 ? distance : null,
    waypoints: [
      if (waypoints is List)
        for (final p in waypoints)
          if (_point(p) case final point?) point,
    ],
  );
}

({double lat, double lng})? _point(Object? p) {
  if (p is ({double lat, double lng})) {
    return p.lat.isFinite && p.lng.isFinite ? p : null;
  }
  if (p is Map) {
    final lat = p['lat'];
    final lng = p['lng'];
    if (lat is num && lng is num && lat.isFinite && lng.isFinite) {
      return (lat: lat.toDouble(), lng: lng.toDouble());
    }
  }
  return null;
}

/// A card with fewer than two usable points has no line to draw. The trace
/// failing is not the route failing — the clip fails closed to `[]` — so the
/// card still renders its name and distance and only the thumbnail falls back.
bool dmRouteCardHasTrace(DmRouteCard card) => card.waypoints.length > 1;
