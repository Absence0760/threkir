import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The disclosure EU AI Act Art. 50 asks for: every message the Coach wrote
/// carries it, not only the first (decisions § 2227). The visible "AI" is a
/// short tag; a screen reader hears the full phrase instead. Web twin:
/// `AiTag.svelte`.
class AiTag extends StatelessWidget {
  const AiTag({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      label: l10n.messagesAiTagSr,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('ai-tag'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          l10n.messagesAiTag,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// The Coach's avatar: its whistle glyph on a tinted disc. Decorative — the
/// name and [AiTag] beside it carry the meaning.
class CoachAvatar extends StatelessWidget {
  final double size;
  const CoachAvatar({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        child: Icon(Icons.sports, size: size * 0.55),
      ),
    );
  }
}
