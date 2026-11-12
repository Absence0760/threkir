import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/auth_stream_error.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/widgets/top_banner.dart';

/// supabase_flutter reports an emailed link that expired or was already
/// used by adding the AuthException to `onAuthStateChange` as an error.
/// Unhandled, that was a fatal crash with nothing shown (Sentry
/// THREKIR-CLIENT-7); the app root now hands it to [showAuthStreamError].
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
}
