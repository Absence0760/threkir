import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

enum EntityLinkKind { run, route }

/// A run or route the OS opened the app with.
@immutable
class EntityLink {
  final EntityLinkKind kind;
  final String id;

  const EntityLink(this.kind, this.id);

  @override
  bool operator ==(Object other) =>
      other is EntityLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// The run or route an in-app link names: `https://threkir.com/runs/<id>` /
/// `/routes/<id>` (any threkir.com host, so a preview link works too), or the
/// app's own `com.threkir.app://runs/<id>` / `com.threkir.app://routes/<id>`.
/// These are the links an owner hands out at the Followers and Specific
/// people levels (decisions § 1879). Only a UUID id is a link: `/runs/new`,
/// `/routes/heatmap` and `/routes/<id>/roadbook` are other web pages, and a
/// query or fragment is ignored.
EntityLink? parseEntityLink(Uri uri) {
  final List<String> segments;
  if (uri.scheme == 'com.threkir.app') {
    segments = [uri.host, ...uri.pathSegments];
  } else if (uri.scheme == 'https' &&
      (uri.host == 'threkir.com' || uri.host.endsWith('.threkir.com'))) {
    segments = uri.pathSegments;
  } else {
    return null;
  }
  final parts = segments.where((s) => s.isNotEmpty).toList();
  if (parts.length != 2 || !_uuid.hasMatch(parts[1])) return null;
  final kind = switch (parts[0]) {
    'runs' => EntityLinkKind.run,
    'routes' => EntityLinkKind.route,
    _ => null,
  };
  return kind == null ? null : EntityLink(kind, parts[1].toLowerCase());
}

/// Cross-boot handoff for a run or route link. [EntityLinkService] sets it;
/// `HomeScreen` drains it into the owner's detail screen or the non-owner
/// view. Global for the same reason as `pendingClubInviteToken`.
final ValueNotifier<EntityLink?> pendingEntityLink =
    ValueNotifier<EntityLink?>(null);

/// Routes run and route links into [pendingEntityLink]. The OS registration
/// lives in the native projects (the AndroidManifest intent-filters for the
/// `com.threkir.app://runs` / `routes` scheme and the threkir.com host, and
/// the iOS `com.threkir.app` URL type). The link source is injectable so a
/// unit test never opens a platform channel.
class EntityLinkService {
  EntityLinkService({
    Stream<Uri>? links,
    Future<Uri?> Function()? initialLink,
  })  : _links = links ?? AppLinks().uriLinkStream,
        _initialLink = initialLink ?? AppLinks().getInitialLink;

  final Stream<Uri> _links;
  final Future<Uri?> Function() _initialLink;
  StreamSubscription<Uri>? _sub;
  EntityLink? _last;

  void start() {
    _sub ??= _links.listen(
      handle,
      onError: (Object e) => debugPrint('entity link stream error: $e'),
    );
  }

  Future<void> processInitial() async {
    try {
      final uri = await _initialLink();
      if (uri != null) handle(uri);
    } catch (e) {
      debugPrint('entity initial link failed: $e');
    }
  }

  /// The plugin can deliver the cold-start link both from [processInitial]
  /// and on the stream, so a link already handed off is not handed off twice.
  void handle(Uri uri) {
    final link = parseEntityLink(uri);
    if (link == null || link == _last) return;
    _last = link;
    pendingEntityLink.value = link;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
