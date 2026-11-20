// The park courses the phone puts on the Wear OS watch (`/park_courses`):
// the writer held to the fixture the watch's reader is held to
// (`fixtures/wear_park_courses_payload.json`), the courses it picks, and the
// bridge that delivers them on Navigate, at startup and on sign-out.

import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/apple_watch_route_bridge.dart';
import '../lib/watch_park_courses.dart';

final Map<String, dynamic> _fixture = jsonDecode(
  File('../../fixtures/wear_park_courses_payload.json').readAsStringSync(),
) as Map<String, dynamic>;

/// Through JSON text, so the comparison is of what reaches the channel.
dynamic _wire(Object? value) => jsonDecode(jsonEncode(value));

Map<String, dynamic> _beaverLake() =>
    ((_fixture['cases'] as List).first['courses_json'] as List).first
        as Map<String, dynamic>;

/// A fixture course as the rows the phone reads it from: the
/// `global_segments` row (lines, length, polyline) and the `park_courses`
/// row (id, route id, laps, checkpoints).
ParkCourseListing _listingFrom(Map<String, dynamic> c, {String? id}) {
  final start = c['start_gate'] as Map<String, dynamic>;
  final end = c['end_gate'] as Map<String, dynamic>;
  return ParkCourseListing(
    course: ParkCourseRow.fromJson({
      'id': id ?? c['id'],
      'park_id': 'park-1',
      'global_segment_id': 'seg-1',
      'route_id': c['route_id'],
      'slug': 'course',
      'course_shape': 'loop',
      'status': 'open',
      'geometry_source': 'osm',
      'checkpoints': c['checkpoints'],
      'created_at': '2026-11-20T00:00:00Z',
      'laps': c['laps'],
    }),
    segment: GlobalSegmentRow.fromJson({
      'id': 'seg-1',
      'name': c['name'],
      'waypoints': c['waypoints'],
      'distance_m': c['distance_m'],
      'surface': 'trail',
      'is_active': true,
      'created_at': '2026-11-20T00:00:00Z',
      'start_gate_lat': start['lat'],
      'start_gate_lng': start['lng'],
      'start_gate_bearing_deg': start['bearing_deg'],
      'start_gate_half_width_m': start['half_width_m'],
      'end_gate_lat': end['lat'],
      'end_gate_lng': end['lng'],
      'end_gate_bearing_deg': end['bearing_deg'],
      'end_gate_half_width_m': end['half_width_m'],
    }),
  );
}

/// `repeat_course` / `repeat` expanded as the fixture's schema says.
List<Object?> _caseCourses(Map<String, dynamic> c) {
  final out = <Object?>[...(c['courses_json'] as List)];
  final repeat = c['repeat_course'] as Map<String, dynamic>?;
  if (repeat != null) {
    final base = repeat['course'] as Map<String, dynamic>;
    for (var i = 0; i < (repeat['count'] as int); i++) {
      out.add({...base, 'id': '${base['id']}$i'});
    }
  }
  return out;
}

