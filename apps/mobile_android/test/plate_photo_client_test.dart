import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../lib/payload_hash.dart';
import '../lib/plate_photo_client.dart';

Uint8List _jpeg({bool exif = false}) {
  final parts = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, ...List.filled(14, 0x4a)];
  if (exif) {
    final gps = 'Exif\u0000\u0000GPS-51.5074N'.codeUnits;
    parts.addAll([0xff, 0xe1, 0x00, gps.length + 2, ...gps]);
  }
  parts.addAll([0xff, 0xda, 0x00, 0x08, ...List.generate(80, (i) => i), 0xff, 0xd9]);
  return Uint8List.fromList(parts);
}

PlatePhotoPoster _respond(int status, Object body, {List<Map<String, String>>? seen, List<String>? bodies}) =>
    (url, headers, body0) async {
      seen?.add(headers);
      bodies?.add(body0);
      return PlatePhotoHttpResponse(status, jsonEncode(body));
    };

Future<String?> _token() async => 'tok';

void main() {
  test('platePhotoErrorKind maps each refusal', () {
    expect(platePhotoErrorKind(401, null), PlatePhotoErrorKind.notAuthenticated);
    expect(platePhotoErrorKind(403, {'code': 'ai_disclosure_required'}), PlatePhotoErrorKind.consent);
    expect(platePhotoErrorKind(403, {'upgrade': true}), PlatePhotoErrorKind.proRequired);
    expect(platePhotoErrorKind(403, null), PlatePhotoErrorKind.unavailable);
    expect(platePhotoErrorKind(429, null), PlatePhotoErrorKind.rateLimited);
    expect(platePhotoErrorKind(413, null), PlatePhotoErrorKind.invalid);
    expect(platePhotoErrorKind(422, null), PlatePhotoErrorKind.notUnderstood);
    expect(platePhotoErrorKind(503, null), PlatePhotoErrorKind.unavailable);
  });

  test('parsePlateEstimate drops nameless items and ill-typed numbers', () {
    final e = parsePlateEstimate({
      'meal_slot': 'dinner',
      'items': [
        {'item_name': ' Rice ', 'calories': 205, 'protein_g': -1, 'fat_g': 'x', 'confidence': 'low'},
        {'calories': 100},
        'junk',
      ],
    })!;
    expect(e.mealSlot, 'dinner');
    expect(e.items.length, 1);
    expect(e.items.single.itemName, 'Rice');
    expect(e.items.single.calories, 205);
    expect(e.items.single.proteinG, isNull);
    expect(e.items.single.fatG, isNull);
    expect(e.items.single.lowConfidence, isTrue);
    expect(parsePlateEstimate({'items': [], 'meal_slot': 'brunch'})!.mealSlot, isNull);
    expect(parsePlateEstimate({'nope': 1}), isNull);
  });

  test('the body is metadata-stripped on the device and the note capped', () {
    final body = jsonDecode(platePhotoBody(_jpeg(exif: true), 'x' * 500)) as Map;
    expect(body['media_type'], 'image/jpeg');
    final sent = base64Decode(body['image'] as String);
    expect(String.fromCharCodes(sent).contains('GPS-51.5074N'), isFalse);
    expect((body['note'] as String).length, kMaxPlateNoteChars);
  });

  test('a picture the stripper cannot clean never leaves the device', () {
    expect(
      () => platePhotoBody(Uint8List.fromList(utf8.encode('GIF89a not an image')), ''),
      throwsA(isA<PlatePhotoError>().having((e) => e.kind, 'kind', PlatePhotoErrorKind.invalid)),
    );
  });

  test('a 200 resolves to the estimate with the auth and payload-hash headers', () async {
    final seen = <Map<String, String>>[];
    final e = await requestPlateEstimate(
      _jpeg(),
      'half',
      post: _respond(200, {'items': [{'item_name': 'Toast', 'calories': 90}]}, seen: seen),
      currentToken: _token,
      baseUrl: 'https://example.test',
    );
    expect(e.items.single.itemName, 'Toast');
    expect(seen.single['x-supabase-authorization'], 'Bearer tok');
    expect(seen.single['x-amz-content-sha256'], isNotEmpty);
  });

  test('a refusal throws its kind, and no session is not authenticated', () async {
    await expectLater(
      requestPlateEstimate(_jpeg(), '',
          post: _respond(403, {'upgrade': true}), currentToken: _token, baseUrl: 'https://e.test'),
      throwsA(isA<PlatePhotoError>().having((e) => e.kind, 'kind', PlatePhotoErrorKind.proRequired)),
    );
    await expectLater(
      requestPlateEstimate(_jpeg(), '',
          post: _respond(200, {}), currentToken: () async => null, baseUrl: 'https://e.test'),
      throwsA(isA<PlatePhotoError>().having((e) => e.kind, 'kind', PlatePhotoErrorKind.notAuthenticated)),
    );
  });

  test('a 200 posts the stripped body to the plate-photo path with its own payload hash', () async {
    Uri? url;
    String? sent;
    Map<String, String>? headers;
    final e = await requestPlateEstimate(
      _jpeg(exif: true),
      ' half portion ',
      post: (u, h, b) async {
        url = u;
        headers = h;
        sent = b;
        return PlatePhotoHttpResponse(
            200,
            jsonEncode({
              'meal_slot': 'breakfast',
              'items': [
                {'item_name': '2 fried eggs', 'calories': 180, 'protein_g': 12.5},
              ],
            }));
      },
      currentToken: _token,
      baseUrl: 'https://example.test',
    );
    expect(url.toString(), 'https://example.test/api/coach/plate-photo');
    expect(headers!['x-amz-content-sha256'], payloadSha256Hex(sent!));
    expect(headers!['content-type'], 'application/json');
    final body = jsonDecode(sent!) as Map;
    expect(body['note'], 'half portion');
    expect(String.fromCharCodes(base64Decode(body['image'] as String)).contains('GPS-51.5074N'), isFalse);
    expect(e.mealSlot, 'breakfast');
    expect(e.items.single.proteinG, 12.5);
  });

  test('a 401 refreshes the session once and retries with the new token', () async {
    final seen = <Map<String, String>>[];
    var calls = 0;
    final e = await requestPlateEstimate(
      _jpeg(),
      '',
      post: (url, headers, body) async {
        seen.add(headers);
        calls += 1;
        return calls == 1
            ? PlatePhotoHttpResponse(401, jsonEncode({'error': 'not authenticated'}))
            : PlatePhotoHttpResponse(200, jsonEncode({'items': [{'item_name': 'Toast'}]}));
      },
      currentToken: _token,
      refreshToken: () async => 'fresh',
      baseUrl: 'https://e.test',
    );
    expect(e.items.single.itemName, 'Toast');
    expect(seen.map((h) => h['x-supabase-authorization']), ['Bearer tok', 'Bearer fresh']);
  });

  test('an empty plate resolves to an estimate with no items, not an error', () async {
    final e = await requestPlateEstimate(
      _jpeg(),
      '',
      post: _respond(200, {'items': [], 'meal_slot': null}),
      currentToken: _token,
      baseUrl: 'https://e.test',
    );
    expect(e.items, isEmpty);
    expect(e.mealSlot, isNull);
  });
}
