// A race-listing page is public and crawler-indexed, so a run photo reaches
// it only by the owner's explicit opt-in (decisions § 1961). These pin the
// owner's toggle on the run detail photos: offered only when the run is
// linked to a race, unavailable for adding while the run is private, and a
// failed write surfaced rather than shown as done.

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/run_photos.dart';

RunPhotoRow _photo(String id, {bool shared = false}) => RunPhotoRow.fromJson({
      'id': id,
      'run_id': 'r1',
      'owner_id': 'owner-1',
      'storage_path': 'owner-1/r1/$id.jpg',
      'thumb_512_path': 'owner-1/r1/$id.512.jpg',
      'position_idx': 0,
      'created_at': '2026-10-01T09:00:00Z',
      'race_gallery': shared,
    });

class _RaceApi extends ApiClient {
  _RaceApi({
    required this.photos,
    this.context,
    this.viewer = 'owner-1',
    this.failWrites = false,
  });

  final List<RunPhotoRow> photos;
  final ({bool isPublic, String? raceListingId})? context;
  final String viewer;
  final bool failWrites;
  final List<(String, bool)> shareCalls = [];
  int contextReads = 0;

  @override
  String? get userId => viewer;

  @override
  Future<List<RunPhotoRow>> fetchRunPhotos(String runId,
          {int limit = 50}) async =>
      photos;

  @override
  Future<({bool isPublic, String? raceListingId})?> fetchRunRaceGalleryContext(
      String runId) async {
    contextReads++;
    return context;
  }

  @override
  Future<void> setRunPhotoRaceGallery(String photoId,
      {required bool shared}) async {
    shareCalls.add((photoId, shared));
    if (failWrites) throw Exception('network down');
  }
}

Future<void> _pump(WidgetTester tester, _RaceApi api) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RunPhotos(api: api, runId: 'r1', runOwnerId: 'owner-1'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const _show = 'Show on race page';
const _hide = 'Remove from race page';
const _private = 'Make this run public to share its photos on the race page.';

void main() {
  testWidgets('a public race-linked run offers the toggle and opts a photo in',
      (tester) async {
    final api = _RaceApi(
      photos: [_photo('a')],
      context: (isPublic: true, raceListingId: 'listing-1'),
    );
    await _pump(tester, api);

    expect(find.textContaining("this race's public page"), findsOneWidget);
    await tester.tap(find.byTooltip(_show));
    await tester.pumpAndSettle();

    expect(api.shareCalls, [('a', true)]);
    expect(find.byTooltip(_hide), findsOneWidget);
    expect(find.byTooltip(_show), findsNothing);
  });

  testWidgets('an opted-in photo can be withdrawn', (tester) async {
    final api = _RaceApi(
      photos: [_photo('a', shared: true)],
      context: (isPublic: true, raceListingId: 'listing-1'),
    );
    await _pump(tester, api);

    await tester.tap(find.byTooltip(_hide));
    await tester.pumpAndSettle();

    expect(api.shareCalls, [('a', false)]);
    expect(find.byTooltip(_show), findsOneWidget);
  });

  testWidgets('a private run explains why and cannot add a photo',
      (tester) async {
    final api = _RaceApi(
      photos: [_photo('a'), _photo('b', shared: true)],
      context: (isPublic: false, raceListingId: 'listing-1'),
    );
    await _pump(tester, api);

    expect(find.text(_private), findsOneWidget);
    await tester.tap(find.byTooltip(_private));
    await tester.pumpAndSettle();
    expect(api.shareCalls, isEmpty,
        reason: 'a private run photo must not be opted in');

    await tester.tap(find.byTooltip(_hide));
    await tester.pumpAndSettle();
    expect(api.shareCalls, [('b', false)],
        reason: 'withdrawing stays possible while the run is private');
  });

  testWidgets('a run with no race link shows no toggle', (tester) async {
    final api = _RaceApi(
      photos: [_photo('a')],
      context: (isPublic: true, raceListingId: null),
    );
    await _pump(tester, api);

    expect(find.byTooltip(_show), findsNothing);
    expect(find.textContaining("this race's public page"), findsNothing);
  });

  testWidgets('a non-owner viewer gets no toggle and no context read',
      (tester) async {
    final api = _RaceApi(
      photos: [_photo('a')],
      context: (isPublic: true, raceListingId: 'listing-1'),
      viewer: 'someone-else',
    );
    await _pump(tester, api);

    expect(find.byTooltip(_show), findsNothing);
    expect(api.contextReads, 0);
  });

  testWidgets('a failed write is surfaced and the photo stays as it was',
      (tester) async {
    final api = _RaceApi(
      photos: [_photo('a')],
      context: (isPublic: true, raceListingId: 'listing-1'),
      failWrites: true,
    );
    await _pump(tester, api);

    await tester.tap(find.byTooltip(_show));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Could not update the race page'),
        findsOneWidget);
    expect(find.byTooltip(_show), findsOneWidget);
    expect(find.byTooltip(_hide), findsNothing);

    // Let the banner's own timer and exit animation run out.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
  });
}