Object? _rejected(Map<String, dynamic> c) {
  final course = Map<String, dynamic>.from(c['course'] as Map);
  final repeat = c['repeat'] as Map<String, dynamic>?;
  if (repeat != null) {
    course[repeat['field'] as String] = [
      for (var i = 0; i < (repeat['count'] as int); i++) repeat['point'],
    ];
  }
  return course;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the fixture the watch reads by', () {
    test('every case keeps the ids the watch keeps', () {
      for (final c in (_fixture['cases'] as List).cast<Map<String, dynamic>>()) {
        // The watch's own walk: readable courses, first of an id, at most
        // its 20. The phone's cap is lower, so it is not applied here.
        final seen = <String>{};
        final kept = [
          for (final course in _caseCourses(c))
            if (wearParkCourseReadable(course) &&
                seen.add((course as Map)['id'] as String))
              course['id'] as String,
        ].take(20).toList();
        expect(kept, c['expected'], reason: c['name'] as String);
      }
    });

    test('every course the watch refuses, the phone refuses too', () {
      final rejected =
          (_fixture['rejected_courses'] as List).cast<Map<String, dynamic>>();
      expect(rejected, isNotEmpty);
      for (final c in rejected) {
        expect(wearParkCourseReadable(_rejected(c)), isFalse,
            reason: c['name'] as String);
      }
    });

    test('the writer builds the fixture course from the rows, key for key',
        () {
      final fixtureCourse = _beaverLake();
      expect(
        _wire(wearParkCourseFor(_listingFrom(fixtureCourse))),
        fixtureCourse,
      );
    });

    test('a course with no laps or route sends both as null, as the watch '
        'reads them', () {
      final minimal = ((_fixture['cases'] as List).first['courses_json']
          as List)[1] as Map<String, dynamic>;
      expect(_wire(wearParkCourseFor(_listingFrom(minimal))), minimal);
    });
  });

  group('wearParkCourseFor', () {
    test('a course the wrist cannot box-time is not sent', () {
      final noEnd = {
        ..._beaverLake(),
        'end_gate': <String, dynamic>{
          ...(_beaverLake()['end_gate'] as Map<String, dynamic>),
          'bearing_deg': null,
        },
      };
      expect(wearParkCourseFor(_listingFrom(noEnd)), isNull);
      final narrow = {
        ..._beaverLake(),
        'start_gate': <String, dynamic>{
          ...(_beaverLake()['start_gate'] as Map<String, dynamic>),
          'half_width_m': 4,
        },
      };
      expect(wearParkCourseFor(_listingFrom(narrow)), isNull);
    });

    test('a dense line is thinned to the budget, both ends kept', () {
      final dense = [
        for (var i = 0; i < 1500; i++)
          {'lat': 37.0 + i * 1e-5, 'lng': -77.0 + (i % 9) * 1e-6},
      ];
      final course =
          wearParkCourseFor(_listingFrom({..._beaverLake(), 'waypoints': dense}))!;
      final line = course['waypoints'] as List;
      expect(line.length, lessThanOrEqualTo(kMaxWearParkCourseWaypoints));
      expect(_wire(line.first), {'lat': 37.0, 'lng': -77.0});
      expect((line.last as Map)['lat'], closeTo(37.01499, 1e-6));
    });
  });

  group('pickWearParkCourses', () {
    Map<String, Object?> course(String id) =>
        (_wire(_beaverLake()) as Map<String, dynamic>)..['id'] = id;

    test('newest first, first of an id, at most the phone cap', () {
      final picked = pickWearParkCourses([
        course('a'),
        course('a'),
        for (var i = 0; i < 12; i++) course('c$i'),
      ]);
      expect(picked.length, kMaxWearParkCourses);
      expect(picked.map((c) => c['id']).take(3), ['a', 'c0', 'c1']);
    });

    test('drops the oldest until the list fits the Data Layer budget', () {
      final heavy = {
        ...course('x'),
        'waypoints': [
          for (var i = 0; i < 1000; i++)
            {'lat': 37.123456789012 + i * 1e-5, 'lng': -77.123456789012},
        ],
      };
      final picked = pickWearParkCourses([
        for (var i = 0; i < kMaxWearParkCourses; i++) {...heavy, 'id': 'h$i'},
      ]);
      expect(picked, isNotEmpty);
      expect(picked.length, lessThan(kMaxWearParkCourses));
      expect(utf8.encode(jsonEncode(picked)).length,
          lessThanOrEqualTo(kWearParkCoursesMaxBytes));
      expect(picked.first['id'], 'h0');
    });

    test('leaves out anything the watch would refuse', () {
      expect(pickWearParkCourses([{...course('a'), 'name': ' '}]), isEmpty);
    });
  });

  group('WatchParkCourses', () {
    const wear = MethodChannel(WatchParkCourses.wearChannelName);
    const apple = MethodChannel(AppleWatchRouteBridge.channelName);
    late List<MethodCall> wearCalls;
    late List<MethodCall> appleCalls;
    Object? wearThrows;

    List<String> pushedIds(MethodCall call) => [
          for (final c in jsonDecode(
              (call.arguments as Map)['courses_json'] as String) as List)
            (c as Map)['id'] as String,
        ];

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      WatchParkCourses().resetForTest();
      wearCalls = [];
      appleCalls = [];
      wearThrows = null;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(wear, (call) async {
        wearCalls.add(call);
        if (wearThrows != null) throw wearThrows!;
        return null;
      });
      messenger.setMockMethodCallHandler(apple, (call) async {
        appleCalls.add(call);
        return call.method == 'available' ? true : null;
      });
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(wear, null);
      messenger.setMockMethodCallHandler(apple, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('Navigate puts the course at the top of the list on Wear OS',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final bridge = WatchParkCourses();
      await bridge.courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      await bridge.courseNavigated(_listingFrom(_beaverLake(), id: 'b'));
      await bridge.courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      expect(wearCalls.map(pushedIds).toList(), [
        ['a'],
        ['b', 'a'],
        ['a', 'b'],
      ]);
      final args = wearCalls.last.arguments as Map;
      expect(args.keys.toSet(), {'courses_json', 'updated_at_ms'});
      expect(appleCalls, isEmpty);
    });

    test('startup restates the stored list once, and not again unchanged',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await WatchParkCourses()
          .courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      wearCalls.clear();
      await WatchParkCourses().attach();
      expect(wearCalls.map(pushedIds).toList(), [
        ['a'],
      ]);
      await WatchParkCourses()
          .courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      expect(wearCalls, hasLength(1));
    });

    test('sign-out empties the list on the watch and on the phone', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await WatchParkCourses()
          .courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      await WatchParkCourses().clear();
      expect(pushedIds(wearCalls.last), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(WatchParkCourses.prefsKey), isNull);
    });

    test('a refused push is logged and tried again on the next one',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      wearThrows = PlatformException(code: 'put_failed');
      await WatchParkCourses()
          .courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      wearThrows = null;
      await WatchParkCourses().attach();
      expect(wearCalls, hasLength(2));
    });

    test('a course the wrist cannot time leaves the list alone', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await WatchParkCourses().courseNavigated(_listingFrom({
        ..._beaverLake(),
        'distance_m': 0,
      }));
      expect(wearCalls, isEmpty);
    });

    test('on an iPhone, Navigate arms the course on the Apple Watch',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await WatchParkCourses()
          .courseNavigated(_listingFrom(_beaverLake(), id: 'a'));
      expect(appleCalls.map((c) => c.method),
          ['available', 'push_park_course', 'push']);
      expect(wearCalls, isEmpty);
    });
  });
}
