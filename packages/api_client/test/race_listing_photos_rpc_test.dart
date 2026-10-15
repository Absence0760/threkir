import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The race-listing photo wrappers name their RPCs and parameters by hand, so
/// a renamed function or a misspelled `p_` key reaches the server as a 404.
/// The fake sits at the http boundary and answers by path; the PostgREST
/// builders and ApiClient above it are real.
class _FakeHttp extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  final Map<String, Object> bodyByPath = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final match = bodyByPath.entries
        .where((e) => request.url.path.endsWith(e.key))
        .map((e) => e.value);
    final body = match.isEmpty ? const <dynamic>[] : match.first;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }

  Iterable<http.BaseRequest> to(String pathSuffix) =>
      requests.where((r) => r.url.path.endsWith(pathSuffix));
}

const _listPath = '/rest/v1/rpc/race_listing_photos';
const _sharePath = '/rest/v1/rpc/set_run_photo_race_gallery';
const _runsPath = '/rest/v1/runs';

void main() {
  late _FakeHttp fake;
  late SupabaseClient client;
  late ApiClient api;

  setUp(() {
    fake = _FakeHttp();
    client = SupabaseClient(
      'http://127.0.0.1:24321',
      'test-anon-key',
      httpClient: fake,
    );
    api = ApiClient.withClient(client);
  });

  tearDown(() => client.dispose());

  group('fetchRaceListingPhotos', () {
    test('reads the RPC as a GET with the listing and limit', () async {
      await api.fetchRaceListingPhotos('listing-1', limit: 12);

      final req = fake.to(_listPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, {
        'p_listing_id': 'listing-1',
        'p_limit': '12',
      });
    });

    test('defaults the limit to 24', () async {
      await api.fetchRaceListingPhotos('listing-1');

      expect(fake.to(_listPath).single.url.queryParameters['p_limit'], '24');
    });

    test('maps each row with the display name the RPC returns', () async {
      fake.bodyByPath[_listPath] = [
        {
          'id': 'photo-a',
          'storage_path': 'owner-1/photo-a.jpg',
          'thumb_512_path': 'owner-1/photo-a.512.jpg',
          'caption': 'Mile 20',
          'created_at': '2026-10-01T09:30:00Z',
          'display_name': 'Ada',
        },
        {
          'id': 'photo-b',
          'storage_path': 'owner-2/photo-b.jpg',
          'thumb_512_path': 'owner-2/photo-b.512.jpg',
          'caption': null,
          'created_at': '2026-10-01T08:00:00Z',
          'display_name': null,
        },
      ];

      final photos = await api.fetchRaceListingPhotos('listing-1');

      expect(photos.map((p) => p.id), ['photo-a', 'photo-b']);
      expect(photos.first.displayName, 'Ada');
      expect(photos.first.caption, 'Mile 20');
      expect(photos.first.thumb512Path, 'owner-1/photo-a.512.jpg');
      expect(photos.first.createdAt, DateTime.utc(2026, 10, 1, 9, 30));
      expect(photos.last.displayName, isNull);
      expect(photos.last.caption, isNull);
    });

    test('an empty page answers empty', () async {
      fake.bodyByPath[_listPath] = const <dynamic>[];

      expect(await api.fetchRaceListingPhotos('listing-1'), isEmpty);
    });
  });

  group('fetchRunRaceGalleryContext', () {
    test('reads the run\'s visibility and race link in one query', () async {
      fake.bodyByPath[_runsPath] = [
        {'is_public': true, 'race_listing_id': 'listing-1'},
      ];

      final ctx = await api.fetchRunRaceGalleryContext('run-1');

      expect(ctx, (isPublic: true, raceListingId: 'listing-1'));
      final req = fake.to(_runsPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters['select'], 'is_public,race_listing_id');
      expect(req.url.queryParameters['id'], 'eq.run-1');
    });

    test('a private run with no race link reads as such', () async {
      fake.bodyByPath[_runsPath] = [
        {'is_public': false, 'race_listing_id': null},
      ];

      expect(
        await api.fetchRunRaceGalleryContext('run-1'),
        (isPublic: false, raceListingId: null),
      );
    });

    test('a run RLS hides answers null', () async {
      fake.bodyByPath[_runsPath] = const <dynamic>[];

      expect(await api.fetchRunRaceGalleryContext('run-1'), isNull);
    });
  });

  group('setRunPhotoRaceGallery', () {
    test('posts the photo id and the shared flag to the RPC', () async {
      fake.bodyByPath[_sharePath] = const <String, dynamic>{};

      await api.setRunPhotoRaceGallery('photo-a', shared: true);

      final req = fake.to(_sharePath).single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'p_photo_id': 'photo-a', 'p_shared': true});
    });

    test('withdrawing posts shared false', () async {
      fake.bodyByPath[_sharePath] = const <String, dynamic>{};

      await api.setRunPhotoRaceGallery('photo-a', shared: false);

      final req = fake.to(_sharePath).single as http.Request;
      expect(jsonDecode(req.body), {'p_photo_id': 'photo-a', 'p_shared': false});
    });
  });
}
