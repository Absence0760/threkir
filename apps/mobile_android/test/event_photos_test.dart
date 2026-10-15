import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/social_service.dart' show RecentRunRow;
import '../lib/widgets/event_photos.dart';
import '../lib/widgets/undo_bar.dart';

EventPhotoView _photo({
  String id = 'p1',
  String owner = 'owner-1',
  String? caption,
  String? uploader = 'Dana',
  DateTime? hiddenAt,
}) =>
    EventPhotoView(
      id: id,
      ownerId: owner,
      storagePath: '$owner/$id.jpg',
      caption: caption,
      positionIdx: 0,
      createdAt: DateTime.utc(2026, 6, 1),
      uploaderName: uploader,
      hiddenAt: hiddenAt,
    );

class _PhotosApi extends ApiClient {
  _PhotosApi({List<EventPhotoView>? seed, this.steward = false, this.failLoads = 0})
      : _photos = List.of(seed ?? const []);

  final List<EventPhotoView> _photos;
  final bool steward;
  int failLoads;
  int addCalls = 0;
  bool addedWithoutRun = false;
  String? lastRunId;
  String? lastEventId;
  DateTime? lastInstance;
  final List<(String, bool)> hideCalls = [];
  final List<String> deleteCalls = [];

  @override
  Future<List<EventPhotoView>> fetchEventPhotos(
    String eventId,
    DateTime instanceStart, {
    int limit = 100,
  }) async {
    if (failLoads > 0) {
      failLoads--;
      throw Exception('boom');
    }
    return List.of(_photos);
  }

  @override
  Future<bool> canStewardEventPhotos(String eventId) async => steward;

  @override
  Future<void> setEventPhotoHidden(String photoId, {required bool hidden}) async {
    hideCalls.add((photoId, hidden));
  }

  @override
  Future<void> deleteEventPhoto(EventPhotoView photo) async {
    deleteCalls.add(photo.id);
  }

  @override
  Future<RunPhotoRow> addRunPhoto({
    required String? runId,
    required Uint8List bytes,
    required String contentType,
    required String extension,
    String? caption,
    int positionIdx = 0,
    String? eventId,
    DateTime? eventInstanceStart,
  }) async {
    addCalls++;
    addedWithoutRun = runId == null;
    lastRunId = runId;
    lastEventId = eventId;
    lastInstance = eventInstanceStart;
    _photos.add(_photo(id: 'added', uploader: 'Me'));
    return RunPhotoRow.fromJson({
      'id': 'added',
      'run_id': runId,
      'owner_id': 'me',
      'storage_path': 'me/added.$extension',
      'position_idx': positionIdx,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'event_id': eventId,
      'event_instance_start': eventInstanceStart?.toUtc().toIso8601String(),
    });
  }
}

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

EventPhotos _widget(
  _PhotosApi api, {
  bool canAdd = true,
  String? myEventRunId,
  String? currentUserId,
  List<RecentRunRow> recent = const [],
  DateTime? now,
}) =>
    EventPhotos(
      api: api,
      eventId: 'event-1',
      instanceStart: DateTime.utc(2026, 6, 10, 8),
      canAdd: canAdd,
      myEventRunId: myEventRunId,
      currentUserId: currentUserId,
      clock: () => now ?? DateTime.utc(2026, 6, 10, 9),
      fetchWindowRuns: () async => recent,
      // Real JPEG magic — the upload path sniffs the bytes and refuses a
      // format its EXIF stripper doesn't understand, so a three-byte
      // placeholder never reaches the API.
      pickImageOverride: () async => XFile.fromData(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0xFF, 0xD9]),
          name: 'shot.jpg'),
    );

