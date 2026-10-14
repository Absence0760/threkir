import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// The event-gallery wrappers name their RPC and its parameters by hand, so a
/// renamed function or a misspelled `p_` key reaches the server as a 404 that
/// the gallery widget contains as "did not load". The fake sits at the http
/// boundary and answers by path; the PostgREST builders and ApiClient above it
/// are real.
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

const _galleryPath = '/rest/v1/rpc/event_gallery_photos';
const _profilesPath = '/rest/v1/user_profiles';
const _stewardPath = '/rest/v1/rpc/can_steward_event_photos';
const _hidePath = '/rest/v1/rpc/set_event_photo_hidden';

Map<String, dynamic> _photo(
  String id,
  String ownerId, {
  String? hiddenAt,
}) =>
    {
      'id': id,
      'owner_id': ownerId,
      'storage_path': '$ownerId/$id.jpg',
      'thumb_512_path': '$ownerId/$id.512.jpg',
      'caption': 'Caption $id',
      'position_idx': 0,
      'created_at': '2026-09-20T08:00:00Z',
      'hidden_at': hiddenAt,
    };

Future<void> _signIn(SupabaseClient client) =>
    client.auth.setInitialSession(jsonEncode({
      'access_token': 'fake-token',
      'token_type': 'bearer',
      'user': {
        'id': 'user-1',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));

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

  group('fetchEventPhotos', () {
    final instanceStart = DateTime.utc(2026, 9, 20, 7, 30);

    test('reads the gallery RPC as a GET with the event, instance and limit',
        () async {
      await api.fetchEventPhotos('event-1', instanceStart, limit: 25);

      final req = fake.to(_galleryPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, {
        'p_event_id': 'event-1',
        'p_instance': instanceStartKey(instanceStart),
        'p_limit': '25',
      });
    });

    test('maps each row with its hidden stamp and its uploader name',
        () async {
      fake.bodyByPath[_galleryPath] = [
        _photo('photo-a', 'owner-1'),
        _photo('photo-b', 'owner-2', hiddenAt: '2026-09-21T10:15:00Z'),
      ];
      fake.bodyByPath[_profilesPath] = [
        {'id': 'owner-1', 'display_name': 'Ada'},
        {'id': 'owner-2', 'display_name': 'Grace'},
      ];

      final photos = await api.fetchEventPhotos('event-1', instanceStart);

      expect(photos.map((p) => p.id), ['photo-a', 'photo-b']);
      expect(photos.map((p) => p.uploaderName), ['Ada', 'Grace']);
      expect(photos.first.hiddenAt, isNull);
      expect(photos.last.hiddenAt, DateTime.utc(2026, 9, 21, 10, 15));
      expect(photos.last.storagePath, 'owner-2/photo-b.jpg');

      final profileReq = fake.to(_profilesPath).single;
      expect(profileReq.method, 'GET');
      expect(profileReq.url.queryParameters['select'], 'id,display_name');
      expect(profileReq.url.queryParameters['id'], 'in.("owner-1","owner-2")');
    });

    test('an empty gallery answers empty and asks for no profiles', () async {
      fake.bodyByPath[_galleryPath] = const <dynamic>[];

      expect(await api.fetchEventPhotos('event-1', instanceStart), isEmpty);
      expect(fake.to(_galleryPath), hasLength(1));
      expect(fake.to(_profilesPath), isEmpty);
    });
  });

  group('canStewardEventPhotos', () {
    test('a signed-in steward is answered true by the RPC', () async {
      await _signIn(client);
      fake.bodyByPath[_stewardPath] = true;

      expect(await api.canStewardEventPhotos('event-1'), isTrue);

      final req = fake.to(_stewardPath).single;
      expect(req.method, 'GET');
      expect(req.url.queryParameters, {'p_event_id': 'event-1'});
    });

    test('a signed-in non-steward is answered false', () async {
      await _signIn(client);
      fake.bodyByPath[_stewardPath] = false;

      expect(await api.canStewardEventPhotos('event-1'), isFalse);
      expect(fake.to(_stewardPath), hasLength(1));
    });

    test('signed out answers false without a wire call', () async {
      fake.bodyByPath[_stewardPath] = true;

      expect(await api.canStewardEventPhotos('event-1'), isFalse);
      expect(fake.requests, isEmpty);
    });
  });

  group('setEventPhotoHidden', () {
    test('posts the photo id and the hidden flag to the RPC', () async {
      fake.bodyByPath[_hidePath] = const <String, dynamic>{};

      await api.setEventPhotoHidden('photo-a', hidden: true);

      final req = fake.to(_hidePath).single as http.Request;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {'p_photo_id': 'photo-a', 'p_hidden': true});
    });
  });
}
