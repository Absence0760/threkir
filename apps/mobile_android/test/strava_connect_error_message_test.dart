import 'package:core_models/core_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/settings_integrations_screen.dart';

/// A refused Strava connect (or a sync Strava refuses for a revoked grant,
/// `refresh_failed`) used to put whatever the function's body held
/// into "Strava connect failed: {error}" — a machine code, or for a missing
/// permission an English sentence in every locale. The code now picks a
/// reason and the reason picks the sentence.
void main() {
  const codes = [
    'strava_not_configured',
    'invalid_redirect_uri',
    'missing_scope',
    'strava_token_exchange_failed',
    'invalid_code',
    'unauthorized',
    'store_tokens_failed',
    'refresh_failed',
  ];

  for (final locale in AppLocalizations.supportedLocales) {
    final l10n = lookupAppLocalizations(locale);
    test('$locale: no code reaches the sentence', () {
      for (final code in codes) {
        final text =
            stravaConnectErrorMessage(l10n, stravaConnectError(code));
        expect(text, isNotEmpty, reason: code);
        expect(text, isNot(contains(code)), reason: code);
      }
    });
  }

  test('each reason reads as its own copy', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(stravaConnectErrorMessage(l10n, StravaConnectError.missingScope),
        l10n.integrationsStravaErrMissingScope);
    expect(stravaConnectErrorMessage(l10n, StravaConnectError.notConfigured),
        l10n.integrationsStravaErrNotConfigured);
    expect(stravaConnectErrorMessage(l10n, StravaConnectError.codeRejected),
        l10n.integrationsStravaErrCodeRejected);
    expect(stravaConnectErrorMessage(l10n, StravaConnectError.signedOut),
        l10n.authErrorNotSignedIn);
    expect(stravaConnectErrorMessage(l10n, StravaConnectError.reconnect),
        l10n.integrationsStravaErrReconnect);
    expect(stravaConnectErrorMessage(l10n, StravaConnectError.generic),
        l10n.authErrorGeneric);
  });
}
