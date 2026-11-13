import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../provenance.dart';
import 'verified_badge.dart';

/// Where a piece of content came from (issue #1190, decisions § 2406): the
/// verified organiser, a data partner or provider sync, a trace from the
/// race's published map, or the community. The kind comes from the
/// `provenance` helper over server-derived fields; this only renders it.
///
/// Never colour alone: every kind carries its own icon and a visible word,
/// and a screen reader hears one sentence saying what the mark means. Official
/// reuses the verified-club rosette so a runner learns one mark. Twin of the
/// Svelte `ProvenanceBadge` component.
class ProvenanceBadge extends StatelessWidget {
  final Provenance provenance;
  final double size;

  /// An official park course route: the label names Threkir, never the park.
  final bool parkCourse;

  const ProvenanceBadge({
    super.key,
    required this.provenance,
    this.size = 14,
    this.parkCourse = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (label, description) = switch (provenance) {
      Provenance.official => parkCourse
          ? (
              l10n.officialBadgeParkCourseLabel,
              l10n.officialBadgeParkCourseTooltip
            )
          : (l10n.officialBadgeLabel, l10n.officialBadgeTooltip),
      Provenance.verifiedSource => (
          l10n.provenanceVerifiedSource,
          l10n.provenanceVerifiedSourceTooltip
        ),
      Provenance.traced => (l10n.provenanceTraced, l10n.provenanceTracedTooltip),
      Provenance.community => (
          l10n.provenanceCommunity,
          l10n.provenanceCommunityTooltip
        ),
    };
    final muted = theme.colorScheme.onSurfaceVariant;
    final icon = switch (provenance) {
      Provenance.official =>
        VerifiedBadge(size: size, tooltip: description),
      Provenance.verifiedSource =>
        Icon(Icons.storage_outlined, size: size, color: muted),
      Provenance.traced => Icon(Icons.map_outlined, size: size, color: muted),
      Provenance.community =>
        Icon(Icons.people_outline, size: size, color: muted),
    };
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 2),
        // Flexible so a long label wraps beside the glyph rather than
        // overflowing a narrow card at large text (issue #1374).
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: provenance == Provenance.official ? null : muted,
            ),
          ),
        ),
      ],
    );
    // The official rosette carries its own tooltip; the other kinds get one
    // here so every badge explains itself on a long press.
    return Semantics(
      key: Key('provenance-badge-${provenanceTokens[provenance]}'),
      label: description,
      excludeSemantics: true,
      child: provenance == Provenance.official
          ? row
          : Tooltip(message: description, child: row),
    );
  }
}
