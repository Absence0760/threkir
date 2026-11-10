/// Grisnir, the Threkir goat, as the phone draws him. The images are renders
/// of his Blender model (apps/web/static/brand/grisnir/README.md); he never
/// appears in an error, sync, payment or lost-GPS state.
library;

import 'package:api_client/api_client.dart' show SettingsKeys;

import 'settings_sync.dart';

/// Standing 3/4, for a corner of a share card.
const kGrisnirBadgeAsset = 'assets/brand/grisnir/grisnir-badge-256.png';

/// Lying down with his legs folded under, for rest days.
const kGrisnirRestAsset = 'assets/brand/grisnir/grisnir-rest-384.png';

/// Whether the runner shows Grisnir: the universal `show_mascot`, on unless
/// it is literally `false`, as web reads it.
bool mascotShown() => activeSetting(SettingsKeys.showMascot) != false;
