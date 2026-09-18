import 'package:flutter/widgets.dart';

import 'l10n/gen/app_localizations.dart';

/// The one registry of derived-metric names and their plain-English
/// definitions on mobile (#902 §1 + §2) — the Dart half of web's
/// `lib/metrics/metric_registry.ts`, carrying the same sentences so the two
/// platforms say the same thing about the same number.
///
/// Every registered name reaches a runner through the disclosure widgets in
/// `widgets/metric_label.dart`, and `test/metric_label_guard_test.dart` reads
/// THIS object — not a second list — to fail the suite when a registered
/// catalogue key is resolved anywhere else, when a term is typed straight into
/// a Dart string, or when English copy carries a term with nothing explaining
/// it.
///
/// A Flutter `Tooltip` is not a disclosure: it opens on a long-press nobody
/// discovers, and the acronym stays a wall for the runner who needed it most.
enum Metric {
  vo2max,
  vdot,
  ctl,
  atl,
  tsb,
  ageGrade,
  vert,
  trimp,
  riegel,
  e1rm,
  rpe,
}

/// Pre-formatted values a catalogue string interpolates, keyed by placeholder.
typedef MetricArgs = Map<String, String>;

/// A catalogue entry named twice: [name] for the guard to hunt for in source,
/// [resolve] for the widget to render.
///
/// The pair is the whole point — a registry that held only a resolver could
/// not be scanned, and one that held only a key could not be rendered. The
/// guard's `registry keys and resolvers agree` test reads this file's own
/// source and fails when the two halves of an entry name different getters.
@immutable
class L10nKey {
  final String name;
  final String Function(AppLocalizations l10n, MetricArgs args) resolve;
  const L10nKey(this.name, this.resolve);
}

@immutable
class MetricEntry {
  /// The metric's own name. Titles its disclosure, and is what a surface
  /// renders when it asks for no variant.
  final L10nKey label;

  /// One plain line saying what the number means.
  final L10nKey definition;

  /// Other spellings of the name a surface needs — "{value} vert", "Target
  /// RPE" — keyed by the short name a call site passes as `variant`.
  final Map<String, L10nKey> variants;

  /// Prose that names the metric mid-sentence. Rendered by `MetricSentence`,
  /// which sets the disclosure at the end of the line rather than splitting
  /// the sentence: Flutter has no inline anchor a screen reader reads in
  /// order, and every catalogue would need re-translating around a marker.
  final Map<String, L10nKey> sentences;

  /// How the jargon is spelled in English. Case-sensitive on purpose: `rpe`
  /// is a field name, `RPE` is a word a runner reads.
  final RegExp? term;

  /// English catalogue keys allowed to carry the term, each with the reason a
  /// reader still gets the meaning there. Three shapes qualify: the same string
  /// spells the term out; the string is a picker or dropdown row that cannot
  /// hold a disclosure, whose metric is disclosed on the surface it belongs to;
  /// or the string is already the BODY of a disclosure. The guard fails once an
  /// exempted key stops carrying the term, so a reason cannot outlive its
  /// cause.
  final Map<String, String> allowedIn;

  const MetricEntry({
    required this.label,
    required this.definition,
    this.variants = const {},
    this.sentences = const {},
    this.term,
    this.allowedIn = const {},
  });
}

