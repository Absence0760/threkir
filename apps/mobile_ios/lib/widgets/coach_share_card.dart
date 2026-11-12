import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../coach_share.dart';
import '../l10n/gen/app_localizations.dart';
import '../screens/coach_screen.dart';
import '../training_service.dart';
import 'ai_tag.dart';

/// AI text another user wrote, drawn as plain text spans from typed blocks
/// (`parseSharedMarkdown`), never through a markdown widget, so nothing in it
/// becomes a link, an image or markup (decisions § 110). Web twin:
/// `SharedText.svelte`.
class SharedText extends StatelessWidget {
  const SharedText({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final muted = base.copyWith(color: base.color?.withValues(alpha: 0.7));
    final blocks = parseSharedMarkdown(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == blocks.length - 1 ? 0 : 6),
            child: _block(blocks[i], base, muted, theme),
          ),
      ],
    );
  }

  Widget _block(
    SharedBlock b,
    TextStyle base,
    TextStyle muted,
    ThemeData theme,
  ) {
    final spans = Text.rich(
      TextSpan(
        style: b.type == SharedBlockType.heading
            ? base.copyWith(fontWeight: FontWeight.w700)
            : base,
        children: [for (final s in b.spans) _span(s, theme)],
      ),
    );
    if (b.type != SharedBlockType.bullet && b.type != SharedBlockType.ordered) {
      return spans;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b.type == SharedBlockType.bullet)
          ExcludeSemantics(child: Text('•', style: muted))
        else
          Text(b.marker ?? '', style: muted),
        const SizedBox(width: 6),
        Expanded(child: spans),
      ],
    );
  }

  InlineSpan _span(SharedSpan s, ThemeData theme) => switch (s.style) {
    SharedSpanStyle.bold => TextSpan(
      text: s.text,
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    SharedSpanStyle.italic => TextSpan(
      text: s.text,
      style: const TextStyle(fontStyle: FontStyle.italic),
    ),
    SharedSpanStyle.code => TextSpan(
      text: s.text,
      style: TextStyle(
        fontFamily: 'monospace',
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
      ),
    ),
    SharedSpanStyle.plain => TextSpan(text: s.text),
  };
}

/// An AI Coach answer the athlete shared with their coach (issue #1215
/// Phase 3): a quote labelled as AI output on both sides (EU AI Act Art. 50,
/// decisions § 2227), drawn as text. Web twin: `CoachShareCard.svelte`.
///
/// [coachMessageId] is the sender's own Coach answer, readable only by the
/// sender, so the link back is offered to the sender alone. It resolves the
/// answer's plan when tapped and opens the Coach on it; a failed lookup opens
/// the Coach on its default plan rather than nowhere.
class CoachShareCard extends StatelessWidget {
  const CoachShareCard({
    super.key,
    required this.api,
    required this.body,
    required this.mine,
    required this.coachMessageId,
    required this.partnerName,
    this.onOpenSource,
  });

  final ApiClient api;
  final String body;
  final bool mine;
  final String? coachMessageId;
  final String partnerName;

  /// Opens the Coach on the resolved plan. Defaults to pushing [CoachScreen].
  final void Function(BuildContext context, String? planId)? onOpenSource;

  Future<void> _openSource(BuildContext context) async {
    String? planId;
    try {
      planId = await api.fetchCoachMessagePlanId(coachMessageId!);
    } catch (e) {
      debugPrint('coach_share_card: source lookup failed: $e');
    }
    if (!context.mounted) return;
    final open = onOpenSource;
    if (open != null) {
      open(context, planId);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoachScreen(
          api: api,
          training: TrainingService(),
          initialPlanId: planId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final secondary = theme.textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      key: const ValueKey('dm-coach-share'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CoachAvatar(size: 22),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  l10n.coachShareCardLabel,
                  style: secondary?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              const AiTag(),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            mine
                ? l10n.coachShareCardFromMe
                : l10n.coachShareCardFromAthlete(partnerName),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
            decoration: BoxDecoration(
              color: cs.secondaryContainer.withValues(alpha: 0.35),
              border: Border(left: BorderSide(color: cs.secondary, width: 3)),
            ),
            child: SharedText(
              text: body,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
          if (mine && coachMessageId != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('dm-coach-share-source'),
                onPressed: () => _openSource(context),
                child: Text(l10n.coachShareOpenSource),
              ),
            ),
        ],
      ),
    );
  }
}
