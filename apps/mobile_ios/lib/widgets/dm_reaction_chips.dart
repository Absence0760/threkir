import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../dm_reactions.dart';
import '../l10n/gen/app_localizations.dart';

/// What a screen reader calls a reaction.
String dmReactionName(AppLocalizations l10n, String reaction) =>
    switch (reaction) {
      'thumbs_up' => l10n.messagesReactionThumbsUp,
      'heart' => l10n.messagesReactionHeart,
      'laugh' => l10n.messagesReactionLaugh,
      'surprised' => l10n.messagesReactionSurprised,
      'sad' => l10n.messagesReactionSad,
      'fire' => l10n.messagesReactionFire,
      _ => reaction,
    };

/// The reaction chips under one message: one per reaction anyone used, with
/// its count. Tapping a chip sets that reaction as the viewer's own, or
/// clears it when it already is. Mirrors web's `DmReactions.svelte`.
class DmReactionChips extends StatelessWidget {
  const DmReactionChips({
    super.key,
    required this.messageId,
    required this.rows,
    required this.viewerId,
    required this.canReact,
    required this.onSet,
  });

  final String messageId;
  final List<DmReactionRow> rows;
  final String? viewerId;
  final bool canReact;
  final void Function(String? reaction) onSet;

  @override
  Widget build(BuildContext context) {
    final chips = summarizeDmReactions(rows, messageId, viewerId);
    if (chips.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final c in chips)
            Semantics(
              button: true,
              selected: c.mine,
              enabled: canReact,
              label: l10n.messagesReactionChipLabel(
                dmReactionName(l10n, c.reaction),
                c.count,
              ),
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('dm-reaction-chip-${c.reaction}'),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: canReact
                    ? () => onSet(c.mine ? null : c.reaction)
                    : null,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: c.mine
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    border: Border.all(
                      color: c.mine ? scheme.primary : scheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(dmReactionGlyph(c.reaction)),
                      const SizedBox(width: 4),
                      Text(
                        '${c.count}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The six reactions to pick from, with the viewer's [current] one marked.
/// Answers the key picked, or null when dismissed.
Future<String?> showDmReactionPicker(BuildContext context, {String? current}) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('dm-reaction-picker'),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.messagesReactPickerLabel,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in kDmReactions)
                    Semantics(
                      button: true,
                      selected: current == r,
                      label: dmReactionName(l10n, r),
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('dm-reaction-option-$r'),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        onTap: () => Navigator.pop(ctx, r),
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: current == r
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: Text(
                            dmReactionGlyph(r),
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
