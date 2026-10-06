import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../lib/avatar_crop.dart';
import '../lib/avatar_crop_image.dart';

/// 40x20, red on the left half and blue on the right, so a crop or a turn is
/// visible in two pixel reads.
img.Image _twoTone() {
  final image = img.Image(width: 40, height: 20);
  for (var y = 0; y < 20; y++) {
    for (var x = 0; x < 40; x++) {
      image.setPixelRgb(x, y, x < 20 ? 255 : 0, 0, x < 20 ? 0 : 255);
    }
  }
  return image;
}

bool _isRed(img.Pixel p) => p.r > 180 && p.b < 80;
bool _isBlue(img.Pixel p) => p.b > 180 && p.r < 80;

bool _contains(Uint8List haystack, String needle) {
  final n = latin1.encode(needle);
  outer:
  for (var i = 0; i + n.length <= haystack.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (haystack[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  test('a sideways photo with Orientation 6 decodes upright, EXIF dropped', () {
    final src = _twoTone();
    src.exif.imageIfd.orientation = 6;
    src.exif.gpsIfd.setGpsLocation(latitude: 51.5, longitude: -0.12);
    final jpeg = img.encodeJpg(src, quality: 100);
    expect(_contains(jpeg, 'Exif'), isTrue, reason: 'fixture carries EXIF');

    final oriented = decodeOrientedAvatar(jpeg)!;
    // Orientation 6 turns the stored 40x20 clockwise, left (red) half on top.
    expect([oriented.width, oriented.height], [20, 40]);
    expect(_isRed(oriented.getPixel(10, 5)), isTrue);
    expect(_isBlue(oriented.getPixel(10, 35)), isTrue);
    expect(oriented.exif.isEmpty, isTrue);
  });

  test('the encoded avatar carries no EXIF, GPS included', () {
    final src = _twoTone();
    src.exif.gpsIfd.setGpsLocation(latitude: 51.5, longitude: -0.12);
    final oriented = decodeOrientedAvatar(img.encodeJpg(src))!;
    final out = encodeAvatarCrop(
      oriented,
      initialCropState(oriented.width, oriented.height, 300),
    );
    expect(_contains(out, 'Exif'), isFalse);
  });

  test('the centre crop is a square of the short side', () {
    final oriented = decodeOrientedAvatar(img.encodePng(_twoTone()))!;
    final out = img.decodeJpg(
      encodeAvatarCrop(
        oriented,
        initialCropState(oriented.width, oriented.height, 300),
      ),
    )!;
    expect([out.width, out.height], [20, 20]);
    expect(_isRed(out.getPixel(5, 10)), isTrue);
    expect(_isBlue(out.getPixel(15, 10)), isTrue);
  });

  test(
    'a clockwise turn puts the left half on top, counter-clockwise the right',
    () {
      final oriented = decodeOrientedAvatar(img.encodePng(_twoTone()))!;
      final start = initialCropState(oriented.width, oriented.height, 300);

      final cw = img.decodeJpg(encodeAvatarCrop(oriented, rotate(start, 1)))!;
      expect(_isRed(cw.getPixel(10, 5)), isTrue);
      expect(_isBlue(cw.getPixel(10, 15)), isTrue);

      final ccw = img.decodeJpg(encodeAvatarCrop(oriented, rotate(start, -1)))!;
      expect(_isBlue(ccw.getPixel(10, 5)), isTrue);
      expect(_isRed(ccw.getPixel(10, 15)), isTrue);
    },
  );

  test('a pan picks the region the viewport shows', () {
    final oriented = decodeOrientedAvatar(img.encodePng(_twoTone()))!;
    // Pan the image right as far as it goes: the viewport shows the left end.
    final s = panBy(initialCropState(40, 20, 300), 1e6, 0);
    final out = img.decodeJpg(encodeAvatarCrop(oriented, s))!;
    expect(_isRed(out.getPixel(3, 10)), isTrue);
    expect(_isRed(out.getPixel(16, 10)), isTrue);
  });

  test('a large source is capped at the avatar size', () {
    final big = img.Image(width: 1600, height: 1200);
    final oriented = decodeOrientedAvatar(img.encodePng(big))!;
    final out = img.decodeJpg(
      encodeAvatarCrop(
        oriented,
        initialCropState(oriented.width, oriented.height, 300),
      ),
    )!;
    expect([out.width, out.height], [avatarOutputMaxPx, avatarOutputMaxPx]);
  });

  test('a source over the working cap is shrunk on decode', () {
    final huge = img.Image(width: 4000, height: 1000);
    final oriented = decodeOrientedAvatar(img.encodePng(huge))!;
    expect([oriented.width, oriented.height], [avatarWorkingMaxPx, 512]);
  });

  test('transparency flattens onto white, not black', () {
    final clear = img.Image(width: 10, height: 10, numChannels: 4);
    final oriented = decodeOrientedAvatar(img.encodePng(clear))!;
    final out = img.decodeJpg(
      encodeAvatarCrop(oriented, initialCropState(10, 10, 300)),
    )!;
    final p = out.getPixel(5, 5);
    expect(p.r > 240 && p.g > 240 && p.b > 240, isTrue, reason: '$p');
  });

  test('bytes no decoder recognises yield null', () {
    expect(decodeOrientedAvatar(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
