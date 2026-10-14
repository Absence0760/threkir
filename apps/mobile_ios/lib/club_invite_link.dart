import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

const String _invitePath = '/clubs/join/';

/// The invite token in whatever a runner pasted or the OS opened: a bare
/// code, the web link (`https://threkir.com/clubs/join/<token>`, with or
/// without the scheme, a trailing slash, a query or a fragment, alone or
/// inside a pasted message), or the
/// app's own `com.threkir.app://clubs/join/<token>`. Returns null for blank
/// input and for a link that is not an invite, so the caller asks for the
/// code instead of sending a URL to the RPC as if it were one. Tokens are
/// hex, so anything carrying a `/` without the invite path is a link, not a
/// code. A bare code passes through trimmed and otherwise untouched: the RPC
/// owns validation.
String? parseClubInviteToken(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final at = s.indexOf(_invitePath);
  if (at < 0) return s.contains('/') ? null : s;
  var rest = s.substring(at + _invitePath.length);
  final end = rest.indexOf(RegExp(r'[/?#\s]'));
  if (end >= 0) rest = rest.substring(0, end);
  rest = rest.trim();
  return rest.isEmpty ? null : rest;
}

/// Cross-boot handoff for an invite link the OS opened the app with.
/// [ClubInviteLinkService] sets it; `HomeScreen` drains it into
/// `ClubInviteScreen`. Global for the same reason as `incomingRouteImport`:
/// every launch path lands on HomeScreen.
final ValueNotifier<String?> pendingClubInviteToken =
    ValueNotifier<String?>(null);

/// Routes `/clubs/join/<token>` links into [pendingClubInviteToken]. The OS
/// registration lives in the native projects (the AndroidManifest
/// intent-filters for the `com.threkir.app://clubs` scheme and the
/// threkir.com host, and the iOS `com.threkir.app` URL type). The link
/// source is injectable so a unit test never opens a platform channel.
class ClubInviteLinkService {
  ClubInviteLinkService({
    Stream<Uri>? links,
    Future<Uri?> Function()? initialLink,
  })  : _links = links ?? AppLinks().uriLinkStream,
        _initialLink = initialLink ?? AppLinks().getInitialLink;

  final Stream<Uri> _links;
  final Future<Uri?> Function() _initialLink;
  StreamSubscription<Uri>? _sub;
  String? _lastToken;

  void start() {
    _sub ??= _links.listen(
      handle,
      onError: (Object e) => debugPrint('club invite link stream error: $e'),
    );
  }

  Future<void> processInitial() async {
    try {
      final uri = await _initialLink();
      if (uri != null) handle(uri);
    } catch (e) {
      debugPrint('club invite initial link failed: $e');
    }
  }

  /// The plugin can deliver the cold-start link both from [processInitial]
  /// and on the stream, so a token already handed off is not handed off
  /// twice.
  void handle(Uri uri) {
    final token = parseClubInviteToken(uri.toString());
    if (token == null || token == _lastToken) return;
    _lastToken = token;
    pendingClubInviteToken.value = token;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
