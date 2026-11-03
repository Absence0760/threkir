import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'cold_start_link_echo.dart';
import 'push_target.dart' show PushTarget, PushTargetKind, planTargetFromSegments;
import 'share_ref.dart';

enum EntityLinkKind { run, route }

/// A run or route to open: one the OS opened the app with, or one an in-app
/// surface that holds no run store points at ([openRunLink]).
@immutable
class EntityLink {
  final EntityLinkKind kind;
  final String id;

  /// Open the run's share sheet on its PR card (`?share=pr`, the
  /// personal_record notification's link). Ignored for a route.
  final bool sharePr;

  const EntityLink(this.kind, this.id, {this.sharePr = false});

  @override
  bool operator ==(Object other) =>
      other is EntityLink &&
      other.kind == kind &&
      other.id == id &&
      other.sharePr == sharePr;

  @override
  int get hashCode => Object.hash(kind, id, sharePr);
}

final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// The run or route an in-app link names: `https://threkir.com/runs/<id>` /
/// `/routes/<id>` (any threkir.com host, so a preview link works too), or the
/// app's own `com.threkir.app://runs/<id>` / `com.threkir.app://routes/<id>`.
/// These are the links an owner hands out at the Followers and Specific
/// people levels (decisions § 1879). Only a UUID id is a link: `/runs/new`,
/// `/routes/heatmap` and `/routes/<id>/roadbook` are other web pages. The one
/// query read is a run's `share=pr`; anything else, and the fragment, is
/// ignored.
EntityLink? parseEntityLink(Uri uri) {
  final parts = _linkSegments(uri);
  if (parts == null || parts.length != 2 || !_uuid.hasMatch(parts[1])) return null;
  final kind = switch (parts[0]) {
    'runs' => EntityLinkKind.run,
    'routes' => EntityLinkKind.route,
    _ => null,
  };
  if (kind == null) return null;
  return EntityLink(kind, parts[1].toLowerCase(),
      sharePr: kind == EntityLinkKind.run && uri.queryParameters['share'] == 'pr');
}

/// The non-empty path segments of an in-app link, with the app scheme's host
/// read as the first segment; null for any other scheme or host.
List<String>? _linkSegments(Uri uri) {
  final List<String> segments;
  if (uri.scheme == 'com.threkir.app') {
    segments = [uri.host, ...uri.pathSegments];
  } else if (uri.scheme == 'https' &&
      (uri.host == 'threkir.com' || uri.host.endsWith('.threkir.com'))) {
    segments = uri.pathSegments;
  } else {
    return null;
  }
  return segments.where((s) => s.isNotEmpty).toList(growable: false);
}

/// The plan surface a link names: `com.threkir.app://plans` (the list),
/// `com.threkir.app://plans/<id>` (one plan) and
/// `com.threkir.app://plans/<id>/workouts/<workout id>` (one workout), the
/// links the home-screen widget opens, and the same paths on threkir.com.
/// Shares the push-notification table ([planTargetFromSegments]), so a plan
/// link and a plan push open the same screen. A creator's
/// `https://threkir.com/share/plan/<id>` "Train with me" link opens that
/// public plan's library preview (decisions § 2262). Null for anything else.
PushTarget? parsePlanLink(Uri uri) {
  final parts = _linkSegments(uri);
  if (parts == null || parts.isEmpty) return null;
  // A creator's link carries their ref to the copy it may lead to (§ 2268).
  final ref = parseShareRef(uri.queryParameters[shareRefParam]);
  if (parts.first == 'share') {
    if (parts.length != 3 || parts[1] != 'plan' || !_uuid.hasMatch(parts[2])) {
      return null;
    }
    return PushTarget(PushTargetKind.planLibrary, parts[2].toLowerCase(), null, ref);
  }
  if (parts.first != 'plans') return null;
  final target = planTargetFromSegments(parts);
  if (target.kind == PushTargetKind.planLibrary && ref != null) {
    return PushTarget(PushTargetKind.planLibrary, target.id, null, ref);
  }
  return target;
}

/// Cross-boot handoff for a run or route link. [EntityLinkService] and
/// [openRunLink] set it; `HomeScreen` drains it into the owner's detail screen
/// or the non-owner view. Global for the same reason as
/// `pendingClubInviteToken`.
final ValueNotifier<EntityLink?> pendingEntityLink =
    ValueNotifier<EntityLink?>(null);

/// Opens run [id] through the shell, which holds the run store and so is the
/// one place that can tell the viewer's own run from someone else's. For a
/// surface such as the inbox that cannot construct the owner's detail screen
/// (the shape of `openSettings`, decisions § 710).
void openRunLink(String id, {bool sharePr = false}) {
  pendingEntityLink.value = EntityLink(EntityLinkKind.run, id, sharePr: sharePr);
}

/// Routes run and route links into [pendingEntityLink], and plan links to
/// [onPlanLink] (the shell's push-target handoff). The OS registration lives
/// in the native projects (the AndroidManifest intent-filters for the
/// `com.threkir.app://runs` / `routes` / `plans` scheme and the threkir.com
/// host, and the iOS `com.threkir.app` URL type). The link source is
/// injectable so a unit test never opens a platform channel.
class EntityLinkService {
  EntityLinkService({
    Stream<Uri>? links,
    Future<Uri?> Function()? initialLink,
    this.onPlanLink,
  })  : _links = links ?? AppLinks().uriLinkStream,
        _initialLink = initialLink ?? AppLinks().getInitialLink;

  final Stream<Uri> _links;
  final Future<Uri?> Function() _initialLink;

  /// Receives a plan link; null drops plan links.
  final void Function(PushTarget target)? onPlanLink;

  StreamSubscription<Uri>? _sub;

  final ColdStartLinkEcho _echo = ColdStartLinkEcho();

  void start() {
    _sub ??= _links.listen(
      (uri) {
        if (_echo.acceptStream(uri)) handle(uri);
      },
      onError: (Object e) => debugPrint('entity link stream error: $e'),
    );
  }

  Future<void> processInitial() async {
    try {
      final uri = await _initialLink();
      if (uri != null && _echo.acceptInitial(uri)) handle(uri);
    } catch (e) {
      debugPrint('entity initial link failed: $e');
    }
  }

  void handle(Uri uri) {
    final plan = parsePlanLink(uri);
    if (plan != null) {
      onPlanLink?.call(plan);
      return;
    }
    final link = parseEntityLink(uri);
    if (link != null) pendingEntityLink.value = link;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
