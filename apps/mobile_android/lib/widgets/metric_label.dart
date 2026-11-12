import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show StatTile;

import '../l10n/gen/app_localizations.dart';
import '../metrics.dart';

/// The derived-metric disclosure: a runner taps once and reads, in plain
/// words, what VO₂ max or TRIMP or 1RM actually is (#902 §1 + §2).
///
/// Sibling of `info_tip.dart`, which explains a FEATURE, and deliberately
/// built on the same idiom — an `(i)` opening an `AlertDialog` — because a
/// tooltip on touch needs a long-press nobody discovers. It differs in where
/// the copy comes from: `InfoTipButton` takes resolved strings, while this one
/// takes a [Metric] and resolves both name and definition from `metrics.dart`,
/// which is what lets `metric_label_guard_test.dart` police every render.

void showMetricDefinition(BuildContext context, Metric metric) {
  final l10n = AppLocalizations.of(context);
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(metricText(l10n, metric)),
      content: SingleChildScrollView(child: Text(metricDefinition(l10n, metric))),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(AppLocalizations.of(dialogContext).commonDismiss),
        ),
      ],
    ),
  );
}

/// The `(i)` alone, for a card header or beside a line of prose.
class MetricInfoButton extends StatelessWidget {
  final Metric metric;
  const MetricInfoButton({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      // The GLYPH shrinks to sit on a label line; the tap target does not
      // (`tap_target_guard_test.dart`).
      icon: const Icon(Icons.info_outline, size: 18),
      tooltip: l10n.metricAbout(metricText(l10n, metric)),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      padding: EdgeInsets.zero,
      onPressed: () => showMetricDefinition(context, metric),
    );
  }
}

/// A line of prose that names a metric, with the disclosure at its end.
class MetricSentence extends StatelessWidget {
  final Metric metric;
  final String sentence;
  final MetricArgs args;
  final TextStyle? style;

  const MetricSentence({
    super.key,
    required this.metric,
    required this.sentence,
    this.args = const {},
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            metricText(l10n, metric, sentence: sentence, args: args),
            style: style,
          ),
        ),
        MetricInfoButton(metric: metric),
      ],
    );
  }
}

/// A hero stat whose name carries its definition one tap away.
///
/// The tile is the tap target, not a button beside it: these sit three to a
/// row in a card, where a 48 dp control per cell would crowd out the number
/// it explains. The info glyph beside the label is the affordance (#25, #267).
class MetricStat extends StatelessWidget {
  final Metric metric;
  final String value;
  const MetricStat({super.key, required this.metric, required this.value});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: metricDefinition(l10n, metric),
      triggerMode: TooltipTriggerMode.longPress,
      child: InkWell(
        onTap: () => showMetricDefinition(context, metric),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: StatTile.large(
            label: metricText(l10n, metric),
            value: value,
            labelTrailing: Icon(Icons.info_outline,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
