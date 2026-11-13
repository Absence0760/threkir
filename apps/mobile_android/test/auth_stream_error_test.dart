import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/auth_change_aware.dart';
import '../lib/auth_stream_error.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/top_banner.dart';

/// supabase_flutter reports an emailed link that expired or was already
/// used by adding the AuthException to `onAuthStateChange` as an error.
/// Unhandled, that was a fatal crash with nothing shown (Sentry
/// THREKIR-CLIENT-7); the app root now hands it to [showAuthStreamError].
class _AuthApi extends ApiClient {
  String? uid = 'a';
  final controller = StreamController<String?>.broadcast();

  @override
  String? get userId => uid;

  @override
  Stream<String?> get authUserChanges => controller.stream;
}

class _Aware extends StatefulWidget {
  const _Aware(this.api, this.seen);
  final _AuthApi api;
  final List<String?> seen;

  @override
  State<_Aware> createState() => _AwareState();
}

class _AwareState extends State<_Aware> with AuthChangeAware<_Aware> {
  @override
  ApiClient? get authApi => widget.api;

  @override
  void onAuthUserChanged(String? userId) => widget.seen.add(userId);

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// The `.listen(` calls on an auth stream in `lib/`, each with the text of
/// its argument list.
Iterable<({String file, String args})> _authStreamListens() sync* {
  final start = RegExp(r'(onAuthStateChange|authUserChanges)\s*\.listen\(');
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    for (final m in start.allMatches(src)) {
      var depth = 1;
      var i = m.end;
      while (i < src.length && depth > 0) {
        final c = src[i];
        if (c == '(') depth++;
        if (c == ')') depth--;
        i++;
      }
      yield (file: f.path, args: src.substring(m.end, i));
    }
  }
}

void main() {
  testWidgets('an expired email link tells the person to request a new one',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    late AppLocalizations l10n;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l10n = AppLocalizations.of(context);
        return const Scaffold(body: SizedBox.expand());
      }),
    ));

    showAuthStreamError(
      const AuthException(
        'Email link is invalid or has expired',
        statusCode: 'access_denied',
        code: 'otp_expired',
      ),
      navigatorKey: navigatorKey,
    );
    await tester.pump();

    expect(find.text(l10n.authErrorLinkExpired), findsOneWidget);
    expect(find.textContaining('AuthException'), findsNothing);

    await tester.pump(kTopBannerMaxDuration + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text(l10n.authErrorLinkExpired), findsNothing);
  });

  testWidgets('does nothing before the navigator exists', (tester) async {
    showAuthStreamError(
      const AuthException('Email link is invalid or has expired',
          code: 'otp_expired'),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
  });

  // Sentry THREKIR-CLIENT-2: offline, every auto-refresh tick near expiry
  // adds an AuthRetryableFetchException to the stream. The SDK retries it
  // itself, so there is nothing to tell the person.
  testWidgets('an offline token refresh is logged, not shown', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SizedBox.expand()),
    ));

    showAuthStreamError(
      AuthRetryableFetchException(
        message: 'ClientException with SocketException: Failed host lookup',
      ),
      navigatorKey: navigatorKey,
    );
    await tester.pump();

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('a screen on AuthChangeAware outlives an erroring auth stream '
      'and still follows the next sign-out', (tester) async {
    final api = _AuthApi();
    addTearDown(api.controller.close);
    final seen = <String?>[];
    await tester.pumpWidget(_Aware(api, seen));

    api.controller.addError(AuthRetryableFetchException(
        message: 'ClientException: Connection closed'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    api.uid = null;
    api.controller.add(null);
    await tester.pump();
    expect(seen, [null]);
  });

  test('every auth-stream subscription in lib/ handles the stream errors',
      () {
    // supabase_flutter adds a refused auth link and an offline token refresh
    // to the stream as errors, and the stream replays its latest error to a
    // new subscriber: a listener without onError turns either into an
    // unhandled fatal error (Sentry THREKIR-CLIENT-2, -6, -7).
    final listens = _authStreamListens().toList();
    expect(listens, isNotEmpty);
    for (final l in listens) {
      expect(l.args, contains('onError:'), reason: l.file);
    }
    final unguarded = RegExp(
        r'(onAuthStateChange|authUserChanges)\s*\.(first|firstWhere|last|single)\b|await\s+for\s*\([^)]*(onAuthStateChange|authUserChanges)');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      expect(unguarded.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}
