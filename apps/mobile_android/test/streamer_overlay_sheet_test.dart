import 'package:api_client/api_client.dart' show ApiClient, LiveOverlay;
import 'package:core_models/core_models.dart' show DistanceUnit;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/streamer_overlay.dart';
import '../lib/widgets/streamer_overlay_sheet.dart';

/// Stands in for the server: [overlay] is what `get_live_overlay` returns,
/// and create / setDelay change it the way the RPCs do.
class _FakeController implements StreamerOverlayController {
  LiveOverlay? overlay;
  Object? loadError;
  Object? createError;
  int loads = 0;
  int creates = 0;
  int revokes = 0;
  final delays = <int>[];

  _FakeController({this.overlay});

  @override
  Future<LiveOverlay?> load() async {
    loads++;
    if (loadError != null) throw loadError!;
    return overlay;
  }

  @override
  Future<String> create() async {
    creates++;
    if (createError != null) throw createError!;
    final token = 'tok-$creates';
    overlay = overlay?.copyWith(token: token) ??
        LiveOverlay(
            token: token,
            delaySeconds: 60,
            showMap: false,
            showHeartRate: false);
    return token;
  }

  @override
  Future<void> revoke() async => revokes++;

  @override
  Future<LiveOverlay?> setDelay(int delaySeconds) async {
    delays.add(delaySeconds);
    overlay = overlay?.copyWith(delaySeconds: delaySeconds);
    return overlay;
  }
}

class _FakeApi implements ApiClient {
  LiveOverlay? server;
  final updates = <Map<String, Object>>[];

  _FakeApi(this.server);

  @override
  Future<LiveOverlay?> fetchLiveOverlay() async => server;

  @override
  Future<void> updateLiveOverlaySettings({
    required int delaySeconds,
    required bool showMap,
    required bool showHeartRate,
  }) async {
    updates.add({
      'delay': delaySeconds,
      'map': showMap,
      'hr': showHeartRate,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _existing = LiveOverlay(
    token: 'abc', delaySeconds: 60, showMap: true, showHeartRate: true);

Future<void> _pump(WidgetTester tester, _FakeController c,
    {Future<bool> Function(Uri url)? openUrl}) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: StreamerOverlaySheet(
        controller: c,
        webBase: 'https://threkir.test/',
        unit: DistanceUnit.mi,
        openUrl: openUrl ?? (_) async => true,
      ),
    ),
  ));
  await tester.pump();
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  test('the URL carries the token in the fragment, never the path or query',
      () {
    expect(
      streamerOverlayUrl('https://threkir.test/', 'a-b_c', unit: DistanceUnit.km),
      'https://threkir.test/live/overlay?units=km#a-b_c',
    );
    expect(streamerOverlayUrl('https://threkir.test', 'tok'),
        'https://threkir.test/live/overlay#tok');
  });

  test('the closed gate is told apart from other failures', () {
    expect(isLiveOverlayDisabledError(Exception('live_overlay_disabled')),
        isTrue);
    expect(isLiveOverlayDisabledError(Exception('socket closed')), isFalse);
  });

  testWidgets('the trace and heart-rate note opens web privacy settings',
      (tester) async {
    // Those two switches exist only on web; the note used to recite a
    // Settings path, and now a button opens the page itself.
    final opened = <Uri>[];
    await _pump(tester, _FakeController(overlay: _existing),
        openUrl: (url) async {
      opened.add(url);
      return true;
    });
    final link = _key('streamer-overlay-web-settings');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    expect(opened, [Uri.parse('https://threkir.test/settings/privacy')]);
  });

  testWidgets('a browser that cannot open the page says so', (tester) async {
    await _pump(tester, _FakeController(overlay: _existing),
        openUrl: (_) async => false);
    final link = _key('streamer-overlay-web-settings');
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pump();
    expect(find.text('Could not open https://threkir.test/settings/privacy'),
        findsOneWidget);
  });

  testWidgets('no overlay yet: Create makes one and shows its link',
      (tester) async {
    final c = _FakeController();
    await _pump(tester, c);
    expect(_key('streamer-overlay-url'), findsNothing);
    await tester.tap(_key('streamer-overlay-create'));
    await tester.pump();
    expect(c.creates, 1);
    expect(find.text('https://threkir.test/live/overlay?units=mi#tok-1'),
        findsOneWidget);
    expect(find.text('Overlay link ready'), findsOneWidget);
  });

