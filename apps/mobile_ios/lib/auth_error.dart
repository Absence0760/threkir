import 'dart:io' show SocketException;

import 'auth_validation.dart';
import 'l10n/gen/app_localizations.dart';

/// Friendly, actionable categories an auth failure maps to. The raw
/// exception text (`ClientException: Failed host lookup`, a Supabase
/// `AuthApiException` toString) is developer jargon no end user should
/// read — classify it into one of these instead so the banner can tell
/// "wrong password" from "offline" from "rate-limited" from "that
/// email already has an account". Web mirrors the classification in
/// `apps/web/src/lib/core/auth_errors.ts` — keep the branches in sync.
/// [notSignedIn] is mobile-only: it classifies the `ApiClient` session
/// guards, which have no web counterpart.
enum AuthErrorKind {
  offline,
  invalidCredentials,
  rateLimited,
  notSignedIn,
  emailExists,
  emailNotConfirmed,
  linkExpired,
  weakPassword,
  generic,
}

/// Classify an arbitrary auth exception. Structural / duck-typed: reads
/// the error's `code` + `statusCode` when present (Supabase's
/// `AuthException` carries both) and falls back to matching the
/// stringified message, so it works for `SocketException`, `http`'s
/// `ClientException`, and Supabase auth errors without importing them.
/// A database code is never overridden by a word in its message.
AuthErrorKind classifyAuthError(Object error) {
  if (error is SocketException) return AuthErrorKind.offline;

  final code = _stringProp(error, (e) => e.code)?.toLowerCase();
  final status = _statusCode(error);
  final msg = error.toString().toLowerCase();
  final readMsg = !databaseCodeDecides(code);
  bool says(String text) => readMsg && msg.contains(text);

  if (readMsg && _looksOffline(msg)) return AuthErrorKind.offline;

  if (status == 429 ||
      (code != null && code.contains('rate')) ||
      code == 'over_email_send_rate_limit' ||
      code == 'over_request_rate_limit' ||
      says('rate limit') ||
      // The Edge Functions' shared limiter answers 429 with this code, and a
      // caller that rethrows the code as its message loses the status.
      says('rate_limit_exceeded') ||
      says('too many requests')) {
    return AuthErrorKind.rateLimited;
  }

  // Checked BEFORE invalidCredentials: GoTrue's token endpoint can
  // report an unconfirmed-email sign-in as the OAuth-style invalid_grant
  // error carrying the descriptive message "Email not confirmed", not
  // only via the dedicated email_not_confirmed code. The
  // invalidCredentials branch below also matches invalid_grant, so this
  // specific-message check has to win first — otherwise the user gets a
  // wrong-password message for an unconfirmed account (issue #486).
  if (code == 'email_not_confirmed' || says('email not confirmed')) {
    return AuthErrorKind.emailNotConfirmed;
  }

  // An emailed magic / confirmation / reset link opened after it expired
  // or a second time. The fix is a fresh link, which no other kind says.
  if (code == 'otp_expired' || says('link is invalid or has expired')) {
    return AuthErrorKind.linkExpired;
  }

  if (code == 'invalid_credentials' ||
      code == 'invalid_grant' ||
      says('invalid login credentials') ||
      says('invalid credentials')) {
    return AuthErrorKind.invalidCredentials;
  }

  if (code == 'user_already_exists' ||
      code == 'email_exists' ||
      says('already registered')) {
    return AuthErrorKind.emailExists;
  }

  if (code == 'weak_password' ||
      says('weak password') ||
      says('password should be at least') ||
      says('password should contain at least')) {
    return AuthErrorKind.weakPassword;
  }

  // ApiClient guards throw Exception('Not authenticated') when an action
  // needs a session — actionable ("sign in"), so don't collapse to generic.
  // The RPCs raise the same words under 42501 when auth.uid() is null.
  if ((readMsg || code == '42501') && msg.contains('not authenticated')) {
    return AuthErrorKind.notSignedIn;
  }

  return AuthErrorKind.generic;
}

/// Map an auth exception to a localized, user-facing message. Route every
/// rendered `_error =` assignment on the sign-in / sign-up screens through
/// this; keep the raw string in `debugPrint` only.
String friendlyAuthError(AppLocalizations l10n, Object error) {
  switch (classifyAuthError(error)) {
    case AuthErrorKind.offline:
      return l10n.authErrorOffline;
    case AuthErrorKind.invalidCredentials:
      return l10n.authErrorInvalidCredentials;
    case AuthErrorKind.rateLimited:
      return l10n.authErrorRateLimited;
    case AuthErrorKind.emailExists:
      return l10n.authErrorEmailExists;
    case AuthErrorKind.emailNotConfirmed:
      return l10n.authErrorEmailNotConfirmed;
    case AuthErrorKind.linkExpired:
      return l10n.authErrorLinkExpired;
    case AuthErrorKind.weakPassword:
      return l10n.authErrorWeakPassword(kPasswordMinLength);
    // "Sign in to do this" makes no sense on the sign-in screens
    // themselves — collapse to generic there.
    case AuthErrorKind.notSignedIn:
    case AuthErrorKind.generic:
      return l10n.authErrorGeneric;
  }
}

