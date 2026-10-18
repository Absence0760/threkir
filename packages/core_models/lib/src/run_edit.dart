import 'generated/db_rows.dart';
import 'metadata_keys.dart';
import 'run.dart';
import 'run_row_shape.dart';

/// The vocabulary a local edit to an already-synced run records its changed
/// fields in (decisions § 2120). A column is named by its `runs` column, a
/// bag key by `metadata.<key>`; a promoted bag key such as `is_dnf` is pushed
/// to its column by [runEditPatch].
abstract final class RunEditField {
  static const String durationS = RunRow.colDurationS;
  static const String distanceM = RunRow.colDistanceM;
  static const String routeId = RunRow.colRouteId;
  static const String metadataPrefix = 'metadata.';

  static String metadata(String key) => '$metadataPrefix$key';
}

/// Bag keys that never count as an edit: the read-side stashes of a column
/// (`track_url`, `hr_series_url`), the server base itself, and the retired
/// device clock, which no reader consults any more.
const Set<String> kRunEditIgnoredMetadataKeys = <String>{
  MetadataKeys.trackUrl,
  MetadataKeys.hrSeriesUrl,
  MetadataKeys.serverUpdatedAt,
  MetadataKeys.lastModifiedAt,
};

/// The server `updated_at` a copy of a run was read at, exactly as the server
/// sent it, or null for a copy that never carried one (read before § 2120, or
/// never pulled). Kept as the server's string because the push filters on it
/// for equality: a re-formatted `DateTime` can lose precision a `timestamptz`
/// keeps, and would then never match.
String? serverUpdatedAtOf(Run run) {
  final v = run.metadata?[MetadataKeys.serverUpdatedAt];
  return v is String && v.isNotEmpty ? v : null;
}

/// The fields [after] changes relative to [before], in [RunEditField] terms.
Set<String> changedRunFields(Run before, Run after) {
  final out = <String>{};
  if (before.duration.inSeconds != after.duration.inSeconds) {
    out.add(RunEditField.durationS);
  }
  if (before.distanceMetres != after.distanceMetres) {
    out.add(RunEditField.distanceM);
  }
  if (before.routeId != after.routeId) out.add(RunEditField.routeId);
  final a = before.metadata ?? const <String, dynamic>{};
  final b = after.metadata ?? const <String, dynamic>{};
  for (final key in <String>{...a.keys, ...b.keys}) {
    if (kRunEditIgnoredMetadataKeys.contains(key)) continue;
    if (a.containsKey(key) != b.containsKey(key) ||
        !_jsonEquals(a[key], b[key])) {
      out.add(RunEditField.metadata(key));
    }
  }
  return out;
}

/// [server] with [local]'s values for [fields] laid on top: the server's
/// changes to every other field are kept, and on a field both changed the
/// local edit wins, because it is the one arriving at the server later. A bag
/// key [local] no longer has is removed. [local]'s track is kept when
/// [server] carries none, since a pulled row never does.
Run applyRunEditFields({
  required Run local,
  required Run server,
  required Set<String> fields,
}) {
  var duration = server.duration;
  var distance = server.distanceMetres;
  var routeId = server.routeId;
  final meta = Map<String, dynamic>.from(server.metadata ?? const {});
  final localMeta = local.metadata ?? const <String, dynamic>{};
  for (final field in fields) {
    if (field == RunEditField.durationS) {
      duration = local.duration;
    } else if (field == RunEditField.distanceM) {
      distance = local.distanceMetres;
    } else if (field == RunEditField.routeId) {
      routeId = local.routeId;
    } else if (field.startsWith(RunEditField.metadataPrefix)) {
      final key = field.substring(RunEditField.metadataPrefix.length);
      if (kRunEditIgnoredMetadataKeys.contains(key)) continue;
      if (localMeta.containsKey(key)) {
        meta[key] = localMeta[key];
      } else {
        meta.remove(key);
      }
    }
  }
  return Run(
    id: server.id,
    startedAt: server.startedAt,
    duration: duration,
    distanceMetres: distance,
    track: server.track.isEmpty ? local.track : server.track,
    routeId: routeId,
    source: server.source,
    externalId: server.externalId,
    metadata: meta.isEmpty ? null : meta,
    createdAt: server.createdAt ?? local.createdAt,
  );
}

/// The `runs` UPDATE body for [fields] of [run]: only the columns those fields
/// live in. Any bag key sends the whole persisted bag, which is safe because
/// the push is a compare-and-swap on the base the bag was rebased onto; a
/// promoted or mirrored key also sends its column.
Map<String, dynamic> runEditPatch(
  Run run,
  Set<String> fields, {
  required String userId,
}) {
  final row = runRowFromRun(run, userId: userId).toJson();
  final patch = <String, dynamic>{};
  for (final field in fields) {
    if (field == RunEditField.durationS ||
        field == RunEditField.distanceM ||
        field == RunEditField.routeId) {
      patch[field] = row[field];
    } else if (field.startsWith(RunEditField.metadataPrefix)) {
      final key = field.substring(RunEditField.metadataPrefix.length);
      if (kRunEditIgnoredMetadataKeys.contains(key)) continue;
      patch[RunRow.colMetadata] = row[RunRow.colMetadata];
      final column =
          kRunPromotedMetadataColumns[key] ?? kRunMirroredMetadataColumns[key];
      if (column != null) patch[column] = row[column];
    }
  }
  return patch;
}

/// A local edit to a synced run that has not reached the server yet: which
/// fields it changed, and the server `updated_at` of the copy it was made on.
/// Every edit installs a new instance, so identity tells a push whether the
/// edit it sent is still the one pending.
class PendingRunEdit {
  PendingRunEdit({required Set<String> fields, required this.baseUpdatedAt})
    : fields = Set.unmodifiable(fields);

  final Set<String> fields;

  /// Null when the edited copy carried no server stamp; the push then reads
  /// the row first and re-bases onto it.
  final String? baseUpdatedAt;

  Map<String, dynamic> toJson() => {
    'fields': (fields.toList()..sort()),
    'base_updated_at': baseUpdatedAt,
  };

  /// Null for anything that is not a usable edit, so a malformed entry reads
  /// as no pending edit rather than failing the store's load.
  static PendingRunEdit? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawFields = json['fields'];
    if (rawFields is! List) return null;
    final fields = <String>{
      for (final f in rawFields)
        if (f is String && f.isNotEmpty) f,
    };
    if (fields.isEmpty) return null;
    final base = json['base_updated_at'];
    return PendingRunEdit(
      fields: fields,
      baseUpdatedAt: base is String && base.isNotEmpty ? base : null,
    );
  }
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
