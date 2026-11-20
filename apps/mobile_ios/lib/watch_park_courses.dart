import 'dart:async';
import 'dart:convert';

import 'package:core_models/core_models.dart' show ParkCourseListing;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apple_watch_route_bridge.dart' show AppleWatchRouteBridge;
import 'gate_crossing.dart' show Gate;
import 'live_course_timing.dart' show liveCourseGeometry;
import 'route_simplify.dart' show simplifyToBudget;

/// Courses one `/park_courses` push carries. Under the watch's own
/// `PARK_COURSES_MAX` (20) on purpose: the Wearable Data Layer refuses an
/// item past ~100 KB, and eight courses at [kMaxWearParkCourseWaypoints]
/// line points plus 50 checkpoints each come to about 90 KB of JSON, the
/// worst case. [kWearParkCoursesMaxBytes] still guards the total.
const int kMaxWearParkCourses = 8;

/// Line points per course on the push. The line is the map and the
/// "X to go" badge on the wrist, never the timing (that is the two lines and
/// the checkpoints, sent exact), so it is thinned by the same priority
/// Douglas-Peucker pass the Apple Watch's starred list uses, keeping both
/// ends. 200 points on a 10 km course is a vertex every ~50 m.
const int kMaxWearParkCourseWaypoints = 200;

/// The JSON text budget for `courses_json`, under the Data Layer's ~100 KB
/// per-item ceiling with room for the other two keys. The oldest course is
/// dropped until the list fits.
const int kWearParkCoursesMaxBytes = 90 * 1024;

/// The watch's receive rules (`ParkCourseBridge.kt`), restated so the phone
/// never sends a course the wrist would refuse. Held against
/// `fixtures/wear_park_courses_payload.json` by the test, which is the one
/// place both sides are read.
const int _kWatchMaxCheckpoints = 50;
const int _kWatchMaxWaypoints = 1000;
const double _kWatchMaxDistanceM = 1000000;
const double _kWatchMinHalfWidthM = 5;
const double _kWatchMaxHalfWidthM = 100;

double _round6(double v) => (v * 1e6).roundToDouble() / 1e6;

Map<String, Object> _gate(Gate g) => {
      'lat': g.lat,
      'lng': g.lng,
      'bearing_deg': g.bearingDeg,
      'half_width_m': g.halfWidthM,
    };

/// One course of the `/park_courses` push for [listing], or null when the
/// wrist could not time it: the phone's own live rule ([liveCourseGeometry])
/// and then every rule the watch reads by ([wearParkCourseReadable]).
///
/// Everything here is public catalogue data: the `global_segments` row's
/// lines, length and polyline, and the `park_courses` row's id, route id,
/// laps and checkpoints. No privacy-zone clipping applies, and nothing of the
/// runner's travels.
Map<String, Object?>? wearParkCourseFor(ParkCourseListing listing) {
  final geometry = liveCourseGeometry(listing);
  if (geometry == null) return null;
  final line = simplifyToBudget(
    geometry.points,
    maxPoints: kMaxWearParkCourseWaypoints,
  );
  final course = <String, Object?>{
    'id': listing.course.id,
    'route_id': listing.course.routeId,
    'name': listing.segment.name,
    'distance_m': geometry.distanceM,
    'laps': listing.course.laps,
    'start_gate': _gate(geometry.startGate!),
    'end_gate': _gate(geometry.endGate!),
    'checkpoints': [
      for (final c in geometry.checkpoints) {'lat': c.lat, 'lng': c.lng},
    ],
    'waypoints': [
      for (final w in line) {'lat': _round6(w.lat), 'lng': _round6(w.lng)},
    ],
  };
  return wearParkCourseReadable(course) ? course : null;
}

