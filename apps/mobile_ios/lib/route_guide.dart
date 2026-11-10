/// A park course's route guide (issue #1344, decisions § 2448): the reader of
/// `park_courses.route_guide` and the renderer from its structured steps to
/// the lines a person follows. Steps are data, so every locale reads the
/// guide through its own templates; trail names stay as OpenStreetMap has
/// them, and `getting_there` is free text in the guide's own `lang`.
///
/// Parity pair with `apps/web/src/lib/parks/route_guide.ts`
/// (docs/architecture/parity_pairs.md). Both read the case table in
/// `fixtures/route_guide_cases.json`, so which template a step takes, and with
/// which values, changes there or nowhere. The vocabularies mirror the CHECK
/// `private.park_course_route_guide_ok` (migration 20271212001344) and the
/// generator `scripts/parks/lib/route_guide.mjs`.
library;

import 'l10n/gen/app_localizations.dart';

const List<String> kGuideTurns = ['left', 'right', 'straight'];
const List<String> kGuideWays = ['fire_road', 'road', 'path'];
const List<String> kGuideRotations = ['clockwise', 'counterclockwise'];
const List<String> kGuideSides = ['left', 'right'];
const List<String> kGuideSurfaces = [
  'paved',
  'gravel',
  'dirt',
  'unpaved',
  'boardwalk',
];
const List<String> kGuideCrossings = ['bridge', 'ford'];

/// One step of a guide. [kind] decides which of the other fields are set:
/// `start` and `junction` carry exactly one of [name] / [way].
class RouteGuideStep {
  final String kind;
  final int atM;
  final String? name;
  final String? way;
  final String? turn;
  final String? rotation;
  final String? keepOn;
  final String? landmark;
  final String? crossing;
  final String? surface;
  final int? gainM;
  final int? lengthM;
  final int? lap;
  final int? order;
  final int? of;

  const RouteGuideStep({
    required this.kind,
    required this.atM,
    this.name,
    this.way,
    this.turn,
    this.rotation,
    this.keepOn,
    this.landmark,
    this.crossing,
    this.surface,
    this.gainM,
    this.lengthM,
    this.lap,
    this.order,
    this.of,
  });
}

class RouteGuide {
  final String lang;
  final String? gettingThere;
  final List<RouteGuideStep> steps;
  const RouteGuide({
    required this.lang,
    required this.gettingThere,
    required this.steps,
  });
}

const int _maxSteps = 200;
const int _maxLabel = 120;
const int _maxGettingThere = 500;

