import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppRadius;

import '../dm_attachment.dart';
import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../screens/public_route_screen.dart';
import 'track_preview.dart';

/// A route shared in a direct message, drawn as a card. Mirrors web's
/// `DmRouteAttachment.svelte`.
///
/// The one read path is `ApiClient.fetchRouteById`, which is owner-aware: the
/// bare `routes` row for the owner, and for everyone else the `public_routes`
/// / `shared_routes` view plus `clip_route_for_viewer`, so the line a
/// recipient is drawn has already had the sender's privacy zones removed on
/// the server. That is why the thumbnail can be a bare [TrackPreview]: the
/// points it is handed are the reader's own view of the route.
class DmRouteAttachment extends StatefulWidget {
  const DmRouteAttachment({
    super.key,
    required this.api,
    required this.routeId,
    this.refreshTick = 0,
    this.onOpen,
    this.now = DateTime.now,
  });

  final ApiClient api;
  final String routeId;

  /// Bumped by the conversation each time it re-reads. A card with no fresh
  /// answer, because its read threw or its cached answer expired, reads again
  /// on the next bump, so it recovers at the conversation's own poll cadence.
  final int refreshTick;

  /// Opens the route. Defaults to the shared-route screen, the same surface a
  /// `/routes/{id}` link opens.
  final void Function(BuildContext context, String routeId)? onOpen;

  final DateTime Function() now;

  @override
  State<DmRouteAttachment> createState() => _DmRouteAttachmentState();
}

/// How long an answer is trusted. A route the reader may not see can become
/// visible (the sender shares or publishes it), and a card drawn from a
/// fail-closed empty clip is indistinguishable here from a route clipped to
/// nothing, so no answer is kept for the life of the process.
const Duration kDmRouteAttachmentCacheTtl = Duration(minutes: 5);

typedef _Cached = ({DmRouteCard? card, DateTime at});

class _DmRouteAttachmentState extends State<DmRouteAttachment> {
  // Bounded LRU like RouteTrackPreview's. Keyed by viewer as well as route:
  // what fetchRouteById answers IS that viewer's clip, so a cache shared across
  // a sign-out would serve one reader another reader's line. Only an answer
  // the read gave is stored; a read that threw is not an answer.
  static const int _cacheMax = 100;
  static final Map<String, _Cached> _cache = {};

  static void _cacheSet(String key, DmRouteCard? card, DateTime at) {
    _cache.remove(key);
    if (_cache.length >= _cacheMax) _cache.remove(_cache.keys.first);
    _cache[key] = (card: card, at: at);
  }

  _Cached? _fresh(String key) {
    final hit = _cache[key];
    if (hit == null) return null;
    if (widget.now().difference(hit.at) < kDmRouteAttachmentCacheTtl) {
      return hit;
    }
    _cache.remove(key);
    return null;
  }

  DmAttachmentResolution _resolution = const DmAttachmentPending();
  String? _reading;

  String get _key => '${widget.api.userId ?? 'anon'}:${widget.routeId}';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(DmRouteAttachment old) {
    super.didUpdateWidget(old);
    if (old.routeId != widget.routeId) {
      _resolution = const DmAttachmentPending();
      _resolve();
    } else if (old.refreshTick != widget.refreshTick && _fresh(_key) == null) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final key = _key;
    final hit = _fresh(key);
    if (hit != null) {
      _resolution = DmAttachmentResolved(hit.card);
      return;
    }
    if (_reading == key) return;
    _reading = key;
    DmRouteCard? card;
    try {
      final read = await widget.api.fetchRouteById(widget.routeId);
      final route = read.route;
      card = route == null
          ? null
          : dmRouteCardFrom(
              id: route.id,
              name: route.name,
              distanceM: route.distanceMetres,
              waypoints: [
                for (final w in route.waypoints) (lat: w.lat, lng: w.lng),
              ],
            );
      _cacheSet(key, card, widget.now());
    } catch (e) {
      // Drawn as unavailable for now, which is all that may be claimed about
      // a route we could not resolve, but not cached: the next refresh reads
      // it again.
      debugPrint('dm route attachment read failed: ${safeErrorLabel(e)}');
      card = null;
    } finally {
      if (_reading == key) _reading = null;
    }
    if (mounted && key == _key) {
      setState(() => _resolution = DmAttachmentResolved(card));
    }
  }

  void _open(DmRouteCard card) {
    final onOpen = widget.onOpen;
    if (onOpen != null) return onOpen(context, card.id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicRouteScreen(api: widget.api, routeId: card.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return switch (dmAttachmentView(widget.routeId, _resolution)) {
      DmAttachmentText() => const SizedBox.shrink(),
      DmAttachmentLoading() => Semantics(
          key: const ValueKey('dm-route-attachment-pending'),
          label: l10n.messagesRouteLoading,
          child: Container(
            height: 64,
            width: 220,
            decoration: ShapeDecoration(
              shape: shape,
              color: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ),
      DmAttachmentUnavailable() => Container(
          key: const ValueKey('dm-route-attachment-unavailable'),
          padding: const EdgeInsets.all(10),
          decoration: ShapeDecoration(
            shape: shape,
            color: theme.colorScheme.surface,
          ),
          child: Text(
            l10n.messagesRouteUnavailable,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      DmAttachmentCard(:final route) => Material(
          key: const ValueKey('dm-route-attachment'),
          color: theme.colorScheme.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _open(route),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 88,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                      child: dmRouteCardHasTrace(route)
                          ? TrackPreview(
                              points: [
                                for (final p in route.waypoints)
                                  Waypoint(lat: p.lat, lng: p.lng),
                              ],
                              aspect: 88 / 56,
                            )
                          : ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.map_outlined,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.messagesRouteEyebrow.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          route.name ?? l10n.messagesRouteUntitled,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (route.distanceM != null)
                          Text(
                            formatDistanceForPref(route.distanceM!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
        ),
    };
  }
}
