import 'import_refusal.dart';
import 'l10n/gen/app_localizations.dart';
import 'loggable_message.dart';

/// What went wrong (or what a reader should know) about one part of a backup
/// restore.
///
/// A warning is data, not a sentence: the kind picks the localized copy, the
/// archive's own row id or position names the row, and a caught failure rides
/// in [error] for the log and for [importErrorText] to classify. It used to be
/// `'run $origId: $e'`, which put a PostgrestException's SQL detail and the
/// app's own English in front of the runner on the import screen in every
/// locale (decisions § 2320). `raw_error_copy_guard_test.dart` pins this
/// class's field set, so a free-text field cannot come back.
enum RestoreWarningKind {
  /// Restored without a session: runs are queued locally, profile skipped.
  offline,

  /// The archive's manifest said `complete: false`.
  archiveIncomplete,

  /// The profile row or the settings prefs failed to upsert.
  profile,

  /// A run row with no usable id was skipped.
  runNoId,

  /// A route row with no usable id was skipped.
  routeNoId,

  /// The offline path found the run already on the device and kept that copy.
  runPresent,

  /// The run's GPS track failed to upload.
  track,

  /// The run's heart-rate sidecar failed to upload.
  heartRate,

  /// The run row failed to save.
  run,

  /// The route row failed to save.
  route,

  /// The gym workouts failed to hydrate into the local store.
  gym,

  /// The food log failed to hydrate into the local store.
  food,

  /// The archive carried columns this build's schema has no home for.
  columnsDropped,

  /// No run store was supplied to the offline path.
  runsSkipped,
}

final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

class RestoreWarning {
  const RestoreWarning(
    this.kind, {
    this.itemId,
    this.index,
    this.columns = const [],
    this.error,
  });

  final RestoreWarningKind kind;

  /// The archive's id for the row, when it had one.
  final String? itemId;

  /// The row's zero-based position in its section of the archive.
  final int? index;

  /// The column names a [RestoreWarningKind.columnsDropped] warning names.
  final List<String> columns;

  /// The caught failure behind the warning. For the log and for
  /// [importErrorText] only, never rendered as text.
  final Object? error;

  /// The row as a reader can find it: the archive's id, else its 1-based
  /// position.
  String get itemLabel => itemId ?? '#${(index ?? 0) + 1}';

  /// The warning as the log records it: nothing the archive could have
  /// written. `debugPrint` output becomes a Sentry breadcrumb once the reader
  /// consents, and the archive is a file anyone can hand-edit, so its row ids
  /// and its JSON keys are free text a stranger chose. An id is kept only when
  /// it is shaped like one of our row ids, dropped columns are counted rather
  /// than named, and the caught failure goes through [loggableMessage].
  @override
  String toString() => [
        kind.name,
        if (itemId != null) _uuid.hasMatch(itemId!) ? itemId : '<invalid>',
        if (index != null) '#$index',
        if (columns.isNotEmpty) 'columns=${columns.length}',
        if (error != null) loggableMessage('$error'),
      ].join(' ');
}

/// The localized line for [w]. A caught failure reaches the sentence only
/// through [importErrorText], which ends in `friendlyError`.
String restoreWarningText(AppLocalizations l10n, RestoreWarning w) {
  final error = w.error;
  final reason =
      error == null ? l10n.authErrorGeneric : importErrorText(l10n, error);
  switch (w.kind) {
    case RestoreWarningKind.offline:
      return l10n.importRestoreWarnOffline;
    case RestoreWarningKind.archiveIncomplete:
      return l10n.importRestoreWarnArchiveIncomplete;
    case RestoreWarningKind.profile:
      return l10n.importRestoreWarnProfile(reason);
    case RestoreWarningKind.runNoId:
      return l10n.importRestoreWarnRunNoId((w.index ?? 0) + 1);
    case RestoreWarningKind.routeNoId:
      return l10n.importRestoreWarnRouteNoId((w.index ?? 0) + 1);
    case RestoreWarningKind.runPresent:
      return l10n.importRestoreWarnRunPresent(w.itemLabel);
    case RestoreWarningKind.track:
      return l10n.importRestoreWarnTrack(w.itemLabel, reason);
    case RestoreWarningKind.heartRate:
      return l10n.importRestoreWarnHeartRate(w.itemLabel, reason);
    case RestoreWarningKind.run:
      return l10n.importRestoreWarnRun(w.itemLabel, reason);
    case RestoreWarningKind.route:
      return l10n.importRestoreWarnRoute(w.itemLabel, reason);
    case RestoreWarningKind.gym:
      return l10n.importRestoreWarnGym(reason);
    case RestoreWarningKind.food:
      return l10n.importRestoreWarnFood(reason);
    case RestoreWarningKind.columnsDropped:
      return l10n.importRestoreWarnColumnsDropped(w.columns.join(', '));
    case RestoreWarningKind.runsSkipped:
      return l10n.importRestoreWarnRunsSkipped;
  }
}
