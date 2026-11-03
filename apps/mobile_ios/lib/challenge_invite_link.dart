import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'cold_start_link_echo.dart';
import 'share_ref.dart';

/// A challenge link the OS opened the app with (decisions § 2261): a creator's
/// invite (`/challenges/join/<token>`), which joins a challenge that need not
/// be public, or a public challenge's share page (`/share/challenge/<id>`).
@immutable
sealed class ChallengeLink {
  const ChallengeLink();
}

@immutable
class ChallengeInviteLink extends ChallengeLink {
  final String token;
  const ChallengeInviteLink(this.token);

  @override
  bool operator ==(Object other) =>
      other is ChallengeInviteLink && other.token == token;

  @override
  int get hashCode => token.hashCode;
}

@immutable
class ChallengeShareLink extends ChallengeLink {
  final String challengeId;

  /// The creator's `ref` the link carried, for the join it may lead to
  /// (decisions § 2268).
  final String? shareRef;
  const ChallengeShareLink(this.challengeId, {this.shareRef});

  @override
  bool operator ==(Object other) =>
      other is ChallengeShareLink &&
      other.challengeId == challengeId &&
      other.shareRef == shareRef;

  @override
  int get hashCode => Object.hash(challengeId, shareRef);
}

final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// Tokens are url-safe base64 (`[A-Za-z0-9_-]`); anything else is not one.
final RegExp _token = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

/// The challenge a link names: `https://threkir.com/challenges/join/<token>`
/// or `/share/challenge/<uuid>` (any threkir.com host, so a preview link
/// works too), or the app's own `com.threkir.app://challenges/join/<token>`.
/// A query or fragment is ignored. Null for anything else.
ChallengeLink? parseChallengeLink(Uri uri) {
  final List<String> segments;
  if (uri.scheme == 'com.threkir.app') {
    segments = [uri.host, ...uri.pathSegments];
  } else if (uri.scheme == 'https' &&
      (uri.host == 'threkir.com' || uri.host.endsWith('.threkir.com'))) {
    segments = uri.pathSegments;
  } else {
    return null;
  }
  final parts = segments.where((s) => s.isNotEmpty).toList(growable: false);
  if (parts.length != 3) return null;
  if (parts[0] == 'challenges' && parts[1] == 'join' && _token.hasMatch(parts[2])) {
    return ChallengeInviteLink(parts[2]);
  }
  if (parts[0] == 'share' && parts[1] == 'challenge' && _uuid.hasMatch(parts[2])) {
    return ChallengeShareLink(parts[2].toLowerCase(),
        shareRef: parseShareRef(uri.queryParameters[shareRefParam]));
  }
  return null;
}

/// The web link a creator hands out for [token].
String challengeInvitePath(String token) =>
    '/challenges/join/${Uri.encodeComponent(token)}';

/// The public share page for challenge [id].
String challengeSharePath(String id) => '/share/challenge/$id';

/// Cross-boot handoff for a challenge link. [ChallengeLinkService] sets it;
/// `HomeScreen` drains it. Global for the same reason as
/// `pendingClubInviteToken`: every launch path lands on HomeScreen, and a
/// link opened signed out waits here through sign-in and sign-up.
final ValueNotifier<ChallengeLink?> pendingChallengeLink =
    ValueNotifier<ChallengeLink?>(null);

/// Routes challenge links into [pendingChallengeLink]. The OS registration
/// lives in the native projects (the AndroidManifest intent-filters and the
/// iOS associated domains backed by `apple-app-site-association`). The link
/// source is injectable so a unit test never opens a platform channel.
class ChallengeLinkService {
  ChallengeLinkService({
    Stream<Uri>? links,
    Future<Uri?> Function()? initialLink,
  })  : _links = links ?? AppLinks().uriLinkStream,
        _initialLink = initialLink ?? AppLinks().getInitialLink;

  final Stream<Uri> _links;
  final Future<Uri?> Function() _initialLink;
  StreamSubscription<Uri>? _sub;
  final ColdStartLinkEcho _echo = ColdStartLinkEcho();

  void start() {
    _sub ??= _links.listen(
      (uri) {
        if (_echo.acceptStream(uri)) handle(uri);
      },
      onError: (Object e) => debugPrint('challenge link stream error: $e'),
    );
  }

  Future<void> processInitial() async {
    try {
      final uri = await _initialLink();
      if (uri != null && _echo.acceptInitial(uri)) handle(uri);
    } catch (e) {
      debugPrint('challenge initial link failed: $e');
    }
  }

  void handle(Uri uri) {
    final link = parseChallengeLink(uri);
    if (link != null) pendingChallengeLink.value = link;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
