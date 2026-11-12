import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The recap's park read answers empty for a signed-out client before any
/// wire call; the run course times read surfaces a failed read as a throw, so
/// the share editor leaves the course sticker unoffered rather than printing a
/// course that was never confirmed.
void main() {
  late SupabaseClient signedOut;

  setUp(() {
    // Port 9 (discard) is never listening, so a wire call fails loudly.
    signedOut = SupabaseClient('http://127.0.0.1:9', 'eyJ.local.test');
  });

  tearDown(() {
    signedOut.dispose();
  });

  test('fetchRecapParkCourses is empty when signed out', () async {
    final api = ApiClient.withClient(signedOut);
    expect(await api.fetchRecapParkCourses(DateTime(2027), DateTime(2028)), isEmpty);
  });

  test('fetchParkCourseBySlugs throws on a failed read', () async {
    final api = ApiClient.withClient(signedOut);
    await expectLater(api.fetchParkCourseBySlugs('pocahontas', 'beaver-lake-trail'), throwsA(anything));
  });

  test('fetchRunParkCourseTimes throws on a failed read', () async {
    final api = ApiClient.withClient(signedOut);
    await expectLater(api.fetchRunParkCourseTimes('run-1'), throwsA(anything));
  });
}
