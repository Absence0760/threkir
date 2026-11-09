import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/park_course_routes.dart';

void main() {
  test('a checked route is known, and only a park course reads as one',
      () async {
    final calls = <List<String>>[];
    final lookup = ParkCourseRouteLookup((ids) async {
      calls.add(ids);
      return {'park'};
    });
    expect(lookup.known('park'), isFalse);
    await lookup.check(['park', 'club', 'park']);
    expect(lookup.known('park'), isTrue);
    expect(lookup.isParkCourse('park'), isTrue);
    expect(lookup.known('club'), isTrue);
    expect(lookup.isParkCourse('club'), isFalse);
    await lookup.check(['park', 'club']);
    expect(calls, [
      ['park', 'club'],
    ]);
  });

  test('a failed read marks the routes checked and not park courses',
      () async {
    final lookup = ParkCourseRouteLookup((ids) async => throw Exception('x'));
    await lookup.check(['a']);
    expect(lookup.known('a'), isTrue);
    expect(lookup.isParkCourse('a'), isFalse);
  });
}
