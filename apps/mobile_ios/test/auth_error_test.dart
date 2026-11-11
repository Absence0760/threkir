import 'dart:io' show Directory, File, SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/auth_error.dart';
import '../lib/auth_validation.dart';
import '../lib/l10n/gen/app_localizations.dart';

/// Duck-typed stand-in for a Supabase `AuthException` (carries `code`
/// + `statusCode`) so the classifier can be exercised without importing
/// the supabase auth types.
class _FakeAuthException {
  const _FakeAuthException(this.message, {this.code, this.statusCode});
  final String message;
  final String? code;
  final String? statusCode;
  @override
  String toString() =>
      'AuthApiException(message: $message, statusCode: $statusCode, code: $code)';
}

void main() {
  group('classifyAuthError', () {
    test('SocketException → offline', () {
      expect(
        classifyAuthError(const SocketException('Failed host lookup: "x"')),
        AuthErrorKind.offline,
      );
    });

    test('ClientException "Failed host lookup" text → offline', () {
      expect(
        classifyAuthError(
          Exception('ClientException: Failed host lookup: "api.threkir.com"'),
        ),
        AuthErrorKind.offline,
      );
    });

    test('connection-refused / network-unreachable text → offline', () {
      expect(
        classifyAuthError(Exception('Connection refused')),
        AuthErrorKind.offline,
      );
      expect(
        classifyAuthError(Exception('Network is unreachable')),
        AuthErrorKind.offline,
      );
    });

    test('invalid_credentials code → invalidCredentials', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'Invalid login credentials',
            code: 'invalid_credentials',
            statusCode: '400',
          ),
        ),
        AuthErrorKind.invalidCredentials,
      );
    });

    test(
      '"Invalid login credentials" message (no code) → invalidCredentials',
      () {
        expect(
          classifyAuthError(
            const _FakeAuthException('Invalid login credentials'),
          ),
          AuthErrorKind.invalidCredentials,
        );
      },
    );

    test('statusCode 429 → rateLimited', () {
      expect(
        classifyAuthError(
          const _FakeAuthException('Too many requests', statusCode: '429'),
        ),
        AuthErrorKind.rateLimited,
      );
    });

    test('over_email_send_rate_limit code → rateLimited', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'For security purposes, you can only request this after 60 seconds',
            code: 'over_email_send_rate_limit',
          ),
        ),
        AuthErrorKind.rateLimited,
      );
    });

    test(
      'an Edge Function limiter code rethrown as the message → rateLimited',
      () {
        // `_shared/rate_limit.ts` answers 429 with `rate_limit_exceeded`; a
        // caller that rethrows `Exception(code)` keeps the code, not the status.
        expect(
          classifyAuthError(Exception('rate_limit_exceeded')),
          AuthErrorKind.rateLimited,
        );
      },
    );

    test('user_already_exists code → emailExists', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'User already registered',
            code: 'user_already_exists',
            statusCode: '422',
          ),
        ),
        AuthErrorKind.emailExists,
      );
    });

    test('"already registered" message (no code) → emailExists', () {
      expect(
        classifyAuthError(const _FakeAuthException('User already registered')),
        AuthErrorKind.emailExists,
      );
    });

    test('email_not_confirmed code → emailNotConfirmed', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'Email not confirmed',
            code: 'email_not_confirmed',
            statusCode: '400',
          ),
        ),
        AuthErrorKind.emailNotConfirmed,
      );
    });

    test('invalid_grant + "Email not confirmed" → emailNotConfirmed', () {
      // GoTrue's token endpoint can report an unconfirmed-email sign-in
      // via the OAuth-style invalid_grant error with the descriptive
      // message, not the dedicated code. The specific message must win
      // over the generic invalid_grant → invalidCredentials branch.
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'Email not confirmed',
            code: 'invalid_grant',
            statusCode: '400',
          ),
        ),
        AuthErrorKind.emailNotConfirmed,
      );
    });

    test('otp_expired code → linkExpired', () {
      // What supabase_flutter reports when an emailed sign-in,
      // confirmation or reset link is opened after it expired or twice
      // (Sentry THREKIR-CLIENT-7).
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'Email link is invalid or has expired',
            code: 'otp_expired',
            statusCode: 'access_denied',
          ),
        ),
        AuthErrorKind.linkExpired,
      );
    });

    test(
      '"link is invalid or has expired" message (no code) → linkExpired',
      () {
        expect(
          classifyAuthError(
            const _FakeAuthException('Email link is invalid or has expired'),
          ),
          AuthErrorKind.linkExpired,
        );
      },
    );

    test('weak_password code → weakPassword', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'Password should be at least 8 characters',
            code: 'weak_password',
            statusCode: '422',
          ),
        ),
        AuthErrorKind.weakPassword,
      );
    });

    test('"password should be at least" message (no code) → weakPassword', () {
      expect(
        classifyAuthError(
          const _FakeAuthException('Password should be at least 6 characters'),
        ),
        AuthErrorKind.weakPassword,
      );
    });

    test('a database code is not overridden by a word in its message', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'duplicate key value violates unique constraint "rate limit buckets_pkey"',
            code: '23505',
          ),
        ),
        AuthErrorKind.generic,
      );
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'relation "invalid credentials" does not exist',
            code: '42P01',
          ),
        ),
        AuthErrorKind.generic,
      );
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'connection closed by trigger',
            code: 'PGRST116',
          ),
        ),
        AuthErrorKind.generic,
      );
    });

    test('a bare-raise P0001 is still read by its message', () {
      expect(
        classifyAuthError(
          const _FakeAuthException(
            'rate limit exceeded for create_club, retry in 30s',
            code: 'P0001',
          ),
        ),
        AuthErrorKind.rateLimited,
      );
      // The RPCs' signed-out guard keeps its meaning under its 42501.
      expect(
        classifyAuthError(
          const _FakeAuthException('not authenticated', code: '42501'),
        ),
        AuthErrorKind.notSignedIn,
      );
    });

    test(
      'a five-character code that is not a SQLSTATE still has its message read',
      () {
        expect(
          classifyAuthError(
            const _FakeAuthException('Failed host lookup', code: 'EPIPE'),
          ),
          AuthErrorKind.offline,
        );
        expect(
          classifyAuthError(
            const _FakeAuthException(
              'Invalid login credentials',
              code: 'stale',
            ),
          ),
          AuthErrorKind.invalidCredentials,
        );
      },
    );

    test(
      'isDatabaseCode accepts SQLSTATE and PostgREST codes in either case',
      () {
        const codes = [
          '23505', '42501', '42P01', '22P02', '57014', 'P0001', 'P0002', //
          'XX000', 'HV000', 'F0000', 'TR001', 'RR001', 'RR002', 'RW001', //
          'PGRST116', 'PGRST301', 'PGRST303', 'PT429',
        ];
        for (final c in codes) {
          expect(isDatabaseCode(c), isTrue, reason: c);
          expect(isDatabaseCode(c.toLowerCase()), isTrue, reason: c);
        }
        for (final c in codes.where((c) => c != 'P0001')) {
          expect(databaseCodeDecides(c), isTrue, reason: c);
        }
        expect(databaseCodeDecides('P0001'), isFalse);
        expect(databaseCodeDecides('p0001'), isFalse);
      },
    );

    test('no GoTrue, Storage or network code is taken for a database code', () {
      const codes = [
        // GoTrue (auth-js ErrorCode): snake_case words, the shortest seven long.
        'bad_jwt', 'bad_json', 'conflict', 'not_admin', 'otp_expired', //
        'invalid_credentials', 'invalid_grant', 'email_exists', //
        'user_already_exists', 'email_not_confirmed', 'weak_password', //
        'same_password', 'over_request_rate_limit', //
        'over_email_send_rate_limit', 'session_not_found', 'user_not_found',
        // Storage API codes, and its string statusCode.
        'NoSuchKey', 'NoSuchBucket', 'InvalidJWT', 'AccessDenied', //
        'EntityTooLarge', 'S3Error', '404', '400',
        // Node / undici network errnos, five-letter ones included.
        'EPIPE', 'EPERM', 'EBUSY', 'EXDEV', 'ECONNREFUSED', 'ETIMEDOUT', //
        'EAI_AGAIN', 'UND_ERR_CONNECT_TIMEOUT',
        // Five characters but no SQLSTATE class, and PGRST without its digits.
        '10000', 'ABCDE', 'stale', 'PGRST', 'PGRSTX', '',
      ];
      for (final c in codes) {
        expect(isDatabaseCode(c), isFalse, reason: c);
        expect(isDatabaseCode(c.toLowerCase()), isFalse, reason: c);
      }
      expect(isDatabaseCode(null), isFalse);
    });

    test('every SQLSTATE a migration raises is a database code', () {
      final re = RegExp(
        r"errcode\s*=\s*'([0-9A-Za-z]{5})'",
        caseSensitive: false,
      );
      final seen = <String>{};
      for (final f in Directory(
        '../backend/supabase/migrations',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.sql'))) {
        for (final m in re.allMatches(f.readAsStringSync())) {
          seen.add(m.group(1)!);
        }
      }
      expect(
        seen.length,
        greaterThanOrEqualTo(10),
        reason: 'read ${seen.length} SQLSTATEs from the migrations',
      );
      for (final c in seen) {
        expect(
          isDatabaseCode(c),
          isTrue,
          reason: '$c is raised by a migration',
        );
      }
    });

    test('unrecognised error → generic', () {
      expect(classifyAuthError(Exception('boom')), AuthErrorKind.generic);
    });

    test('ApiClient "Not authenticated" guard → notSignedIn', () {
      expect(
        classifyAuthError(Exception('Not authenticated')),
        AuthErrorKind.notSignedIn,
      );
    });
  });

  group('signUpErrorRevealsAccountExistence', () {
    test(
      'an existing-email error would reveal account existence (issue #454)',
      () {
        // With GoTrue enable_confirmations=false a duplicate sign-up throws
        // user_already_exists; the sign-up surface must collapse that to the
        // SAME neutral check-your-email outcome a fresh sign-up shows, never a
        // distinct "that email already has an account" message. Mirror of web
        // auth_errors.test.ts (#399/#448).
        final dup = classifyAuthError(
          const _FakeAuthException(
            'User already registered',
            code: 'user_already_exists',
            statusCode: '422',
          ),
        );
        expect(dup, AuthErrorKind.emailExists);
        expect(signUpErrorRevealsAccountExistence(dup), isTrue);
      },
    );

    test('non-enumerating auth errors are not neutralised', () {
      final kinds = <Object>[
        const SocketException('x'),
        const _FakeAuthException(
          'Invalid login credentials',
          code: 'invalid_credentials',
          statusCode: '400',
        ),
        const _FakeAuthException('Too many requests', statusCode: '429'),
        const _FakeAuthException(
          'Password should be at least 8 characters',
          code: 'weak_password',
          statusCode: '422',
        ),
        const _FakeAuthException(
          'Email not confirmed',
          code: 'email_not_confirmed',
          statusCode: '400',
        ),
        Exception('boom'),
      ];
      for (final err in kinds) {
        expect(
          signUpErrorRevealsAccountExistence(classifyAuthError(err)),
          isFalse,
        );
      }
    });
  });

  testWidgets('friendlyAuthError returns the localized message per kind', (
    tester,
  ) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(
      friendlyAuthError(l10n, const SocketException('x')),
      l10n.authErrorOffline,
    );
    expect(
      friendlyAuthError(
        l10n,
        const _FakeAuthException('', code: 'invalid_credentials'),
      ),
      l10n.authErrorInvalidCredentials,
    );
    expect(
      friendlyAuthError(l10n, const _FakeAuthException('', statusCode: '429')),
      l10n.authErrorRateLimited,
    );
    expect(
      friendlyAuthError(
        l10n,
        const _FakeAuthException('', code: 'user_already_exists'),
      ),
      l10n.authErrorEmailExists,
    );
    expect(
      friendlyAuthError(
        l10n,
        const _FakeAuthException('', code: 'email_not_confirmed'),
      ),
      l10n.authErrorEmailNotConfirmed,
    );
    expect(
      friendlyAuthError(
        l10n,
        const _FakeAuthException('', code: 'otp_expired'),
      ),
      l10n.authErrorLinkExpired,
    );
    expect(
      friendlyAuthError(
        l10n,
        const _FakeAuthException('', code: 'weak_password'),
      ),
      l10n.authErrorWeakPassword(kPasswordMinLength),
    );
    expect(friendlyAuthError(l10n, Exception('boom')), l10n.authErrorGeneric);

    // The raw jargon never appears in a rendered message.
    final rendered = friendlyAuthError(
      l10n,
      Exception('AuthApiException(message: nope, statusCode: 500)'),
    );
    expect(rendered.contains('AuthApiException'), isFalse);
    expect(rendered, l10n.authErrorGeneric);

    // "Sign in to do this" makes no sense on the sign-in screens —
    // notSignedIn collapses to generic there…
    expect(
      friendlyAuthError(l10n, Exception('Not authenticated')),
      l10n.authErrorGeneric,
    );
  });

  testWidgets('friendlyError surfaces the not-signed-in message', (
    tester,
  ) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = AppLocalizations.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    // …but on every other surface (kudos, follow, submit-result) the
    // ApiClient's Exception('Not authenticated') guard becomes an
    // actionable "sign in" message, never "Exception: Not authenticated".
    final rendered = friendlyError(l10n, Exception('Not authenticated'));
    expect(rendered, l10n.authErrorNotSignedIn);
    expect(rendered.contains('Exception'), isFalse);
  });
}
