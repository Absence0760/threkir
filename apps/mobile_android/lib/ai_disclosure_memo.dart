import 'ai_disclosure.dart';

/// The last AI-consent record this process read or wrote, per signed-in user,
/// so the Coach can open straight into the chat instead of a loading screen
/// while it re-asks the server. Home already reads the same `get_my_profile()`
/// row on launch, so by the time the runner taps "Ask your coach" the answer
/// is usually here.
///
/// It decides only what the Coach screen shows FIRST. The screen still fetches
/// the record on every open and swaps to the disclosure if the server
/// disagrees, and the Coach endpoint grades consent itself on every turn, so a
/// stale memo can never serve a turn the runner has not consented to. Every
/// writer of the record updates it, and a withdrawal clears it.
class AiDisclosureMemo {
  AiDisclosureMemo._();

  static String? _userId;
  static AiDisclosureRecord? _record;

  static void remember(String userId, AiDisclosureRecord record) {
    _userId = userId;
    _record = record;
  }

  /// The memo for [userId], or null when it holds nothing for that user.
  static AiDisclosureRecord? peek(String? userId) =>
      userId != null && userId == _userId ? _record : null;

  static void forget() {
    _userId = null;
    _record = null;
  }
}
