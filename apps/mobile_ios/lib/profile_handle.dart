// The public @handle (migration 20270424000002, issue #465): lowercase
// [a-z0-9_], 3-30 characters, stored lowercased by `set_my_handle`. The same
// rule as web's account page, checked here so a bad handle is refused before
// a round trip, and the server's refusals are told apart.

/// The form `set_my_handle` stores: trimmed, lowercased, one leading `@`
/// dropped (people type it).
String normalizeHandle(String input) {
  final t = input.trim().toLowerCase();
  return t.startsWith('@') ? t.substring(1) : t;
}

final _handlePattern = RegExp(r'^[a-z0-9_]{3,30}$');

/// Whether [normalized] may be saved. Empty clears the handle, so it passes.
bool isValidHandle(String normalized) =>
    normalized.isEmpty || _handlePattern.hasMatch(normalized);

enum HandleRefusal { taken, invalid }

/// Which refusal a `set_my_handle` failure is, or null for any other error.
HandleRefusal? handleRefusalOf(Object error) {
  final text = error.toString();
  if (text.contains('handle_taken')) return HandleRefusal.taken;
  if (text.contains('handle_invalid')) return HandleRefusal.invalid;
  // The unique index is the race backstop: two claims in the same instant.
  if (text.contains('user_profiles_handle_lower_key')) {
    return HandleRefusal.taken;
  }
  return null;
}
