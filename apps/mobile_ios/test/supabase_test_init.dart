import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The `app_links` platform channels `supabase_flutter` listens on.
const appLinksChannels = [
  'com.llfbandit.app_links/events',
  'com.llfbandit.app_links/messages',
];

/// Boot the test Supabase client, with its deep-link channels stubbed first.
///
/// `supabase_flutter` opens an `app_links` stream on init. No plugin answers
/// it under `flutter test`, so the `MissingPluginException` is delivered on
/// the REAL event loop — and lands as an unhandled error in whichever test
/// happens to be turning that loop (`runAsync`, `pumpUntil`) when it fires.
/// That made the failure timing-dependent and pinned on an innocent case.
/// Every suite boots the client through here so the stub cannot be skipped;
/// `supabase_test_init_guard_test.dart` fails a direct `Supabase.initialize`.
///
/// Points at the local stack's port with a dummy key; nothing is reached.
Future<void> initializeTestSupabase() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in appLinksChannels) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            MethodChannel(name, const StandardMethodCodec()),
            (call) async => null);
  }
  await Supabase.initialize(
    url: 'http://127.0.0.1:24321',
    anonKey: 'eyJ.local.test',
  );
}
