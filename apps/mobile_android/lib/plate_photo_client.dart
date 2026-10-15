import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ai_disclosure.dart';
import 'exif_strip.dart';
import 'nutrition_totals.dart' show mealSlots;
import 'payload_hash.dart';

/// Network glue for the plate-photo logger (decisions § 1972), the mobile
/// half of web's `plate_photo_client.ts`. The picture is metadata-stripped
/// on the device, posted to `/api/coach/plate-photo`, and the proposed items
/// come back for the runner to edit; nothing is saved here.
///
/// The server already whitelists and clamps every field. This parse only
/// refuses to trust a malformed body: a field of the wrong type reads as
/// absent, and an item with no name is dropped.

enum PlatePhotoErrorKind {
  notAuthenticated,
  consent,
  proRequired,
  rateLimited,
  invalid,
  notUnderstood,
  unavailable,
}

class PlatePhotoError implements Exception {
  final PlatePhotoErrorKind kind;
  const PlatePhotoError(this.kind);

  @override
  String toString() => 'PlatePhotoError(${kind.name})';
}

PlatePhotoErrorKind platePhotoErrorKind(int status, Object? body) {
  final map = body is Map ? body : const {};
  if (status == 401) return PlatePhotoErrorKind.notAuthenticated;
  if (status == 403 && map['code'] == kAiDisclosureError) {
    return PlatePhotoErrorKind.consent;
  }
  if (status == 403 && map['upgrade'] == true) {
    return PlatePhotoErrorKind.proRequired;
  }
  if (status == 429) return PlatePhotoErrorKind.rateLimited;
  if (status == 400 || status == 413) return PlatePhotoErrorKind.invalid;
  if (status == 422) return PlatePhotoErrorKind.notUnderstood;
  return PlatePhotoErrorKind.unavailable;
}

/// The long edge the model reads at; the picker resizes to it so the upload
/// carries nothing the model would discard.
const double kPlateUploadLongEdgePx = 1568;
const int kPlateUploadJpegQuality = 85;
const int kMaxPlateNoteChars = 200;

class PlateItem {
  final String itemName;
  final bool lowConfidence;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sugarG;
  final double? saturatedFatG;
  final double? sodiumMg;
  final double? cholesterolMg;

  const PlateItem({
    required this.itemName,
    this.lowConfidence = false,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sugarG,
    this.saturatedFatG,
    this.sodiumMg,
    this.cholesterolMg,
  });
}

class PlateEstimate {
  final List<PlateItem> items;
  final String? mealSlot;
  const PlateEstimate(this.items, this.mealSlot);
}

double? _num(Object? v) {
  if (v is! num || !v.isFinite || v < 0) return null;
  return v.toDouble();
}

/// Parse a 200 body, or null when it is not an estimate at all.
PlateEstimate? parsePlateEstimate(Object? json) {
  if (json is! Map || json['items'] is! List) return null;
  final items = <PlateItem>[];
  for (final e in json['items'] as List) {
    if (e is! Map) continue;
    final name = e['item_name'];
    if (name is! String || name.trim().isEmpty) continue;
    items.add(PlateItem(
      itemName: name.trim(),
      lowConfidence: e['confidence'] == 'low',
      calories: _num(e['calories']),
      proteinG: _num(e['protein_g']),
      carbsG: _num(e['carbs_g']),
      fatG: _num(e['fat_g']),
      fiberG: _num(e['fiber_g']),
      sugarG: _num(e['sugar_g']),
      saturatedFatG: _num(e['saturated_fat_g']),
      sodiumMg: _num(e['sodium_mg']),
      cholesterolMg: _num(e['cholesterol_mg']),
    ));
  }
  final slot = json['meal_slot'];
  return PlateEstimate(items, mealSlots.contains(slot) ? slot as String : null);
}

