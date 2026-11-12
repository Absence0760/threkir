// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../lib/dm_image.dart';
import '../lib/dm_image_encode.dart';

/// The markers of every segment before the scan: what a JPEG says about
/// itself, as opposed to its pixels.
List<int> _headerMarkers(Uint8List jpeg) {
  final out = <int>[];
  var i = 2;
  while (i + 3 < jpeg.length && jpeg[i] == 0xFF) {
    final marker = jpeg[i + 1];
    out.add(marker);
    if (marker == 0xDA) break;
    i += 2 + ((jpeg[i + 2] << 8) | jpeg[i + 3]);
  }
  return out;
}

bool _contains(Uint8List bytes, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// A camera-style JPEG: a GPS position and an orientation tag that says the
/// pixels are stored turned a quarter.
Uint8List _geotagged({required int width, required int height}) {
  final src = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(200, 40, 40));
  src.exif.imageIfd.orientation = 6;
  src.exif.gpsIfd.setGpsLocation(latitude: 51.5007, longitude: -0.1246);
  return img.encodeJpg(src, quality: 90);
}

void main() {
  test('a geotagged photo comes out with no EXIF block, upright and fitted',
      () {
    final input = _geotagged(width: 3000, height: 1000);
    expect(_headerMarkers(input), contains(0xE1),
        reason: 'the fixture must carry the APP1 block the encode removes');
    expect(_contains(input, ascii.encode('Exif')), isTrue);

    final out = encodeDmImage(input);

    expect(out.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    expect(_headerMarkers(out), isNot(contains(0xE1)));
    expect(_headerMarkers(out), isNot(contains(0xE2)));
    expect(_contains(out, ascii.encode('Exif')), isFalse);
    final decoded = img.decodeJpg(out)!;
    expect(decoded.exif.isEmpty, isTrue);
    expect(decoded.exif.gpsIfd.hasGPSLatitude, isFalse);
    final fit = dmImageFit(1000, 3000);
    expect((decoded.width, decoded.height), (fit.width, fit.height));
    expect(decoded.height, kDmImageMaxEdge);
    expect(out.length, lessThanOrEqualTo(kDmImageMaxBytes));
  });

  test('a small photo keeps its size and still loses its metadata', () {
    final src = img.Image(width: 40, height: 30)..clear(img.ColorRgb8(1, 2, 3));
    src.exif.gpsIfd.setGpsLocation(latitude: -33.86, longitude: 151.21);
    final out = encodeDmImage(img.encodePng(src));
    final decoded = img.decodeJpg(out)!;
    expect((decoded.width, decoded.height), (40, 30));
    expect(_contains(out, ascii.encode('Exif')), isFalse);
  });

  test('a file that is not a photo is refused as unreadable', () {
    expect(
      () => encodeDmImage(Uint8List.fromList(utf8.encode('<svg></svg>'))),
      throwsA(isA<DmImageEncodeError>()
          .having((e) => e.kind, 'kind', DmImageEncodeFailure.unreadable)),
    );
    expect(
      () => encodeDmImage(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x01])),
      throwsA(isA<DmImageEncodeError>()
          .having((e) => e.kind, 'kind', DmImageEncodeFailure.unreadable)),
    );
  });

  test('a photo still over the limit at the lowest quality is refused', () {
    expect(
      () => encodeDmImage(_geotagged(width: 200, height: 200), maxBytes: 10),
      throwsA(isA<DmImageEncodeError>()
          .having((e) => e.kind, 'kind', DmImageEncodeFailure.tooLarge)),
    );
  });

  test('quality steps down the way web does', () {
    expect(kDmImageQualitySteps, [kDmImageQuality, 70, 55]);
  });
}
