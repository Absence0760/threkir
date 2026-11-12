import 'l10n/gen/app_localizations.dart';

/// Localized name for a stored `routes.surface` token. An unrecognised value
/// is returned VERBATIM: the CHECK constraint means a stray token can only
/// appear when this client is older than the database, and a prettified guess
/// (or a silent "Road") is indistinguishable from a real translation. Mirrors
/// web's `routeSurfaceLabel`.
String routeSurfaceLabel(AppLocalizations l10n, String surface) =>
    switch (surface) {
      'road' => l10n.routesSurfaceRoad,
      'trail' => l10n.routesSurfaceTrail,
      'mixed' => l10n.routesSurfaceMixed,
      _ => surface,
    };
