import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart'
    show
        kLocalStoreSchemaVersion,
        kLocalStoreVersionKey,
        localStoreRecordVersion,
        serialiseStoreWrite,
        sweepStoreScratchFiles,
        writeStringAtomic;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'gym_prs.dart' show namesAnExercise;

/// One half-typed set row of a gym-composer draft.
///
/// Every field is the RAW string the athlete typed, not a parsed number: what
/// has to survive a process death is what is on screen, including a value
/// mid-edit ("12.", "-", "") that no parser would accept yet. Parsing on the
/// way out and re-rendering on the way back in would quietly rewrite the
/// user's own text.
class GymComposeDraftSet {
  const GymComposeDraftSet({
    this.reps = '',
    this.weight = '',
    this.rpe = '',
    this.duration = '',
    this.setType = 'working',
  });

  final String reps;
  final String weight;
  final String rpe;
  final String duration;
  final String setType;

  bool get isEmpty =>
      reps.trim().isEmpty &&
      weight.trim().isEmpty &&
      rpe.trim().isEmpty &&
      duration.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'reps': reps,
        'weight': weight,
        'rpe': rpe,
        'duration': duration,
        'set_type': setType,
      };

  static GymComposeDraftSet fromJson(Map<String, dynamic> json) =>
      GymComposeDraftSet(
        reps: _str(json['reps']),
        weight: _str(json['weight']),
        rpe: _str(json['rpe']),
        duration: _str(json['duration']),
        setType: _str(json['set_type'], fallback: 'working'),
      );
}

/// One exercise block of a draft: the typed name plus its set rows.
class GymComposeDraftExercise {
  const GymComposeDraftExercise({this.name = '', this.sets = const []});

  final String name;
  final List<GymComposeDraftSet> sets;

  /// Blankness on the folded KEY, never on the spelling: `trim()` happens to
  /// strip exactly the folded class on this runtime, and the web twin's does
  /// not (decisions § 1367).
  bool get isEmpty => !namesAnExercise(name) && sets.every((s) => s.isEmpty);

  Map<String, dynamic> toJson() => {
        'name': name,
        'sets': [for (final s in sets) s.toJson()],
      };

  static GymComposeDraftExercise fromJson(Map<String, dynamic> json) =>
      GymComposeDraftExercise(
        name: _str(json['name']),
        sets: [
          for (final s in (json['sets'] as List?) ?? const [])
            if (s is Map)
              GymComposeDraftSet.fromJson(Map<String, dynamic>.from(s)),
        ],
      );
}

/// A snapshot of the gym composer's whole in-progress form.
class GymComposeDraft {
  const GymComposeDraft({
    required this.title,
    required this.isPublic,
    required this.exercises,
    required this.savedAt,
  });

  final String title;
  final bool isPublic;
  final List<GymComposeDraftExercise> exercises;
  final DateTime savedAt;

  /// Whether this draft is worth offering back. A composer that only ever held
  /// its blank starter block is not half-built work, and offering to restore
  /// nothing is worse than offering nothing.
  bool get hasContent =>
      title.trim().isNotEmpty || exercises.any((e) => !e.isEmpty);

  Map<String, dynamic> toJson() => {
        kLocalStoreVersionKey: kLocalStoreSchemaVersion,
        'title': title,
        'is_public': isPublic,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'exercises': [for (final e in exercises) e.toJson()],
      };

  static GymComposeDraft? fromJson(Map<String, dynamic> json) {
    if (localStoreRecordVersion(json) > kLocalStoreSchemaVersion) {
      debugPrint('gym_compose_draft: record is newer than this build; '
          'reading known fields only');
    }
    final saved = DateTime.tryParse(_str(json['saved_at']));
    if (saved == null) return null;
    return GymComposeDraft(
      title: _str(json['title']),
      isPublic: json['is_public'] == true,
      savedAt: saved.toUtc(),
      exercises: [
        for (final e in (json['exercises'] as List?) ?? const [])
          if (e is Map)
            GymComposeDraftExercise.fromJson(Map<String, dynamic>.from(e)),
      ],
    );
  }
}

