import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// A basemap provider that answers every tile with a 1x1 PNG from memory, so
/// a widget test that draws a map makes no network request.
class HermeticTileProvider extends TileProvider {
  HermeticTileProvider();

  static final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}
