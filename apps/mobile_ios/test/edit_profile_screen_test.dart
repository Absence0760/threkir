import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/edit_profile_screen.dart';
import 'pump_until.dart';
import 'supabase_test_init.dart';
import 'editor_layout.dart';
import 'worst_case_layout.dart';

// A 1x1 transparent PNG so the avatar tile's NetworkImage decodes instead of
// throwing a load error during pumpAndSettle (no network in widget tests).
final _transparentPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82, //
]);

class _ImageHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeHttpResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpResponse implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _transparentPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable([_transparentPng]).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}


/// The profile server: [reads] queue so a test decides when, and whether,
/// each read lands; the writes are recorded.
class _ProfileApi extends ApiClient {
  _ProfileApi({this.avatar, this.handle, this.queued = false});
  String? uid = 'u1';
  String? avatar;
  String? name = 'Alex Rivera';
  String? handle;
  final bool queued;
  Object? handleError;
  Object? nameError;
  int removeCalls = 0;
  final reads = <Completer<UserProfileRow?>>[];
  final nameWrites = <String?>[];
  final handleWrites = <String>[];
  final uploads = <({Uint8List bytes, String contentType})>[];
  final _auth = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;
  @override
  String? get userEmail => uid == null ? null : '$uid@test.com';
  @override
  Stream<String?> get authUserChanges => _auth.stream;

  UserProfileRow _row() => UserProfileRow(
        profilePrivate: false,
        shadowHidden: false,
        id: uid!,
        displayName: name,
        avatarUrl: avatar,
        handle: handle,
      );

  @override
  Future<UserProfileRow?> fetchMyProfile() {
    if (!queued) return Future.value(_row());
    final read = Completer<UserProfileRow?>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<void> updateDisplayName(String? displayName) async {
    nameWrites.add(displayName);
    if (nameError != null) throw nameError!;
    name = displayName;
  }

  @override
  Future<String?> setMyHandle(String next) async {
    handleWrites.add(next);
    if (handleError != null) throw handleError!;
    return handle = next.isEmpty ? null : next;
  }

  @override
  Future<void> removeAvatar() async {
    removeCalls++;
    avatar = null;
  }

  @override
  Future<String> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploads.add((bytes: bytes, contentType: contentType));
    return avatar = 'https://example.invalid/u1/avatar.jpg?v=${uploads.length}';
  }

  void switchTo(String? next) {
    uid = next;
    _auth.add(next);
  }
}

UserProfileRow _row(String id, String? name) => UserProfileRow(
    profilePrivate: false, shadowHidden: false, id: id, displayName: name);

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await initializeTestSupabase();
  _supabaseReady = true;
}

Future<void> _pump(
  WidgetTester tester,
  _ProfileApi api, {
  Future<XFile?> Function()? pickAvatar,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EditProfileScreen(apiClient: api, pickAvatarOverride: pickAvatar),
    ),
  );
  // A pending read shows a skeleton that never settles.
  settle ? await tester.pumpAndSettle() : await tester.pump();
}

Finder _photoIcon(IconData icon) => find.descendant(
    of: find.byKey(const ValueKey('edit-profile-photo')),
    matching: find.byIcon(icon));
final _name = find.byKey(const ValueKey('edit-profile-name'));
final _username = find.byKey(const ValueKey('edit-profile-username'));
final _save = find.byKey(const ValueKey('edit-profile-save'));
const _loadFailed =
    "Couldn't load your profile, so your photo and display name can't be changed yet.";

String _text(WidgetTester tester, Finder field) =>
    tester.widget<TextField>(field).controller!.text;