/// The event detail screen's own geometry: a 360dp phone, 16dp list gutters.
Future<void> _pumpNarrow(
  WidgetTester tester,
  _PhotosApi api, {
  required Locale locale,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = const Size(360, 640) * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _widget(api),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The armed undo window owns a real Timer; a test that ends with it pending
/// fails on `!timersPending`.
Future<void> _drain(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 9));

void main() {
  tearDown(debugResetUndo);

  testWidgets('empty gallery + canAdd shows title, add button, hint',
      (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api)));
    await tester.pumpAndSettle();
    expect(find.text('Photos (0)'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
    expect(find.textContaining('No photos yet.'), findsOneWidget);
  });

  testWidgets('empty gallery for anon viewer renders nothing', (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api, canAdd: false)));
    await tester.pumpAndSettle();
    expect(find.text('Photos (0)'), findsNothing);
    expect(find.text('Add photo'), findsNothing);
  });

  testWidgets('seeded photos render tiles with uploader + caption',
      (tester) async {
    final api = _PhotosApi(seed: [
      _photo(id: 'a', caption: 'Great day', uploader: 'Dana'),
      _photo(id: 'b', uploader: null),
    ]);
    await tester.pumpWidget(_host(_widget(api, canAdd: false)));
    await tester.pumpAndSettle();
    expect(find.text('Photos (2)'), findsOneWidget);
    expect(find.text('Great day'), findsOneWidget);
    expect(find.text('Dana'), findsOneWidget);
    // Null uploader falls back to the "A runner" label.
    expect(find.text('A runner'), findsOneWidget);
  });

  testWidgets('each tile carries a button+image semantics label', (tester) async {
    // The tappable thing is a bare Image under a GestureDetector — to TalkBack
    // an unlabelled, roleless rectangle. The caption and uploader render as
    // SEPARATE nodes, so without this the control itself had no name at all.
    final api = _PhotosApi(seed: [
      _photo(id: 'a', caption: 'Great day', uploader: 'Dana'),
      _photo(id: 'b', uploader: null),
    ]);
    await tester.pumpWidget(_host(_widget(api, canAdd: false)));
    await tester.pumpAndSettle();

    final semantics = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((w) => w.properties.button == true && w.properties.image == true)
        .toList();
    expect(semantics.length, 2, reason: 'one per photo tile');
    // A captioned photo is named by its caption; an uncaptioned one falls back.
    final labels = semantics.map((w) => w.properties.label).toSet();
    expect(labels, {'Great day', 'Open photo'});
  });

  testWidgets('finisher add attaches to own event run', (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api, myEventRunId: 'run-me')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    expect(api.addCalls, 1);
    expect(api.lastRunId, 'run-me');
    expect(api.lastEventId, 'event-1');
    expect(api.lastInstance, DateTime.utc(2026, 6, 10, 8));
    expect(find.text('Photos (1)'), findsOneWidget);
  });

  testWidgets('non-finisher add picks a recent run first', (tester) async {
    final api = _PhotosApi();
    final recent = [
      RecentRunRow(
        id: 'run-pick',
        startedAt: DateTime.utc(2026, 6, 9, 7),
        durationS: 1800,
        distanceM: 5000,
        activityType: 'run',
      ),
    ];
    await tester.pumpWidget(_host(_widget(api, recent: recent)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    // The run picker sheet is open — choose the run.
    expect(find.text('Which run is this photo from?'), findsOneWidget);
    await tester.tap(find.textContaining('5.00 km'));
    await tester.pumpAndSettle();
    expect(api.addCalls, 1);
    expect(api.lastRunId, 'run-pick');
    expect(api.lastEventId, 'event-1');
  });

  testWidgets('mi mode: the run picker names each run in the runner\'s unit',
      (tester) async {
    // The picker labelled every candidate run in kilometres whatever the unit
    // pref said, so a mile-unit runner had to convert in their head to tell
    // which of their recent runs the photo belonged to.
    SharedPreferences.setMockInitialValues({'use_miles': true});
    final prefs = Preferences();
    await prefs.init();
    registerActivePreferences(prefs);
    addTearDown(resetActivePreferencesForTest);

    final api = _PhotosApi();
    final recent = [
      RecentRunRow(
        id: 'run-pick',
        startedAt: DateTime.utc(2026, 6, 9, 7),
        durationS: 1800,
        distanceM: 8046.72,
        activityType: 'run',
      ),
    ];
    await tester.pumpWidget(_host(_widget(api, recent: recent)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5.00 mi'), findsOneWidget);
    expect(find.textContaining(' km'), findsNothing);
  });

  group('steward (#1150)', () {
    testWidgets('a steward posts an occurrence photo with no run',
        (tester) async {
      final api = _PhotosApi(steward: true);
      await tester.pumpWidget(_host(_widget(api)));
      await tester.pumpAndSettle();
      expect(find.text('Add from my run'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('event-photo-add-host')));
      await tester.pumpAndSettle();
      expect(api.addCalls, 1);
      expect(api.addedWithoutRun, isTrue);
      expect(api.lastEventId, 'event-1');
      expect(api.lastInstance, DateTime.utc(2026, 6, 10, 8));
    });

    testWidgets('the run-less upload stays shut until two hours before',
        (tester) async {
      final api = _PhotosApi(steward: true);
      await tester.pumpWidget(
          _host(_widget(api, now: DateTime.utc(2026, 6, 10, 5, 59))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('event-photo-add-host')), findsNothing);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('a non-steward sees no run-less upload and no Hide',
        (tester) async {
      final api = _PhotosApi(seed: [_photo(id: 'a')]);
      await tester.pumpWidget(_host(_widget(api)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('event-photo-add-host')), findsNothing);
      expect(find.text('Hide'), findsNothing);
    });

    testWidgets('Hide is deferred behind the undo bar and badges the tile',
        (tester) async {
      final api = _PhotosApi(steward: true, seed: [_photo(id: 'a')]);
      await tester.pumpWidget(_host(_widget(api)));
      await tester.pumpAndSettle();
      expect(find.text('Photos (1)'), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing,
          reason: 'hiding is reversible, so undo replaces a confirm');
      expect(find.text('Hidden'), findsOneWidget);
      expect(find.text('Restore'), findsOneWidget);
      expect(find.text('Photos (0)'), findsOneWidget);
      expect(api.hideCalls, isEmpty);

      await _drain(tester);
      expect(api.hideCalls, [('a', true)]);
    });

    testWidgets('Undo puts a hidden photo back without calling the server',
        (tester) async {
      final api = _PhotosApi(steward: true, seed: [_photo(id: 'a')]);
      await tester.pumpWidget(_host(_widget(api)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hide'));
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(find.text('Hidden'), findsNothing);
      await _drain(tester);
      expect(api.hideCalls, isEmpty);
    });

    testWidgets('Restore un-hides a hidden photo', (tester) async {
      final api = _PhotosApi(
          steward: true,
          seed: [_photo(id: 'a', hiddenAt: DateTime.utc(2026, 6, 10, 10))]);
      await tester.pumpWidget(_host(_widget(api)));
      await tester.pumpAndSettle();
      expect(find.text('Photos (0)'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();
      expect(api.hideCalls, [('a', false)]);
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Photos (1)'), findsOneWidget);
    });

    testWidgets(
        'Restore inside the undo window cancels the pending hide, so it never saves',
        (tester) async {
      final api = _PhotosApi(steward: true, seed: [_photo(id: 'a')]);
      await tester.pumpWidget(_host(_widget(api)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.text('Photos (0)'), findsOneWidget);

      await tester.tap(find.text('Restore'));
      await tester.pump();
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Photos (1)'), findsOneWidget);

      await _drain(tester);
      expect(api.hideCalls, isEmpty,
          reason: 'the hide was cancelled, and there was nothing to un-hide');
      expect(find.text('Photos (1)'), findsOneWidget);
    });
  });

  testWidgets('the owner deletes their own photo behind the undo bar',
      (tester) async {
    final api = _PhotosApi(
        seed: [_photo(id: 'mine', owner: 'me'), _photo(id: 'theirs')]);
    await tester.pumpWidget(_host(_widget(api, currentUserId: 'me')));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget,
        reason: 'only the viewer\'s own photo carries Delete');
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('Photos (1)'), findsOneWidget);
    expect(api.deleteCalls, isEmpty);
    await _drain(tester);
    expect(api.deleteCalls, ['mine']);
  });

  testWidgets('a failed load shows an error with reload, not an empty gallery',
      (tester) async {
    final api = _PhotosApi(seed: [_photo(id: 'a')], failLoads: 1);
    await tester.pumpWidget(_host(_widget(api)));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load the photos."), findsOneWidget);
    expect(find.textContaining('No photos yet.'), findsNothing);
    await tester.tap(find.text('Reload photos'));
    await tester.pumpAndSettle();
    expect(find.text('Photos (1)'), findsOneWidget);
    expect(find.text("Couldn't load the photos."), findsNothing);
  });

  testWidgets('the run picker explains the photo window when it is empty',
      (tester) async {
    final api = _PhotosApi();
    await tester.pumpWidget(_host(_widget(api)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('None of your runs started during this event'),
        findsOneWidget);
  });

  group('long localized add labels at 360dp (#1154)', () {
    const locales = [
      Locale('de'),
      Locale('es'),
      Locale('pt'),
      Locale('pt', 'BR'),
    ];

    for (final locale in locales) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('$locale at ${scale}x shows every add label whole',
            (tester) async {
          final l10n = lookupAppLocalizations(locale);
          await _pumpNarrow(tester, _PhotosApi(steward: true),
              locale: locale, textScale: scale);
          expect(tester.takeException(), isNull);

          for (final label in [
            l10n.eventAddPhotoFromRun,
            l10n.eventAddOccurrencePhoto,
          ]) {
            final text = find.text(label);
            expect(text, findsOneWidget, reason: label);
            expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
                isFalse,
                reason: '"$label" was cut short');
            final rect = tester.getRect(text);
            expect(rect.left, greaterThanOrEqualTo(16), reason: label);
            expect(rect.right, lessThanOrEqualTo(360 - 16), reason: label);
            final button = find.ancestor(
              of: text,
              matching: find.byWidgetPredicate((w) => w is TextButton),
            );
            expect(tester.getSize(button.first).height,
                greaterThanOrEqualTo(48),
                reason: label);
          }
        });
      }
    }

    testWidgets('given room, the add button stays on the title line',
        (tester) async {
      await tester.pumpWidget(_host(_widget(_PhotosApi())));
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.text('Add photo')).dy,
          closeTo(tester.getCenter(find.text('Photos (0)')).dy, 1));
    });
  });
}