String _str(Object? v, {String fallback = ''}) => v is String ? v : fallback;

/// The single in-flight gym-composer draft, on disk.
///
/// **Why this is not a `gym_workouts` row.** The guided session runner keeps
/// its draft in `LocalGymStore` under a `gym_session_draft` metadata marker,
/// and that is right for it: a runner's draft already holds sets the athlete
/// genuinely performed, so it is a real workout that happens to be unfinished.
/// A composer draft is not — it is half-typed form state, including exercise
/// blocks with no name yet and numbers that do not parse. Persisting it as a
/// workout row would sync a phantom session to the server, put it in the
/// user's gym history and every cross-modal timeline, and STILL lose the
/// unnamed blocks, because `_buildSets` drops them. So the composer keeps its
/// own non-syncing sidecar in the shape the sibling stores use: one directory
/// under app documents, a `_v`-stamped record, and a crash-atomic write.
///
/// One draft, not a queue: the composer is a single pushed route, so there is
/// never more than one in flight.
class GymComposeDraftStore {
  GymComposeDraftStore();

  /// The app-wide instance the composer uses when a host supplies none.
  static final GymComposeDraftStore shared = GymComposeDraftStore();

  static const _subdir = 'gym_compose_draft';
  static const _filename = 'draft.json';

  Directory? _dir;
  Future<void>? _initOnce;

  File get _file => File('${_dir!.path}/$_filename');

  /// Resolve the draft directory. Idempotent and safe to call concurrently —
  /// every entry point awaits the same future.
  ///
  /// Best-effort by design: this is an L4 auxiliary store, so a
  /// `path_provider` failure (no platform channel under a plain unit test, a
  /// locked-down device) leaves it inert rather than breaking the composer it
  /// exists to protect.
  Future<void> init({Directory? overrideDirectory}) {
    if (overrideDirectory != null) {
      _dir = overrideDirectory;
      if (!_dir!.existsSync()) _dir!.createSync(recursive: true);
      sweepStoreScratchFiles(_dir!,
          onError: (m) => debugPrint('gym_compose_draft: $m'));
      return _initOnce = Future.value();
    }
    return _initOnce ??= () async {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final d = Directory('${appDir.path}/$_subdir');
        if (!d.existsSync()) d.createSync(recursive: true);
        sweepStoreScratchFiles(d,
            onError: (m) => debugPrint('gym_compose_draft: $m'));
        _dir = d;
      } catch (e) {
        debugPrint('gym_compose_draft: init failed: $e');
      }
    }();
  }

  /// The stored draft, or null when there is none or it cannot be read.
  ///
  /// A record that cannot be parsed answers null AND is cleared: it can never
  /// be restored, so leaving it makes every later open pay the same failed
  /// read and keeps offering a card that does nothing.
  Future<GymComposeDraft?> read() async {
    await init();
    if (_dir == null) return null;
    try {
      final f = _file;
      if (!f.existsSync()) return null;
      final json = jsonDecode(await f.readAsString());
      if (json is! Map) {
        await clear();
        return null;
      }
      final draft = GymComposeDraft.fromJson(Map<String, dynamic>.from(json));
      if (draft == null) await clear();
      return draft;
    } catch (e) {
      debugPrint('gym_compose_draft: read failed: $e');
      await clear();
      return null;
    }
  }

  /// Replace the stored draft. Serialised on the directory so the periodic
  /// save and a [clear] at teardown cannot interleave over one file.
  Future<void> write(GymComposeDraft draft) async {
    await init();
    final d = _dir;
    if (d == null) return;
    await serialiseStoreWrite(d.path, () async {
      try {
        await writeStringAtomic(_file, jsonEncode(draft.toJson()));
      } catch (e) {
        debugPrint('gym_compose_draft: write failed: $e');
      }
    });
  }

  Future<void> clear() async {
    await init();
    final d = _dir;
    if (d == null) return;
    await serialiseStoreWrite(d.path, () async {
      try {
        final f = _file;
        if (f.existsSync()) await f.delete();
      } catch (e) {
        debugPrint('gym_compose_draft: clear failed: $e');
      }
    });
  }
}
