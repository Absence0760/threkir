import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_disclosure.dart';
import 'l10n/locale_support.dart';
import 'payload_hash.dart';
import 'route_description.dart';
import 'web_base_url.dart';

/// Network glue for the route-detail "Describe this route" affordance.
///
/// The pure, locale/unit-aware templated baseline is built in the screen
/// from [describeRoute]'s parts; this module is the part that needs the
/// Supabase session + an HTTP POST to the Pro-gated enhancement endpoint.
/// It resolves to `{ description, source, upgrade }`, refreshing the JWT
/// once on a 401, mirroring CoachChat. The endpoint itself degrades to
/// the templated text on every failure, so a 200 with `source:'template'`
/// is the normal not-Pro / fallback shape; callers only treat a non-200
/// (or a thrown request) as a hard error and keep the locally-rendered
/// baseline.
///
/// The web counterpart is the module of the same name under `routes/`; the two are network glue rather than a lockstep parity pair, and the PURE half they both call is the registered `route_description` pair — keep the
/// request body shape, the single 401 refresh-and-replay, and the
/// `source`/`upgrade` parsing in lockstep.

class AiDescriptionResult {
  final String description;

  /// 'ai' when the model produced it, 'template' on any server fallback.
  final String source;

  /// True when the server declined because the caller isn't Pro.
  final bool upgrade;

  const AiDescriptionResult({
    required this.description,
    required this.source,
    required this.upgrade,
  });
}

/// The canonical tag (`en`, `pt-PT`, `pt-BR`) for the app's resolved
/// `Localizations` locale — the identifier the endpoint accepts, the same one
/// web sends. Normalised through [negotiateLocale] so the generated delegate's
/// bare `pt` base still reads as the European catalogue it renders.
String routeDescribeLocaleTag(Locale resolved) =>
    localeToTag(negotiateLocale(localeToTag(resolved), const []));

/// The request body. [unit] and [locale] are the viewer's, so the paragraph
/// comes back in the unit and the language they read. [routeId] is how the
/// server decides whether the name may go to the model at all (owner or public
/// route only); `name` only shapes the templated fallback it answers with.
Map<String, dynamic> routeDescribeBody(RouteDescriptionInput input,
        DistanceUnit unit, String locale, String routeId) =>
    {
      'route_id': routeId,
      'name': input.name,
      'distance_m': input.distanceM,
      'elevation_m': input.elevationM,
      'surface': input.surface,
      'start': input.start == null
          ? null
          : {'lat': input.start!.lat, 'lng': input.start!.lng},
      'end': input.end == null
          ? null
          : {'lat': input.end!.lat, 'lng': input.end!.lng},
      'unit': unit.name,
      'locale': locale,
    };

/// Does this non-200 response say the caller has not accepted the AI
/// disclosure the endpoint requires? 403 alone cannot answer it — the
/// paywall uses 403 too, and telling a runner to buy Pro when their actual
/// problem is a missing consent record sends them to buy something that
/// would not unlock the feature. Only the body's `code` decides.
bool isAiDisclosureDenial(int status, String body) {
  if (status != 403) return false;
  try {
    return (jsonDecode(body) as Map<String, dynamic>)['code'] ==
        kAiDisclosureError;
  } catch (_) {
    return false;
  }
}

/// Request an AI-enhanced description. Throws only on a non-200 response
/// or a request failure — a 200 with `source:'template'` (not-Pro, or the
/// server's own fallback) is a normal, non-throwing result. A consent gap
/// throws [kAiDisclosureError] so the caller can lead the runner to the
/// disclosure instead of offering a retry that can never succeed.
Future<AiDescriptionResult> requestAiDescription(RouteDescriptionInput input,
    DistanceUnit unit, String locale, String routeId) async {
  final body = jsonEncode(routeDescribeBody(input, unit, locale, routeId));
  final uri = Uri.parse('${resolveWebBaseUrl()}/api/coach/route-describe');

  String? token = Supabase.instance.client.auth.currentSession?.accessToken;
  if (token == null) throw StateError('not_authenticated');

  // Each call uses a fresh HttpClient so a redirect / error leaves no
  // half-open connection. Production Lambda reads
  // `x-supabase-authorization` only (CloudFront's OAC sigv4-signs the
  // `Authorization` header), matching the coach path.
  Future<HttpClientResponse> postWith(String t) async {
    final c = HttpClient();
    try {
      final r = await c.postUrl(uri);
      r.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      r.headers.set('x-supabase-authorization', 'Bearer $t');
      // CloudFront's Lambda OAC can't hash the body itself — the client
      // supplies the sigv4 payload hash or the Function URL 403s (#590).
      r.headers.set('x-amz-content-sha256', payloadSha256Hex(body));
      r.add(utf8.encode(body));
      return await r.close();
    } catch (_) {
      c.close(force: true);
      rethrow;
    }
  }

  var res = await postWith(token);
  if (res.statusCode == 401) {
    try {
      final refreshed =
          await Supabase.instance.client.auth.refreshSession();
      final newToken = refreshed.session?.accessToken;
      if (newToken != null) {
        token = newToken;
        res = await postWith(newToken);
      }
    } catch (e) {
      debugPrint('route_describe_client: refreshSession failed: $e');
    }
  }

  final raw = await res.transform(utf8.decoder).join();
  if (res.statusCode != 200) {
    // A 403 carrying the AI-disclosure code is a consent gap, not a broken
    // request: the runner has to accept the widened disclosure before the
    // enhancement is lawful. It gets its own error so the screen can lead
    // them there instead of offering a retry that can never succeed — or,
    // worse, a Pro upsell that would not unlock it either.
    if (isAiDisclosureDenial(res.statusCode, raw)) {
      throw StateError(kAiDisclosureError);
    }
    throw StateError('route_describe_failed_${res.statusCode}');
  }
  Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    throw StateError('route_describe_malformed');
  }
  final description = json['description'];
  if (description is! String) {
    throw StateError('route_describe_malformed');
  }
  return AiDescriptionResult(
    description: description,
    source: json['source'] == 'ai' ? 'ai' : 'template',
    upgrade: json['upgrade'] == true,
  );
}