  testWidgets('Copy puts the overlay link on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester, _FakeController(overlay: _existing));
    await tester.tap(_key('streamer-overlay-copy'));
    await tester.pump();
    expect(copied, 'https://threkir.test/live/overlay?units=mi#abc');
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('Turn off asks first, and cancelling keeps the overlay',
      (tester) async {
    final c = _FakeController(overlay: _existing);
    await _pump(tester, c);
    await tester.tap(_key('streamer-overlay-revoke'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Turn off the streamer overlay?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.revokes, 0);
    expect(_key('streamer-overlay-url'), findsOneWidget);
  });

  testWidgets('confirming Turn off revokes the link', (tester) async {
    final c = _FakeController(overlay: _existing);
    await _pump(tester, c);
    await tester.tap(_key('streamer-overlay-revoke'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Turn off overlay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.revokes, 1);
    expect(_key('streamer-overlay-url'), findsNothing);
    expect(_key('streamer-overlay-create'), findsOneWidget);
  });

  testWidgets('Replace asks first, then makes a new token', (tester) async {
    final c = _FakeController(overlay: _existing);
    await _pump(tester, c);
    await tester.tap(_key('streamer-overlay-replace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Replace the overlay link?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Replace link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.creates, 1);
    expect(find.text('https://threkir.test/live/overlay?units=mi#tok-1'),
        findsOneWidget);
  });

  testWidgets('Replace shows the settings the server kept, not the stale copy',
      (tester) async {
    final c = _FakeController(overlay: _existing);
    await _pump(tester, c);
    c.overlay = const LiveOverlay(
        token: 'abc', delaySeconds: 300, showMap: false, showHeartRate: false);
    await tester.tap(_key('streamer-overlay-replace'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Replace link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(_key('streamer-overlay-delay-300'));
    expect(
        tester
            .widget<ChoiceChip>(_key('streamer-overlay-delay-300'))
            .selected,
        isTrue);
  });

  test('setDelay sends the map and heart-rate choices the server holds now',
      () async {
    final api = _FakeApi(const LiveOverlay(
        token: 'abc', delaySeconds: 60, showMap: false, showHeartRate: true));
    final saved = await ApiStreamerOverlayController(api).setDelay(300);
    expect(api.updates, [
      {'delay': 300, 'map': false, 'hr': true}
    ]);
    expect(saved?.delaySeconds, 300);
    expect(saved?.showMap, isFalse);
    expect(saved?.showHeartRate, isTrue);
  });

  test('setDelay writes nothing when the overlay no longer exists', () async {
    final api = _FakeApi(null);
    expect(await ApiStreamerOverlayController(api).setDelay(300), isNull);
    expect(api.updates, isEmpty);
  });

  testWidgets('picking a delay saves it',
      (tester) async {
    final c = _FakeController(overlay: _existing);
    await _pump(tester, c);
    expect(
        tester
            .widget<ChoiceChip>(_key('streamer-overlay-delay-60'))
            .selected,
        isTrue);
    await tester.ensureVisible(_key('streamer-overlay-delay-300'));
    await tester.tap(_key('streamer-overlay-delay-300'));
    await tester.pump();
    expect(c.delays, [300]);
    expect(
        tester
            .widget<ChoiceChip>(_key('streamer-overlay-delay-300'))
            .selected,
        isTrue);
    expect(find.text('No delay'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
  });

  testWidgets('a failed load offers Retry instead of claiming no overlay',
      (tester) async {
    final c = _FakeController(overlay: _existing)..loadError = Exception('x');
    await _pump(tester, c);
    expect(_key('streamer-overlay-load-error'), findsOneWidget);
    expect(_key('streamer-overlay-create'), findsNothing);
    c.loadError = null;
    await tester.tap(_key('streamer-overlay-retry'));
    await tester.pump();
    expect(c.loads, 2);
    expect(_key('streamer-overlay-url'), findsOneWidget);
  });

  testWidgets('a closed gate on create says the overlay is unavailable',
      (tester) async {
    final c = _FakeController()
      ..createError = Exception('P0001 live_overlay_disabled');
    await _pump(tester, c);
    await tester.tap(_key('streamer-overlay-create'));
    await tester.pump();
    expect(find.text("The streamer overlay isn't available right now."),
        findsOneWidget);
    expect(_key('streamer-overlay-url'), findsNothing);
  });

  testWidgets('any other create failure says so', (tester) async {
    final c = _FakeController()..createError = Exception('socket closed');
    await _pump(tester, c);
    await tester.tap(_key('streamer-overlay-create'));
    await tester.pump();
    expect(find.text("Couldn't create the overlay link. Try again."),
        findsOneWidget);
  });
}
