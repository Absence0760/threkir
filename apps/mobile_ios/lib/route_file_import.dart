import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'auth_error.dart';
import 'l10n/gen/app_localizations.dart';
import 'local_route_store.dart';
import 'shared_file_import.dart'
    show
        kRouteImportPickerExtensions,
        routeTextFromImportedBytes,
        routesFromImportedFile;
import 'widgets/top_banner.dart';

/// Lets the user pick a GPX / KML / KMZ / GeoJSON file, parses it off the UI
/// thread, saves every usable route to [routeStore], and says what happened
/// in a banner. Returns the routes it saved — empty on a cancel or a failure —
/// so a caller like the add-run form can select the one it just got.
Future<List<cm.Route>> pickAndImportRouteFile(
  BuildContext context,
  LocalRouteStore routeStore,
) async {
  try {
    // Inside the try: the picker throws a PlatformException when the OS
    // refuses it (no document provider, one already open), and outside it
    // that reached the zone as an unhandled error with nothing shown.
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kRouteImportPickerExtensions,
    );
    if (result == null || result.files.isEmpty) return const [];
    // path can be null when the picker hands back a content URI it
    // couldn't resolve to a real file (Drive / OneDrive document
    // providers do this). readAsBytes may also throw on permission
    // errors or if the user revokes access mid-read — both stay
    // inside the try so the banner handles them, not an uncaught
    // unhandled-async-error crash.
    final path = result.files.first.path;
    if (path == null) {
      if (context.mounted) {
        showTopBanner(
            context, AppLocalizations.of(context).routesImportFailedLocalOnly);
      }
      return const [];
    }
    final ext = result.files.first.extension?.toLowerCase();
    // BYTES, not text: a KMZ is a zip and `readAsString` throws on one
    // before any dispatch is reached (decisions § 1025).
    final bytes = await File(path).readAsBytes();
    final routes =
        await compute(_parseRouteFile, _RouteParseRequest(ext, bytes));
    // A route needs two points to have a line, a distance, or a map. Saving
    // a degenerate one and reporting success is how a silently-dropped
    // track became "Route imported!".
    final usable =
        routes.where((r) => r.waypoints.length >= 2).toList(growable: false);
    if (usable.isEmpty) {
      if (context.mounted) {
        showTopBanner(context, AppLocalizations.of(context).routesImportNoTrack);
      }
      return const [];
    }
    for (final route in usable) {
      await routeStore.save(route);
    }
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      showTopBanner(
          context,
          usable.length == 1
              ? l10n.routesImported(usable.first.name)
              : l10n.routesImportedMany(usable.length));
    }
    return usable;
  } catch (e) {
    debugPrint('routes import failed: $e');
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      showTopBanner(context, l10n.routesImportFailed(friendlyError(l10n, e)));
    }
    return const [];
  }
}

class _RouteParseRequest {
  final String? ext;
  final Uint8List bytes;
  const _RouteParseRequest(this.ext, this.bytes);
}

List<cm.Route> _parseRouteFile(_RouteParseRequest req) {
  // Resolved rather than inferred from the extension alone: this path used to
  // read `ext == 'kml' ? 'kml' : 'gpx'`, a third dispatch that could name only
  // two of the four formats and parsed everything else as GPX. The KMZ unwrap
  // runs here too, in the isolate, for the same reason the parse does.
  final decoded =
      routeTextFromImportedBytes(extension: req.ext, bytes: req.bytes);
  if (decoded == null) return const <cm.Route>[];
  return routesFromImportedFile(
      format: decoded.format, content: decoded.content);
}
