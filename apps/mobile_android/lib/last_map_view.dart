import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local: the camera the routes heatmap was last left on, so a visit
/// with no location fix reopens where the runner was looking rather than on
/// the whole world. Where this phone's owner browses is not a preference to
/// roam, so it lives in raw SharedPreferences.
const kLastBrowseMapViewKey = 'last_browse_map_view';

typedef MapView = ({LatLng center, double zoom});

/// The saved view, or null when there is none or it cannot be read. Never
/// throws: a broken read only costs the fallback.
Future<MapView?> loadLastBrowseMapView() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kLastBrowseMapViewKey);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final lat = (m['lat'] as num).toDouble();
    final lng = (m['lng'] as num).toDouble();
    final zoom = (m['zoom'] as num).toDouble();
    if (lat.abs() > 90 || lng.abs() > 180 || !zoom.isFinite) return null;
    return (center: LatLng(lat, lng), zoom: zoom);
  } catch (e) {
    debugPrint('last map view: read failed: $e');
    return null;
  }
}

/// Saves [view]. Never throws: it runs as the screen closes.
Future<void> saveLastBrowseMapView(MapView view) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kLastBrowseMapViewKey,
      jsonEncode({
        'lat': view.center.latitude,
        'lng': view.center.longitude,
        'zoom': view.zoom,
      }),
    );
  } catch (e) {
    debugPrint('last map view: save failed: $e');
  }
}
