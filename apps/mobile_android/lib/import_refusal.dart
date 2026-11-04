import 'auth_error.dart';
import 'l10n/gen/app_localizations.dart';

/// Why an importer refused a whole file. Each one tells the runner something
/// different to do, so each gets its own copy rather than the generic retry.
enum ImportRefusalKind {
  tooLarge,
  notStravaExport,
  stravaColumnsMissing,
  notBackup,
  backupTooNew,
}

/// A whole-file refusal from the Strava, CSV or backup importer.
///
/// It is a [FormatException] so callers that only ask "was the file wrong?"
/// keep working, and its [message] stays the English sentence the log has
/// always carried. What the runner reads comes from [importErrorText].
class ImportRefused extends FormatException {
  const ImportRefused(this.kind, String message, {this.sizeMb, this.limitMb})
      : super(message);

  final ImportRefusalKind kind;
  final int? sizeMb;
  final int? limitMb;
}

/// The detail an import screen puts after "Import failed:". A refusal names
/// itself, any other [FormatException] is a file the importer could not
/// read, and everything else reads as [friendlyError].
String importErrorText(AppLocalizations l10n, Object error) {
  if (error is ImportRefused) {
    switch (error.kind) {
      case ImportRefusalKind.tooLarge:
        return l10n.importRefusedTooLarge(
            error.sizeMb ?? 0, error.limitMb ?? 0);
      case ImportRefusalKind.notStravaExport:
        return l10n.importRefusedNotStravaExport;
      case ImportRefusalKind.stravaColumnsMissing:
        return l10n.importRefusedColumnsMissing;
      case ImportRefusalKind.notBackup:
        return l10n.importRefusedNotBackup;
      case ImportRefusalKind.backupTooNew:
        return l10n.importRefusedBackupTooNew;
    }
  }
  if (error is FormatException) return l10n.importFileUnreadable;
  return friendlyError(l10n, error);
}