final Map<Metric, MetricEntry> kMetrics = {
  Metric.vo2max: MetricEntry(
    label: L10nKey('fitnessStatVo2Max', (l, a) => l.fitnessStatVo2Max),
    definition:
        L10nKey('fitnessStatVo2MaxTooltip', (l, a) => l.fitnessStatVo2MaxTooltip),
    term: RegExp(r'VO₂\s?max|VO2\s?max'),
    allowedIn: const {
      'watchMetricVo2Max':
          'a row in the watch-screen metric picker, which names the field the '
              'watch itself draws and cannot hold a disclosure',
    },
  ),
  Metric.vdot: MetricEntry(
    label: L10nKey('fitnessStatVdot', (l, a) => l.fitnessStatVdot),
    definition:
        L10nKey('fitnessStatVdotTooltip', (l, a) => l.fitnessStatVdotTooltip),
    variants: {
      'value': L10nKey('metricVdotValue', (l, a) => l.metricVdotValue(a['value']!)),
      'daniels': L10nKey('planNewVdot', (l, a) => l.planNewVdot(a['value']!)),
    },
    term: RegExp(r'\bVDOT\b'),
  ),
  Metric.ctl: MetricEntry(
    label: L10nKey('fitnessStatCtl', (l, a) => l.fitnessStatCtl),
    definition: L10nKey('fitnessStatCtlTooltip', (l, a) => l.fitnessStatCtlTooltip),
    term: RegExp(r'\bCTL\b'),
  ),
  Metric.atl: MetricEntry(
    label: L10nKey('fitnessStatAtl', (l, a) => l.fitnessStatAtl),
    definition: L10nKey('fitnessStatAtlTooltip', (l, a) => l.fitnessStatAtlTooltip),
    term: RegExp(r'\bATL\b'),
  ),
  Metric.tsb: MetricEntry(
    label: L10nKey('fitnessStatTsb', (l, a) => l.fitnessStatTsb),
    definition: L10nKey('fitnessStatTsbTooltip', (l, a) => l.fitnessStatTsbTooltip),
    term: RegExp(r'\bTSB\b'),
  ),
  Metric.ageGrade: MetricEntry(
    label: L10nKey('runDetailStatAgeGrade', (l, a) => l.runDetailStatAgeGrade),
    definition: L10nKey(
        'metricAgeGradeDefinition', (l, a) => l.metricAgeGradeDefinition),
    variants: {
      'pb': L10nKey(
          'dashboardPbAgeGrade', (l, a) => l.dashboardPbAgeGrade(a['percent']!)),
    },
    term: RegExp(r'\b[Aa]ge grade\b'),
    allowedIn: const {
      'integrationsParkrunInfo':
          'the parkrun tile\'s own explanation, already behind a disclosure of '
              'its own, naming what the import brings back',
    },
  ),
  Metric.vert: MetricEntry(
    label: L10nKey('metricVertLabel', (l, a) => l.metricVertLabel),
    definition: L10nKey('metricVertDefinition', (l, a) => l.metricVertDefinition),
    variants: {
      'total': L10nKey('dashboardVert', (l, a) => l.dashboardVert(a['value']!)),
    },
    sentences: {
      'roadbook': L10nKey(
          'roadbookSummary',
          (l, a) =>
              l.roadbookSummary(a['distance']!, a['vert']!, a['time']!)),
    },
    // Not the `{vert}` placeholder in a composite line, and not a field name.
    term: RegExp(r'\bVert\b|(?<![{\x27"\w])vert(?![}\x27"\w])'),
  ),
  Metric.trimp: MetricEntry(
    label: L10nKey('metricTrimpLabel', (l, a) => l.metricTrimpLabel),
    definition:
        L10nKey('metricTrimpDefinition', (l, a) => l.metricTrimpDefinition),
    sentences: {
      'hr': L10nKey('trainingLoadSubtitleHr',
          (l, a) => l.trainingLoadSubtitleHr(int.parse(a['days']!))),
      'volume': L10nKey(
          'trainingLoadSubtitleVolume', (l, a) => l.trainingLoadSubtitleVolume),
    },
    term: RegExp(r'\bTRIMP\b'),
  ),
  Metric.riegel: MetricEntry(
    label: L10nKey('metricRiegelLabel', (l, a) => l.metricRiegelLabel),
    definition:
        L10nKey('metricRiegelDefinition', (l, a) => l.metricRiegelDefinition),
    sentences: {
      'predictor':
          L10nKey('racePredictorFootnote', (l, a) => l.racePredictorFootnote),
      'plan': L10nKey('planNewRecent5kHelp', (l, a) => l.planNewRecent5kHelp),
    },
    term: RegExp(r'\bRiegel\b'),
  ),
  Metric.e1rm: MetricEntry(
    label: L10nKey('metricE1rmLabel', (l, a) => l.metricE1rmLabel),
    definition: L10nKey('metricE1rmDefinition', (l, a) => l.metricE1rmDefinition),
    variants: {
      'best': L10nKey('gymPrE1rm', (l, a) => l.gymPrE1rm),
      'percent': L10nKey('gymRoutineProgressionPercentLabel',
          (l, a) => l.gymRoutineProgressionPercentLabel),
      'oneRm': L10nKey('gymRoutineProgressionOneRmLabel',
          (l, a) => l.gymRoutineProgressionOneRmLabel(a['unit']!)),
    },
    term: RegExp(r'\b1RM\b'),
    allowedIn: const {
      'gymRoutineProgressionPercentCycle':
          'a dropdown row naming a progression scheme, which cannot hold a '
              'disclosure; the scheme\'s own fields carry one',
    },
  ),
  Metric.rpe: MetricEntry(
    label: L10nKey('gymRpe', (l, a) => l.gymRpe),
    definition: L10nKey('metricRpeDefinition', (l, a) => l.metricRpeDefinition),
    variants: {
      'target': L10nKey('gymRoutineProgressionTargetRpeLabel',
          (l, a) => l.gymRoutineProgressionTargetRpeLabel),
    },
    term: RegExp(r'\bRPE\b'),
    allowedIn: const {
      'gymRoutineProgressionRpeAutoreg':
          'a dropdown row naming a progression scheme, which cannot hold a '
              'disclosure; the scheme\'s own fields carry one',
    },
  ),
};

/// Every catalogue key the registry owns for one metric's name.
List<L10nKey> metricNameKeys(MetricEntry entry) =>
    [entry.label, ...entry.variants.values];

/// A registered metric's name as plain text, for the places a disclosure
/// cannot go — a `TextField`'s `labelText`, a chip, a dense tappable card.
///
/// The guard allows this only for a metric that is disclosed somewhere in the
/// tree, so the definition stays one surface away rather than nowhere.
String metricText(AppLocalizations l10n, Metric metric,
    {String? variant, String? sentence, MetricArgs args = const {}}) {
  final entry = kMetrics[metric]!;
  final key = sentence != null
      ? entry.sentences[sentence]!
      : variant != null
          ? entry.variants[variant]!
          : entry.label;
  return key.resolve(l10n, args);
}

String metricDefinition(AppLocalizations l10n, Metric metric) =>
    kMetrics[metric]!.definition.resolve(l10n, const {});