/// The request body for one picture: metadata stripped on the device (the
/// server strips again regardless), refused when it is not a format the
/// stripper can clean, so a capture GPS tag never leaves the phone.
@visibleForTesting
String platePhotoBody(Uint8List bytes, String note) {
  final mime = detectImageMime(bytes);
  if (mime == null) throw const PlatePhotoError(PlatePhotoErrorKind.invalid);
  final clean = stripImageExif(bytes, mime);
  final trimmed = note.trim();
  return jsonEncode({
    'image': base64Encode(clean),
    'media_type': mime,
    'note': trimmed.length > kMaxPlateNoteChars
        ? trimmed.substring(0, kMaxPlateNoteChars)
        : trimmed,
  });
}

class PlatePhotoHttpResponse {
  final int statusCode;
  final String body;
  const PlatePhotoHttpResponse(this.statusCode, this.body);
}

typedef PlatePhotoPoster = Future<PlatePhotoHttpResponse> Function(
  Uri url,
  Map<String, String> headers,
  String body,
);

Future<PlatePhotoHttpResponse> _defaultPost(
  Uri url,
  Map<String, String> headers,
  String body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    headers.forEach(req.headers.set);
    req.add(utf8.encode(body));
    final res = await req.close();
    final raw = await res.transform(utf8.decoder).join();
    return PlatePhotoHttpResponse(res.statusCode, raw);
  } finally {
    client.close(force: true);
  }
}

String _webBase() =>
    ((dotenv.isInitialized ? dotenv.maybeGet('WEB_BASE_URL') : null) ??
            'https://threkir.com')
        .replaceAll(RegExp(r'/$'), '');

Future<String?> _currentToken() async =>
    Supabase.instance.client.auth.currentSession?.accessToken;

Future<String?> _refreshToken() async =>
    (await Supabase.instance.client.auth.refreshSession())
        .session
        ?.accessToken;

Future<PlateEstimate> requestPlateEstimate(
  Uint8List bytes,
  String note, {
  PlatePhotoPoster? post,
  Future<String?> Function()? currentToken,
  Future<String?> Function()? refreshToken,
  String? baseUrl,
}) async {
  final send = post ?? _defaultPost;
  final body = platePhotoBody(bytes, note);
  final uri = Uri.parse('${baseUrl ?? _webBase()}/api/coach/plate-photo');
  // Production Lambda reads `x-supabase-authorization` only, and CloudFront's
  // OAC cannot hash the body, so the client supplies the payload hash (#590).
  final hash = payloadSha256Hex(body);
  Map<String, String> headersFor(String token) => {
        HttpHeaders.contentTypeHeader: 'application/json',
        'x-supabase-authorization': 'Bearer $token',
        'x-amz-content-sha256': hash,
      };

  String? token;
  try {
    token = await (currentToken ?? _currentToken)();
  } catch (e) {
    debugPrint('plate_photo_client: session lookup failed: $e');
  }
  if (token == null) {
    throw const PlatePhotoError(PlatePhotoErrorKind.notAuthenticated);
  }

  PlatePhotoHttpResponse res;
  try {
    res = await send(uri, headersFor(token), body);
    if (res.statusCode == 401) {
      try {
        final refreshed = await (refreshToken ?? _refreshToken)();
        if (refreshed != null) res = await send(uri, headersFor(refreshed), body);
      } catch (e) {
        debugPrint('plate_photo_client: refreshSession failed: $e');
      }
    }
  } catch (e) {
    debugPrint('plate_photo_client: request failed: $e');
    throw const PlatePhotoError(PlatePhotoErrorKind.unavailable);
  }

  Object? json;
  try {
    json = jsonDecode(res.body);
  } catch (_) {
    json = null;
  }
  if (res.statusCode != 200) {
    throw PlatePhotoError(platePhotoErrorKind(res.statusCode, json));
  }
  final estimate = parsePlateEstimate(json);
  if (estimate == null) {
    throw const PlatePhotoError(PlatePhotoErrorKind.unavailable);
  }
  return estimate;
}