/// Whether the watch's `parseParkCourse` keeps [course] (a decoded JSON
/// object). A restatement of its rules, checked against the fixture's kept
/// and refused cases, so a writer change that would ship a refused course
/// fails here rather than on a wrist that silently drops the row.
bool wearParkCourseReadable(Object? course) {
  if (course is! Map) return false;
  String? str(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  double? numOf(Object? v) =>
      v is num && v.toDouble().isFinite ? v.toDouble() : null;
  bool point(Object? v) {
    if (v is! Map) return false;
    final lat = numOf(v['lat']);
    final lng = numOf(v['lng']);
    return lat != null && lng != null && lat.abs() < 90 && lng.abs() <= 180;
  }

  bool gate(Object? v) {
    if (!point(v)) return false;
    final g = v as Map;
    final halfWidth = numOf(g['half_width_m']);
    return numOf(g['bearing_deg']) != null &&
        halfWidth != null &&
        halfWidth >= _kWatchMinHalfWidthM &&
        halfWidth <= _kWatchMaxHalfWidthM;
  }

  if (str(course['id']) == null || str(course['name']) == null) return false;
  final routeId = course['route_id'];
  if (routeId != null && str(routeId) == null) return false;
  final distance = numOf(course['distance_m']);
  if (distance == null || distance <= 0 || distance > _kWatchMaxDistanceM) {
    return false;
  }
  final laps = course['laps'];
  if (laps != null && (laps is! int || laps < 1 || laps > 1000)) return false;
  if (!gate(course['start_gate']) || !gate(course['end_gate'])) return false;
  final checkpoints = course['checkpoints'];
  if (checkpoints is! List || checkpoints.length > _kWatchMaxCheckpoints) {
    return false;
  }
  if (!checkpoints.every(point)) return false;
  final waypoints = course['waypoints'];
  if (waypoints is! List ||
      waypoints.length < 2 ||
      waypoints.length > _kWatchMaxWaypoints) {
    return false;
  }
  return waypoints.every(point);
}

/// The courses a push carries out of [newestFirst]: readable ones only, the
/// first of a repeated id, at most [kMaxWearParkCourses], and then the
/// oldest dropped until the JSON text fits [kWearParkCoursesMaxBytes].
List<Map<String, Object?>> pickWearParkCourses(
  List<Map<String, Object?>> newestFirst,
) {
  final seen = <String>{};
  final out = <Map<String, Object?>>[];
  for (final c in newestFirst) {
    if (out.length == kMaxWearParkCourses) break;
    if (!wearParkCourseReadable(c)) continue;
    if (!seen.add(c['id'] as String)) continue;
    out.add(c);
  }
  while (out.isNotEmpty &&
      utf8.encode(jsonEncode(out)).length > kWearParkCoursesMaxBytes) {
    out.removeLast();
  }
  return out;
}

/// Keeps both watches holding the park courses the runner is about to run
/// (#1446, decisions § 2595), so the wrist can time them live.
///
/// **Which courses.** The ones the runner opened "Navigate this course" on,
/// newest first, up to [kMaxWearParkCourses], kept on the phone across
/// launches. That is the one signal on the phone that a runner means to run a
/// course (park courses cannot be starred: their routes belong to the
/// official club, and `is_starred` is per owner), the course being navigated
/// is always at the top, and it is all public catalogue geometry. Courses go
/// to the Wear OS picker as rows; the Apple Watch holds one armed course, so
/// it gets the one being navigated, with its line as the armed route.
///
/// **When.** On every Navigate, on startup (so a watch paired since, or a
/// list a failed push left behind, catches up), and on sign-out, which
/// empties the list on both wrists: which parks someone runs is theirs.
///
/// Fire-and-forget throughout. Nothing on the phone waits on it, and every
/// failure is logged and left for the next push; recording and the run
/// screen never touch it.
class WatchParkCourses {
  factory WatchParkCourses() => _instance;

  WatchParkCourses._();

  static final WatchParkCourses _instance = WatchParkCourses._();

  @visibleForTesting
  static const String wearChannelName = 'run_app/wear_park_courses';

  @visibleForTesting
  static const String prefsKey = 'watch_park_courses_v1';

  static const _wear = MethodChannel(wearChannelName);

  /// The last `courses_json` that reached the native side.
  String? _lastPushed;

  @visibleForTesting
  void resetForTest() => _lastPushed = null;

  /// State the stored list to the Wear OS watch. Called once at startup.
  Future<void> attach() async {
    _lastPushed = null;
    await _publishWear(await _load());
  }

  /// The runner opened "Navigate this course" on [listing].
  Future<void> courseNavigated(ParkCourseListing listing) async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final course = wearParkCourseFor(listing);
          if (course == null) {
            debugPrint('park course ${listing.course.id}: not timeable on a '
                'watch, not sent');
            return;
          }
          final list = pickWearParkCourses([
            course,
            for (final c in await _load())
              if (c['id'] != course['id']) c,
          ]);
          await _save(list);
          await _publishWear(list);
        case TargetPlatform.iOS:
          await AppleWatchRouteBridge.armParkCourse(listing);
        default:
          return;
      }
    } catch (e) {
      debugPrint('watch park course push failed: $e');
    }
  }

  /// Sign-out: forget the list and empty it on both wrists.
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (e) {
      debugPrint('watch park courses clear failed: $e');
    }
    await _publishWear(const []);
    await AppleWatchRouteBridge.clearParkCourse();
  }

  Future<List<Map<String, Object?>>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return pickWearParkCourses([
        for (final c in decoded)
          if (c is Map) c.cast<String, Object?>(),
      ]);
    } catch (e) {
      debugPrint('watch park courses read failed: $e');
      return const [];
    }
  }

  Future<void> _save(List<Map<String, Object?>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode(list));
    } catch (e) {
      debugPrint('watch park courses write failed: $e');
    }
  }

  /// An empty list is a value: it clears the watch's course rows.
  Future<void> _publishWear(List<Map<String, Object?>> list) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final json = jsonEncode(list);
    if (json == _lastPushed) return;
    try {
      await _wear.invokeMethod<void>('push', {
        'courses_json': json,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
      _lastPushed = json;
    } on MissingPluginException catch (e) {
      debugPrint('wear park courses push has no native side: $e');
    } on PlatformException catch (e) {
      // No Play services or no paired watch: the phone is unaffected.
      debugPrint('wear park courses push refused: $e');
    }
  }
}
