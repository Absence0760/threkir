import '../lib/preferences.dart';

/// Puts [prefs] in the state of a runner who has already met RunScreen's
/// one-time Android pre-run dialog, so tapping START goes straight into the
/// countdown.
///
/// RunScreen gates that dialog on `defaultTargetPlatform`, and flutter_test
/// reports android there unless a test overrides it, so from empty prefs every
/// START in a widget test stops on the battery-optimisation hint. The
/// background-location nudge needs nothing here: it only shows while
/// "allow all the time" is denied, and these harnesses grant every permission.
/// A test that is ABOUT the dialogs skips this and starts from empty prefs.
Future<void> markPreRunDialogsSeen(Preferences prefs) =>
    prefs.setBatteryOptHintShown();
