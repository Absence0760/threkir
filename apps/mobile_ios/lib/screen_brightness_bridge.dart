import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Raises the screen to full brightness while a barcode is up and hands it
/// back afterwards, over `run_app/screen_brightness` (Android
/// `ScreenBrightnessBridge.kt`, iOS `AppDelegate.swift`). Android overrides
/// only this window, so it reverts by itself when the window goes; iOS sets
/// the device brightness, so the caller restores it whenever the app leaves
/// the foreground.
///
/// An auxiliary effect: a failure here never stops the barcode from showing.
class ScreenBrightnessBridge {
  const ScreenBrightnessBridge();

  static const _channel = MethodChannel('run_app/screen_brightness');

  Future<void> setMax() => _invoke('setMax');

  Future<void> restore() => _invoke('restore');

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (e) {
      debugPrint('screen brightness $method failed: $e');
    }
  }
}