/// Whether surfacing this error kind at the SIGN-UP surface would
/// disclose that an email is already registered. GoTrue only
/// obfuscates a duplicate sign-up (returning a session-less success
/// identical to a fresh one) when email confirmations are ON — a
/// dashboard-managed setting invisible from this repo. With
/// confirmations OFF a duplicate address throws `user_already_exists`
/// (→ [AuthErrorKind.emailExists]), which would otherwise render a
/// distinct "that email already has an account" message and turn
/// sign-up into an account-existence oracle. Defence in depth: the
/// sign-up screen collapses this to the same neutral check-your-email
/// state a fresh sign-up shows, regardless of the server toggle. The
/// full fix is prod GoTrue running `enable_confirmations = true` — see
/// docs/features/web_app_auth.md. Sign-IN is unaffected: an existing
/// email there classifies as [AuthErrorKind.invalidCredentials], which
/// is standard. Mirrors web's `signUpErrorRevealsAccountExistence` in
/// `apps/web/src/lib/core/auth_errors.ts` — keep the two in sync.
bool signUpErrorRevealsAccountExistence(AuthErrorKind kind) =>
    kind == AuthErrorKind.emailExists;

/// Map an arbitrary exception on a non-auth form screen (club, coach, plan,
/// invite) to a localized, user-facing message. Reuses [classifyAuthError]'s
/// offline / rate-limited detection; the credential-shaped branches can't
/// arise off the sign-in / sign-up screens, so they collapse into the
/// generic fallback. Route every rendered `_error =` assignment on those
/// screens through this and keep the raw string in `debugPrint` only.
String friendlyError(AppLocalizations l10n, Object error) {
  switch (classifyAuthError(error)) {
    case AuthErrorKind.offline:
      return l10n.authErrorOffline;
    case AuthErrorKind.rateLimited:
      return l10n.authErrorRateLimited;
    case AuthErrorKind.notSignedIn:
      return l10n.authErrorNotSignedIn;
    case AuthErrorKind.linkExpired:
      return l10n.authErrorLinkExpired;
    case AuthErrorKind.invalidCredentials:
    case AuthErrorKind.emailExists:
    case AuthErrorKind.emailNotConfirmed:
    case AuthErrorKind.weakPassword:
    case AuthErrorKind.generic:
      return l10n.authErrorGeneric;
  }
}

/// True when [error] is the data layer's signed-out rejection — the
/// `StateError('not signed in')` guard, a service's 'Not authenticated'
/// throw, a 401, or the Postgres permission failure (42501) an anon
/// request gets from an authenticated-only grant. Callers route these
/// into the shared sign-in-required state instead of a generic error +
/// a Retry that can never succeed.
bool isSignedOutError(Object error) {
  final code = _stringProp(error, (e) => e.code)?.toLowerCase();
  if (code == '42501') return true;
  if (_statusCode(error) == 401) return true;
  final msg = error.toString().toLowerCase();
  return msg.contains('not signed in') || msg.contains('not authenticated');
}

/// SQLSTATE classes a database error can carry: every class Postgres and
/// PL/pgSQL define, plus the classes this project's own RPCs raise (`RR`
/// restart_training_plan, `RW` the recurrence dry run, `TR`
/// trim_training_plan, `PC` the propose_plan_change dry run). A test reads every `errcode` in the migrations and
/// fails when a new one is not covered here.
const _sqlstateClasses = {
  '00', '01', '02', '03', '08', '09', '0A', '0B', '0F', '0L', '0P', '0Z', //
  '20', '21', '22', '23', '24', '25', '26', '27', '28', '2B', '2D', '2F', //
  '34', '38', '39', '3B', '3D', '3F', '40', '42', '44', '53', '54', '55', //
  '57', '58', '72', 'F0', 'HV', 'P0', 'XX', //
  'RR', 'RW', 'TR', 'PC',
};

final _pgrst = RegExp(r'^PGRST\d{3}$');
final _sqlstate = RegExp(r'^[0-9A-Z]{5}$');

/// Whether [code] is a SQLSTATE or a PostgREST `PGRST` code, in any case.
/// A bare five-character test also took an errno like `EPIPE` and any
/// five-letter word an auth or storage service might send; a SQLSTATE is
/// five characters of `[0-9A-Z]` whose first two name a known class, and
/// GoTrue's snake_case codes and Storage's CamelCase ones can never be one.
/// Mirrors `isDatabaseCode` in web's `core/auth_errors.ts`.
bool isDatabaseCode(String? code) {
  if (code == null || code.isEmpty) return false;
  final c = code.toUpperCase();
  if (_pgrst.hasMatch(c)) return true;
  return _sqlstate.hasMatch(c) && _sqlstateClasses.contains(c.substring(0, 2));
}

/// A database code that decides the category on its own, so the message is
/// not read for one its code does not have. `P0001` is the exception: a
/// bare `raise exception` carries it whatever the failure is, and its
/// message is all there is. Mirrors `databaseCodeDecides` in web's
/// `core/auth_errors.ts`.
bool databaseCodeDecides(String? code) =>
    isDatabaseCode(code) && code!.toUpperCase() != 'P0001';

bool _looksOffline(String msg) =>
    msg.contains('failed host lookup') ||
    msg.contains('socketexception') ||
    msg.contains('clientexception') ||
    msg.contains('network is unreachable') ||
    msg.contains('connection refused') ||
    msg.contains('connection closed') ||
    msg.contains('connection reset') ||
    msg.contains('connection timed out') ||
    msg.contains('operation timed out') ||
    msg.contains('no address associated with hostname') ||
    msg.contains('handshake');

String? _stringProp(Object error, dynamic Function(dynamic) get) {
  try {
    final v = get(error as dynamic);
    return v is String ? v : null;
  } catch (_) {
    return null;
  }
}

int? _statusCode(Object error) {
  try {
    final s = (error as dynamic).statusCode;
    if (s is int) return s;
    if (s is String) return int.tryParse(s);
    return null;
  } catch (_) {
    return null;
  }
}
