import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Open/closed state for the named disclosures on a screen, remembered across
/// visits. Web twin: `apps/web/src/lib/util/disclosure_state.ts`.
///
/// SharedPreferences is device-scoped, not account-scoped, so the key carries
/// the account id — a phone signed into a second account must not hand it the
/// first account's layout. It is per-viewer view state, the same class as the
/// `runs_filters_v1` / `routes_filters_v1` blobs, so it stays local rather
/// than costing a `user_settings` bag key and a round trip on every toggle.
///
/// Every read and write is wrapped: a screen whose layout depends on this must
/// still render when the platform store is unavailable, and a failed read
/// falls back to the caller's defaults.

const String _kKeyPrefix = 'run_app.disclosure_v1';

typedef DisclosureState = Map<String, bool>;

typedef PrefsLoader = Future<SharedPreferences> Function();

String disclosureStorageKey(String scope, String? userId) =>
    '$_kKeyPrefix:$scope:${userId ?? 'anon'}';

/// Overlay a stored blob onto the defaults. A key the screen no longer
/// declares is dropped and a non-boolean value is ignored, so a section added
/// after the blob was written opens in the direction it was designed for
/// rather than in whatever the old blob happened to hold.
DisclosureState mergeDisclosureState(DisclosureState defaults, Object? stored) {
  final merged = Map<String, bool>.of(defaults);
  if (stored is! Map) return merged;
  for (final entry in stored.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String && merged.containsKey(key) && value is bool) {
      merged[key] = value;
    }
  }
  return merged;
}

Future<DisclosureState> readDisclosureState(
  String scope,
  String? userId,
  DisclosureState defaults, {
  PrefsLoader prefs = SharedPreferences.getInstance,
}) async {
  try {
    final p = await prefs();
    final raw = p.getString(disclosureStorageKey(scope, userId));
    return mergeDisclosureState(defaults, raw == null ? null : jsonDecode(raw));
  } catch (e) {
    debugPrint('readDisclosureState($scope) failed: $e');
    return Map<String, bool>.of(defaults);
  }
}

Future<void> writeDisclosureState(
  String scope,
  String? userId,
  DisclosureState state, {
  PrefsLoader prefs = SharedPreferences.getInstance,
}) async {
  try {
    final p = await prefs();
    await p.setString(disclosureStorageKey(scope, userId), jsonEncode(state));
  } catch (e) {
    debugPrint('writeDisclosureState($scope) failed: $e');
  }
}
