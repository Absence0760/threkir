import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Pins the auth-transition seam for issues #223/#232: identity-bearing
/// screens subscribe to [ApiClient.authUserChanges] to learn that the
/// session ended or a different account signed in. Two contracts matter:
/// the stream must be offline-safe (uninitialised Supabase → empty
/// stream, never a throw), and a sign-out must surface as a null-user
/// event so subscribers can drop the departed user's data.
void main() {
  test('returns an empty stream when Supabase was never initialised', () async {
    final api = ApiClient();
    expect(await api.authUserChanges.isEmpty, isTrue);
  });

  test('maps a sign-out to a null user-id event', () async {
    // Port 9 (discard) is never listening — a local-scope sign-out with
    // no session never hits the wire, so this exercises only the event
    // plumbing.
    final client = SupabaseClient('http://127.0.0.1:9', 'eyJ.local.test');
    addTearDown(client.dispose);
    final api = ApiClient.withClient(client);

    final events = <String?>[];
    final sub = api.authUserChanges.listen(events.add);
    addTearDown(sub.cancel);

    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);

    expect(events, isNotEmpty);
    expect(events.last, isNull);
  });

  test('a refused auth deep link does not reach subscribers as an error',
      () async {
    // supabase_flutter adds an expired / reused email link's
    // AuthException to onAuthStateChange as a stream error. Unhandled,
    // it became a fatal crash (Sentry THREKIR-CLIENT-7).
    final client = SupabaseClient('http://127.0.0.1:9', 'eyJ.local.test');
    addTearDown(client.dispose);
    final api = ApiClient.withClient(client);

    final errors = <Object>[];
    final events = <String?>[];
    final sub = api.authUserChanges.listen(events.add, onError: errors.add);
    addTearDown(sub.cancel);

    // ignore: invalid_use_of_internal_member
    client.auth.notifyException(const AuthException(
      'Email link is invalid or has expired',
      statusCode: 'access_denied',
      code: 'otp_expired',
    ));
    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
    expect(events.last, isNull);
  });
}