void main() {
  setUpAll(() => HttpOverrides.global = _ImageHttpOverrides());

  setUp(() async {
    await _ensureSupabase();
    SharedPreferences.setMockInitialValues({});
  });

  group('loading', () {
    testWidgets('the fields stay closed until the saved profile has loaded',
        (tester) async {
      final api = _ProfileApi(queued: true);
      await _pump(tester, api, settle: false);
      expect(_name, findsNothing);
      expect(_save, findsNothing);

      api.reads.single.complete(_row('u1', 'Alex Rivera'));
      await tester.pumpAndSettle();
      expect(_text(tester, _name), 'Alex Rivera');
      expect(api.nameWrites, isEmpty);
    });

    testWidgets('a failed read offers Retry instead of fields seeded with blanks',
        (tester) async {
      final api = _ProfileApi(queued: true);
      await _pump(tester, api, settle: false);
      api.reads.single.completeError(StateError('profile read failed'));
      await tester.pumpAndSettle();
      expect(find.text(_loadFailed), findsOneWidget);
      expect(_name, findsNothing);
      expect(find.text('Profile photo'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(api.reads, hasLength(2));
      api.reads.last.complete(_row('u1', 'Alex Rivera'));
      await tester.pumpAndSettle();
      expect(find.text(_loadFailed), findsNothing);
      expect(_text(tester, _name), 'Alex Rivera');
    });

    testWidgets(
        "a read that lands after an account switch does not show the previous account's name",
        (tester) async {
      final api = _ProfileApi(queued: true);
      await _pump(tester, api, settle: false);
      api.switchTo('b');
      await tester.pump();
      expect(api.reads, hasLength(2));
      api.reads.last.complete(_row('b', 'Bea'));
      await tester.pumpAndSettle();
      api.reads.first.complete(_row('a', 'Alex Rivera'));
      await tester.pumpAndSettle();
      expect(_text(tester, _name), 'Bea');
    });

    testWidgets('an account switch closes the fields until the next read lands',
        (tester) async {
      final api = _ProfileApi(queued: true);
      await _pump(tester, api, settle: false);
      api.reads.single.complete(_row('u1', 'Alex Rivera'));
      await tester.pumpAndSettle();

      api.switchTo('b');
      await tester.pump();
      await tester.pump();
      expect(_name, findsNothing);
      api.reads.last.completeError(StateError('profile read failed'));
      await tester.pumpAndSettle();
      expect(find.text(_loadFailed), findsOneWidget);
      expect(api.nameWrites, isEmpty);
    });
  });

  group('name and username', () {
    testWidgets('Save writes a changed name and leaves', (tester) async {
      final api = _ProfileApi();
      await _pump(tester, api);
      await tester.enterText(_name, '  Alex R  ');
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(api.nameWrites, ['Alex R']);
      expect(api.handleWrites, isEmpty,
          reason: 'an unchanged username is not written');
      expect(find.byType(EditProfileScreen), findsNothing);
    });

    testWidgets('a username is stored lowercased without its @',
        (tester) async {
      final api = _ProfileApi();
      await _pump(tester, api);
      expect(find.text('@'), findsOneWidget, reason: 'the prefix is drawn');
      await tester.enterText(_username, '@Alex_R');
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(api.handleWrites, ['alex_r']);
      expect(api.nameWrites, isEmpty);
    });

    testWidgets('a malformed username is refused before any write',
        (tester) async {
      final api = _ProfileApi();
      await _pump(tester, api);
      await tester.enterText(_username, 'al');
      await tester.tap(_save);
      await tester.pump();
      expect(api.handleWrites, isEmpty);
      expect(find.text('Use 3–30 lowercase letters, numbers, or underscores.'),
          findsOneWidget);
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('a taken username says so and keeps what was typed',
        (tester) async {
      final api = _ProfileApi()
        ..handleError = Exception('P0001 handle_taken');
      await _pump(tester, api);
      await tester.enterText(_username, 'popular');
      await tester.enterText(_name, 'New name');
      await tester.tap(_save);
      await tester.pumpAndSettle();
      expect(find.text('That username is already taken.'), findsOneWidget);
      expect(_text(tester, _username), 'popular');
      expect(api.nameWrites, isEmpty,
          reason: 'the name saves with the username or not at all');
    });

    testWidgets('any other failure keeps the form and says so',
        (tester) async {
      final api = _ProfileApi()..nameError = StateError('write failed');
      await _pump(tester, api);
      await tester.enterText(_name, 'New name');
      await tester.tap(_save);
      await tester.pump();
      expect(find.text("Couldn't save your profile. Please try again."),
          findsOneWidget);
      expect(_text(tester, _name), 'New name');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('leaving with an unsaved change asks first', (tester) async {
      final api = _ProfileApi();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => EditProfileScreen(apiClient: api))),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(_name, 'Changed');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    });
  });

  group('photo', () {
    testWidgets('shows Remove when a photo is set, and asks before removing',
        (tester) async {
      final api =
          _ProfileApi(avatar: 'https://example.invalid/u1/avatar.png');
      await _pump(tester, api);
      expect(_photoIcon(Icons.delete_outline), findsOneWidget);
      expect(_photoIcon(Icons.photo_camera), findsNothing);

      await tester.tap(_photoIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Remove profile photo?'), findsOneWidget);
      expect(api.removeCalls, 0);
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Remove photo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.removeCalls, 1);
      expect(_photoIcon(Icons.photo_camera), findsOneWidget);
    });

    testWidgets('cancelling the confirm keeps the photo', (tester) async {
      final api =
          _ProfileApi(avatar: 'https://example.invalid/u1/avatar.png');
      await _pump(tester, api);
      await tester.tap(_photoIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tester.pumpAndSettle();
      expect(api.removeCalls, 0);
      expect(_photoIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('a photo state clears on sign-out and reloads for the next account',
        (tester) async {
      final api =
          _ProfileApi(avatar: 'https://example.invalid/u1/avatar.png');
      await _pump(tester, api);
      expect(_photoIcon(Icons.delete_outline), findsOneWidget);
      api.avatar = null;
      api.switchTo(null);
      await tester.pumpAndSettle();
      expect(find.text('Profile photo'), findsNothing);
      api.switchTo('b');
      await tester.pumpAndSettle();
      expect(_photoIcon(Icons.photo_camera), findsOneWidget);
      expect(_photoIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets(
        'picking a photo opens the crop step and uploads only the turned, '
        'EXIF-free square', (tester) async {
      final api = _ProfileApi();
      // A sideways geotagged JPEG: 40x20, red left / blue right, Orientation 6.
      final src = img.Image(width: 40, height: 20);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 40; x++) {
          src.setPixelRgb(x, y, x < 20 ? 255 : 0, 0, x < 20 ? 0 : 255);
        }
      }
      src.exif.imageIfd.orientation = 6;
      src.exif.gpsIfd.setGpsLocation(latitude: 51.5, longitude: -0.12);
      final picked = img.encodeJpg(src, quality: 100);
      await _pump(tester, api,
          pickAvatar: () async =>
              XFile.fromData(picked, mimeType: 'image/jpeg'));

      await tester.tap(_photoIcon(Icons.photo_camera));
      await pumpUntil(
        tester,
        () => find.text('Adjust profile photo').evaluate().isNotEmpty,
        describe: 'the crop step to open',
      );
      await tester.pump(const Duration(milliseconds: 400));
      FilledButton confirm() => tester
          .widget<FilledButton>(find.byKey(const Key('avatar-crop-confirm')));
      await pumpUntil(tester, () => confirm().onPressed != null,
          describe: 'the picked photo to decode');
      await tester.tap(find.byTooltip('Rotate right'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('avatar-crop-confirm')));
      await pumpUntil(tester, () => api.uploads.isNotEmpty,
          describe: 'the cropped photo to upload');

      final upload = api.uploads.single;
      expect(upload.contentType, 'image/jpeg');
      expect(String.fromCharCodes(upload.bytes).contains('Exif'), isFalse);
      final out = img.decodeJpg(upload.bytes)!;
      expect([out.width, out.height], [20, 20]);
      final left = out.getPixel(5, 10);
      final right = out.getPixel(15, 10);
      expect(left.b > 180 && left.r < 80, isTrue, reason: 'left $left');
      expect(right.r > 180 && right.b < 80, isTrue, reason: 'right $right');
    });

    testWidgets('backing out of the crop step uploads nothing',
        (tester) async {
      final api = _ProfileApi();
      final png = img.encodePng(img.Image(width: 8, height: 8));
      await _pump(tester, api,
          pickAvatar: () async => XFile.fromData(png, mimeType: 'image/png'));
      await tester.tap(_photoIcon(Icons.photo_camera));
      await pumpUntil(
        tester,
        () => find.text('Adjust profile photo').evaluate().isNotEmpty,
        describe: 'the crop step to open',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.descendant(
          of: find.ancestor(
              of: find.text('Adjust profile photo'),
              matching: find.byType(Scaffold)),
          matching: find.byType(CloseButton)));
      await tester.pumpAndSettle();
      expect(find.text('Adjust profile photo'), findsNothing);
      expect(api.uploads, isEmpty);
    });
  });

  testWidgets('Save stays reachable on a small phone at 2x, keyboard up or down',
      (tester) async {
    await expectEditorSaveReachable(
      tester,
      page: () => EditProfileScreen(apiClient: _ProfileApi()),
      save: _save,
      settle: () => tester.pumpAndSettle(),
    );
  });

  worstCaseTestWidgets('Edit profile', (tester, locale) async {
    await tester.pumpWidget(worstCaseApp(
      locale: locale,
      home: EditProfileScreen(apiClient: _ProfileApi(handle: 'alex_r')),
    ));
    await tester.pumpAndSettle();
  });
}
