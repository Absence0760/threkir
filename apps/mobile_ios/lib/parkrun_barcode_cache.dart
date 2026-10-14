import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'parkrun_barcode.dart';

/// The device's copy of the runner's parkrun athlete number, so the barcode
/// opens at a finish funnel with no signal. The durable home is
/// `user_profiles.parkrun_number` (owner-only, read through `get_my_profile`);
/// this is a cache of it, refreshed whenever the barcode screen can reach the
/// server.
///
/// The entry is tagged with the account that wrote it and read back only for
/// that account, and sign-out clears it, so a phone handed to someone else
/// never shows the previous runner's number.
class ParkrunBarcodeCache {
  const ParkrunBarcodeCache();

  @visibleForTesting
  static const storageKey = 'parkrun_barcode_cache';

  /// Ticks on every write and clear, so a shortcut that only shows once a
  /// number exists can follow a save made on another screen.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  Future<String?> read(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['user_id'] != userId) return null;
      final number = decoded['number'];
      return number is String ? normalizeParkrunAthleteNumber(number) : null;
    } catch (e) {
      debugPrint('parkrun barcode cache read failed: $e');
      return null;
    }
  }

  /// Stores [number] for [userId]; a null [number] forgets it.
  Future<void> write(String userId, String? number) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final canonical = normalizeParkrunAthleteNumber(number);
      if (canonical == null) {
        await prefs.remove(storageKey);
      } else {
        await prefs.setString(
          storageKey,
          jsonEncode({'user_id': userId, 'number': canonical}),
        );
      }
    } catch (e) {
      debugPrint('parkrun barcode cache write failed: $e');
    }
    changes.value++;
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (e) {
      debugPrint('parkrun barcode cache clear failed: $e');
    }
    changes.value++;
  }
}