// JSON has one number type, so `400.0` is whole on web; Dart decodes it as a
// double and must accept it the same way.
int? _whole(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

String? _label(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isNotEmpty && t.length <= _maxLabel ? t : null;
}

String? _oneOf(List<String> list, Object? v) =>
    v is String && list.contains(v) ? v : null;

({String? name, String? way})? _readTarget(Map<String, dynamic> s) {
  final hasName = s.containsKey('name');
  final hasWay = s.containsKey('way');
  if (hasName == hasWay) return null;
  if (hasName) {
    final name = _label(s['name']);
    return name == null ? null : (name: name, way: null);
  }
  final way = _oneOf(kGuideWays, s['way']);
  return way == null ? null : (name: null, way: way);
}

RouteGuideStep? _readStep(Object? raw) {
  if (raw is! Map) return null;
  final s = Map<String, dynamic>.from(raw);
  final atM = _whole(s['at_m']);
  if (atM == null || atM < 0) return null;
  switch (s['kind']) {
    case 'start':
      final target = _readTarget(s);
      return target != null && atM == 0
          ? RouteGuideStep(
              kind: 'start', atM: atM, name: target.name, way: target.way)
          : null;
    case 'direction':
      final rotation = _oneOf(kGuideRotations, s['rotation']);
      if (rotation == null) return null;
      if (s.containsKey('keep_on') != s.containsKey('landmark')) return null;
      if (!s.containsKey('keep_on')) {
        return RouteGuideStep(kind: 'direction', atM: atM, rotation: rotation);
      }
      final keepOn = _oneOf(kGuideSides, s['keep_on']);
      final landmark = _label(s['landmark']);
      if (keepOn == null || landmark == null) return null;
      return RouteGuideStep(
        kind: 'direction',
        atM: atM,
        rotation: rotation,
        keepOn: keepOn,
        landmark: landmark,
      );
    case 'lap':
      final lap = _whole(s['lap']);
      final of = _whole(s['of']);
      return lap != null && of != null && lap >= 2 && lap <= of
          ? RouteGuideStep(kind: 'lap', atM: atM, lap: lap, of: of)
          : null;
    case 'junction':
      final target = _readTarget(s);
      final turn = _oneOf(kGuideTurns, s['turn']);
      return target != null && turn != null
          ? RouteGuideStep(
              kind: 'junction',
              atM: atM,
              turn: turn,
              name: target.name,
              way: target.way,
            )
          : null;
    case 'crossing':
      final crossing = _oneOf(kGuideCrossings, s['crossing']);
      return crossing == null
          ? null
          : RouteGuideStep(kind: 'crossing', atM: atM, crossing: crossing);
    case 'surface':
      final surface = _oneOf(kGuideSurfaces, s['surface']);
      return surface == null
          ? null
          : RouteGuideStep(kind: 'surface', atM: atM, surface: surface);
    case 'climb':
      final gain = _whole(s['gain_m']);
      final length = _whole(s['length_m']);
      return gain != null && length != null && gain >= 1 && length >= 1
          ? RouteGuideStep(
              kind: 'climb', atM: atM, gainM: gain, lengthM: length)
          : null;
    case 'checkpoint':
      final order = _whole(s['order']);
      final of = _whole(s['of']);
      return order != null && of != null && order >= 1 && order <= of
          ? RouteGuideStep(kind: 'checkpoint', atM: atM, order: order, of: of)
          : null;
    case 'finish':
      return RouteGuideStep(kind: 'finish', atM: atM);
    default:
      return null;
  }
}

/// Reads `park_courses.route_guide`. Null — never a guide with a step left
/// out — when anything in it cannot be read: a guide missing one turn sends a
/// runner the wrong way, so the section is hidden instead.
RouteGuide? parseRouteGuide(Object? raw) {
  if (raw is! Map) return null;
  final g = Map<String, dynamic>.from(raw);
  final lang = g['lang'];
  final rawSteps = g['steps'];
  if (g['version'] != 1 || lang is! String || rawSteps is! List) return null;
  if (rawSteps.length < 2 || rawSteps.length > _maxSteps) return null;
  String? gettingThere;
  final rawThere = g['getting_there'];
  if (rawThere != null) {
    if (rawThere is! String) return null;
    final text = rawThere.trim();
    if (text.isEmpty || text.length > _maxGettingThere) return null;
    gettingThere = text;
  }
  final steps = <RouteGuideStep>[];
  var prev = 0;
  for (final raw in rawSteps) {
    final step = _readStep(raw);
    if (step == null || step.atM < prev) return null;
    prev = step.atM;
    steps.add(step);
  }
  if (steps.first.kind != 'start' || steps.last.kind != 'finish') return null;
  return RouteGuide(lang: lang, gettingThere: gettingThere, steps: steps);
}

/// Every template a guide line takes. Each is a full sentence per locale, so
/// word order and gender stay right.
const List<String> kGuideLineKeys = [
  'startNamed',
  'startFireRoad',
  'startRoad',
  'startPath',
  'clockwise',
  'counterclockwise',
  'keepLeft',
  'keepRight',
  'passCheckpoints',
  'leftNamed',
  'rightNamed',
  'straightNamed',
  'leftFireRoad',
  'rightFireRoad',
  'straightFireRoad',
  'leftRoad',
  'rightRoad',
  'straightRoad',
  'leftPath',
  'rightPath',
  'straightPath',
  'bridge',
  'ford',
  'surfacePaved',
  'surfaceGravel',
  'surfaceDirt',
  'surfaceUnpaved',
  'surfaceBoardwalk',
  'climb',
  'checkpoint',
  'lap',
  'finish',
];

/// One line before formatting: its template and raw values. Distances are
/// metres ([at], [length], [gain]); the caller formats them in the reader's
/// unit and locale.
class GuideLine {
  final String key;
  final int? at;
  final String? name;
  final String? landmark;
  final int? gain;
  final int? length;
  final int? n;
  final int? total;
  const GuideLine(
    this.key, {
    this.at,
    this.name,
    this.landmark,
    this.gain,
    this.length,
    this.n,
    this.total,
  });

  /// The set fields under the web's names, for the shared case table.
  Map<String, Object> toJson() => {
        'key': key,
        'at': ?at,
        'name': ?name,
        'landmark': ?landmark,
        'gain': ?gain,
        'length': ?length,
        'n': ?n,
        'total': ?total,
      };
}

const Map<String, String> _waySuffix = {
  'fire_road': 'FireRoad',
  'road': 'Road',
  'path': 'Path',
};
const Map<String, String> _surfaceKey = {
  'paved': 'surfacePaved',
  'gravel': 'surfaceGravel',
  'dirt': 'surfaceDirt',
  'unpaved': 'surfaceUnpaved',
  'boardwalk': 'surfaceBoardwalk',
};

/// The lines a guide reads as, in order. The start, the direction and (when
/// the course has checkpoints) the stay-on-course note come first; every
/// other step follows at its distance.
List<GuideLine> routeGuideLines(RouteGuide guide) {
  final lines = <GuideLine>[];
  final rest = <GuideLine>[];
  var hasCheckpoint = false;
  for (final s in guide.steps) {
    switch (s.kind) {
      case 'start':
        lines.add(s.name != null
            ? GuideLine('startNamed', name: s.name)
            : GuideLine('start${_waySuffix[s.way]}'));
      case 'direction':
        lines.add(GuideLine(s.rotation!));
        if (s.keepOn != null && s.landmark != null) {
          lines.add(GuideLine(s.keepOn == 'left' ? 'keepLeft' : 'keepRight',
              landmark: s.landmark));
        }
      case 'junction':
        rest.add(s.name != null
            ? GuideLine('${s.turn}Named', at: s.atM, name: s.name)
            : GuideLine('${s.turn}${_waySuffix[s.way]}', at: s.atM));
      case 'crossing':
        rest.add(GuideLine(s.crossing!, at: s.atM));
      case 'surface':
        rest.add(GuideLine(_surfaceKey[s.surface]!, at: s.atM));
      case 'climb':
        rest.add(GuideLine('climb',
            at: s.atM, gain: s.gainM, length: s.lengthM));
      case 'checkpoint':
        hasCheckpoint = true;
        rest.add(GuideLine('checkpoint', at: s.atM, n: s.order, total: s.of));
      case 'lap':
        rest.add(GuideLine('lap', at: s.atM, n: s.lap, total: s.of));
      case 'finish':
        rest.add(GuideLine('finish', at: s.atM));
    }
  }
  if (hasCheckpoint) lines.add(const GuideLine('passCheckpoints'));
  return [...lines, ...rest];
}

class GuideFormat {
  /// The template for a key, with `{at}`, `{name}`, `{landmark}`, `{gain}`,
  /// `{length}`, `{n}`, `{total}` filled.
  final String Function(String key, Map<String, Object> params) message;

  /// A distance along the course, e.g. `1.8 km`.
  final String Function(double metres) distance;

  /// A short length or a height, e.g. `19 m` / `62 ft`.
  final String Function(double metres) short;

  const GuideFormat({
    required this.message,
    required this.distance,
    required this.short,
  });
}

/// A line as text.
String formatGuideLine(GuideLine line, GuideFormat fmt) {
  final params = <String, Object>{
    if (line.at != null) 'at': fmt.distance(line.at!.toDouble()),
    'name': ?line.name,
    'landmark': ?line.landmark,
    if (line.gain != null) 'gain': fmt.short(line.gain!.toDouble()),
    if (line.length != null) 'length': fmt.short(line.length!.toDouble()),
    'n': ?line.n,
    'total': ?line.total,
  };
  return fmt.message(line.key, params);
}

/// The guide as plain text, one line each, for a GPX `<desc>`.
List<String> routeGuideText(RouteGuide guide, GuideFormat fmt) =>
    [for (final l in routeGuideLines(guide)) formatGuideLine(l, fmt)];

/// The English templates, for the one place that writes canonical English
/// whoever asks: a GPX file's `<desc>` (the file is the same whoever opens
/// it). `route_guide_test.dart` holds every entry to `parkGuide<Key>` in
/// `app_en.arb`, so the two cannot drift.
const Map<String, String> guideEn = {
  'pending': 'Drafted from map data, not yet checked on the ground.',
  'checked': 'Checked on the ground on {date}.',
  'startNamed': 'Start on {name}.',
  'startFireRoad': 'Start on the fire road.',
  'startRoad': 'Start on the park road.',
  'startPath': 'Start on the path.',
  'clockwise': 'Run the loop clockwise.',
  'counterclockwise': 'Run the loop counterclockwise.',
  'keepLeft': 'Keep {landmark} on your left.',
  'keepRight': 'Keep {landmark} on your right.',
  'passCheckpoints': 'Pass every checkpoint in order, or the run is not timed.',
  'leftNamed': '{at}: turn left onto {name}.',
  'rightNamed': '{at}: turn right onto {name}.',
  'straightNamed': '{at}: continue straight onto {name}.',
  'leftFireRoad': '{at}: turn left onto the fire road.',
  'rightFireRoad': '{at}: turn right onto the fire road.',
  'straightFireRoad': '{at}: continue straight along the fire road.',
  'leftRoad': '{at}: turn left onto the park road.',
  'rightRoad': '{at}: turn right onto the park road.',
  'straightRoad': '{at}: continue straight along the park road.',
  'leftPath': '{at}: turn left onto the path.',
  'rightPath': '{at}: turn right onto the path.',
  'straightPath': '{at}: continue straight along the path.',
  'bridge': '{at}: cross the bridge.',
  'ford': '{at}: cross the ford. There is no bridge, so expect water.',
  'surfacePaved': '{at}: paved from here.',
  'surfaceGravel': '{at}: gravel from here.',
  'surfaceDirt': '{at}: dirt trail from here.',
  'surfaceUnpaved': '{at}: unpaved from here.',
  'surfaceBoardwalk': '{at}: boardwalk from here.',
  'climb': '{at}: a climb of {gain} over {length}.',
  'checkpoint': '{at}: checkpoint {n} of {total}.',
  'lap': '{at}: start lap {n} of {total} and repeat the loop.',
  'finish': '{at}: finish.',
};

final RegExp _placeholder = RegExp(r'\{(\w+)\}');

String _fill(String template, Map<String, Object> params) => template
    .replaceAllMapped(_placeholder, (m) => '${params[m.group(1)] ?? ''}');

/// Canonical-English formatting: kilometres to one decimal, metres whole.
final GuideFormat englishGuideFormat = GuideFormat(
  message: (key, params) => _fill(guideEn[key]!, params),
  distance: (metres) => '${(metres / 1000).toStringAsFixed(1)} km',
  short: (metres) => '${metres.round()} m',
);

/// The guide as canonical-English text: whether it has been checked on the
/// ground, the getting-there note, then every line. [checkedAt] is
/// `park_courses.route_guide_checked_at` (YYYY-MM-DD) or null.
List<String> routeGuideEnglish(RouteGuide guide, String? checkedAt) {
  final status = checkedAt != null && checkedAt.isNotEmpty
      ? _fill(guideEn['checked']!, {'date': checkedAt})
      : guideEn['pending']!;
  return [
    status,
    ?guide.gettingThere,
    ...routeGuideText(guide, englishGuideFormat),
  ];
}

/// The reader's-locale template for a line key, filled from [params] as
/// [formatGuideLine] builds them.
String guideLineMessage(
  AppLocalizations l10n,
  String key,
  Map<String, Object> params,
) {
  String s(String p) => '${params[p] ?? ''}';
  int i(String p) => (params[p] as int?) ?? 0;
  return switch (key) {
    'startNamed' => l10n.parkGuideStartNamed(s('name')),
    'startFireRoad' => l10n.parkGuideStartFireRoad,
    'startRoad' => l10n.parkGuideStartRoad,
    'startPath' => l10n.parkGuideStartPath,
    'clockwise' => l10n.parkGuideClockwise,
    'counterclockwise' => l10n.parkGuideCounterclockwise,
    'keepLeft' => l10n.parkGuideKeepLeft(s('landmark')),
    'keepRight' => l10n.parkGuideKeepRight(s('landmark')),
    'passCheckpoints' => l10n.parkGuidePassCheckpoints,
    'leftNamed' => l10n.parkGuideLeftNamed(s('at'), s('name')),
    'rightNamed' => l10n.parkGuideRightNamed(s('at'), s('name')),
    'straightNamed' => l10n.parkGuideStraightNamed(s('at'), s('name')),
    'leftFireRoad' => l10n.parkGuideLeftFireRoad(s('at')),
    'rightFireRoad' => l10n.parkGuideRightFireRoad(s('at')),
    'straightFireRoad' => l10n.parkGuideStraightFireRoad(s('at')),
    'leftRoad' => l10n.parkGuideLeftRoad(s('at')),
    'rightRoad' => l10n.parkGuideRightRoad(s('at')),
    'straightRoad' => l10n.parkGuideStraightRoad(s('at')),
    'leftPath' => l10n.parkGuideLeftPath(s('at')),
    'rightPath' => l10n.parkGuideRightPath(s('at')),
    'straightPath' => l10n.parkGuideStraightPath(s('at')),
    'bridge' => l10n.parkGuideBridge(s('at')),
    'ford' => l10n.parkGuideFord(s('at')),
    'surfacePaved' => l10n.parkGuideSurfacePaved(s('at')),
    'surfaceGravel' => l10n.parkGuideSurfaceGravel(s('at')),
    'surfaceDirt' => l10n.parkGuideSurfaceDirt(s('at')),
    'surfaceUnpaved' => l10n.parkGuideSurfaceUnpaved(s('at')),
    'surfaceBoardwalk' => l10n.parkGuideSurfaceBoardwalk(s('at')),
    'climb' => l10n.parkGuideClimb(s('at'), s('gain'), s('length')),
    'checkpoint' => l10n.parkGuideCheckpoint(s('at'), i('n'), i('total')),
    'lap' => l10n.parkGuideLap(s('at'), i('n'), i('total')),
    'finish' => l10n.parkGuideFinish(s('at')),
    _ => '',
  };
}
