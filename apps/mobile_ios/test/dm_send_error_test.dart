import 'dart:io';

import 'package:api_client/api_client.dart' show DmSendNotPermitted;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../lib/dm_send_error.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/rate_limit_message.dart';

// The four answers a sender can act on differently must never collapse into
// one another (decisions § 734, § 737).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('the follow / block gate reads as not allowed, naming neither cause', () {
    expect(dmSendErrorMessage(en, const DmSendNotPermitted()),
        en.messagesSendNotAllowed);
  });

  test('the send throttle reads its own wait, not a generic failure', () {
    const error = PostgrestException(
        code: 'P0001',
        message: 'rate limit exceeded for send_dm, retry in 30s');
    final throttled =
        rateLimitErrorMessage(en, code: error.code, message: error.message);
    expect(throttled, isNotNull);
    expect(dmSendErrorMessage(en, error), throttled);
    expect(dmSendErrorMessage(en, error), isNot(en.messagesSendFailed));
    expect(dmSendErrorMessage(en, error), isNot(en.authErrorOffline));
  });

  test('a dropped connection reads as offline', () {
    expect(dmSendErrorMessage(en, const SocketException('Network is unreachable')),
        en.authErrorOffline);
  });

  test('any other failure reads as a plain send failure', () {
    expect(dmSendErrorMessage(en, StateError('boom')), en.messagesSendFailed);
    expect(
        dmSendErrorMessage(
            en,
            const PostgrestException(
                code: '42501', message: 'permission denied for table messages')),
        en.messagesSendFailed);
  });

  test('the four answers are four different sentences in every locale', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      final answers = {
        dmSendErrorMessage(l10n, const DmSendNotPermitted()),
        dmSendErrorMessage(
            l10n,
            const PostgrestException(
                code: 'P0001',
                message: 'rate limit exceeded for send_dm, retry in 30s')),
        dmSendErrorMessage(l10n, const SocketException('down')),
        dmSendErrorMessage(l10n, StateError('boom')),
      };
      expect(answers, hasLength(4), reason: '$locale');
    }
  });
}
