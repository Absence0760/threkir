import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';

import '../coach_share.dart';
import '../dm_send_error.dart';
import '../l10n/gen/app_localizations.dart';
import 'coach_share_card.dart' show SharedText;

/// Share with coach (issue #1215 Phase 3): the athlete picks which paragraphs
/// of one Coach answer go to which of their coaches. The server copies the
/// text by index, so what is offered here is the same split
/// (`coachAnswerParagraphs`). Mirror of web `CoachShareDialog.svelte`.
///
/// Resolves to the coach whose conversation the athlete asked to open, or
/// null when the sheet was closed any other way.
Future<CoachAthleteLink?> showCoachShareSheet(
  BuildContext context, {
  required ApiClient api,
  required String messageId,
  required String content,
  required List<CoachAthleteLink> coaches,
}) {
  return showModalBottomSheet<CoachAthleteLink>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => CoachShareSheet(
      api: api,
      messageId: messageId,
      content: content,
      coaches: coaches,
    ),
  );
}

/// The sentence the athlete reads when a share did not go: the gate being
/// closed has its own; everything else reads as a refused or failed send.
String coachShareErrorMessage(AppLocalizations l10n, Object error) {
  if (error is CoachShareUnavailable) return l10n.coachShareUnavailable;
  return dmSendErrorMessage(l10n, error);
}

class CoachShareSheet extends StatefulWidget {
  const CoachShareSheet({
    super.key,
    required this.api,
    required this.messageId,
    required this.content,
    required this.coaches,
  });

  final ApiClient api;
  final String messageId;
  final String content;
  final List<CoachAthleteLink> coaches;

  @override
  State<CoachShareSheet> createState() => _CoachShareSheetState();
}

class _CoachShareSheetState extends State<CoachShareSheet> {
  late final List<String> _paragraphs = coachAnswerParagraphs(widget.content);
  late final Set<int> _picked = {
    for (var i = 0; i < _paragraphs.length; i++) i,
  };
  late String? _coachId = widget.coaches.isEmpty
      ? null
      : widget.coaches.first.userId;
  bool _sending = false;
  String? _sendError;
  CoachAthleteLink? _sentTo;

  String _nameOf(AppLocalizations l10n, CoachAthleteLink c) =>
      c.displayName ?? l10n.profileRunnerFallback;

  bool get _tooLong =>
      coachShareExcerpt(_paragraphs, _picked).length > kCoachShareMaxChars;

  Future<void> _send() async {
    final coach = widget.coaches.where((c) => c.userId == _coachId).firstOrNull;
    if (coach == null || _picked.isEmpty || _tooLong || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await widget.api.shareCoachMessage(
        widget.messageId,
        coach.userId,
        (_picked.toList()..sort()),
      );
      if (!mounted) return;
      setState(() {
        _sentTo = coach;
        _sending = false;
      });
    } catch (e) {
      debugPrint('coach_share_sheet: share failed: $e');
      if (!mounted) return;
      setState(() {
        _sendError = coachShareErrorMessage(AppLocalizations.of(context), e);
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sentTo = _sentTo;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.coachShareTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (sentTo != null)
              ..._sentView(l10n, theme, sentTo)
            else
              ..._pickView(l10n, theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _sentView(
    AppLocalizations l10n,
    ThemeData theme,
    CoachAthleteLink sentTo,
  ) {
    return [
      Text(
        l10n.coachShareSent(_nameOf(l10n, sentTo)),
        key: const ValueKey('coach-share-sent'),
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: 16),
      OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 8,
        overflowAlignment: OverflowBarAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.coachShareDone),
          ),
          FilledButton(
            key: const ValueKey('coach-share-open-thread'),
            onPressed: () => Navigator.of(context).pop(sentTo),
            child: Text(l10n.coachShareOpenThread),
          ),
        ],
      ),
    ];
  }

  List<Widget> _pickView(AppLocalizations l10n, ThemeData theme) {
    final cs = theme.colorScheme;
    final legend = theme.textTheme.titleSmall;
    final tooLong = _tooLong;
    final canSend =
        !_sending && _picked.isNotEmpty && !tooLong && _coachId != null;
    return [
      Text(l10n.coachShareIntro),
      const SizedBox(height: 12),
      if (widget.coaches.length > 1) ...[
        Text(l10n.coachShareCoachLegend, style: legend),
        RadioGroup<String>(
          groupValue: _coachId,
          onChanged: (v) => setState(() => _coachId = v ?? _coachId),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in widget.coaches)
                RadioListTile<String>(
                  key: ValueKey('coach-share-coach-${c.userId}'),
                  value: c.userId,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_nameOf(l10n, c)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ] else if (widget.coaches.isNotEmpty) ...[
        Text(l10n.coachShareTo(_nameOf(l10n, widget.coaches.first))),
        const SizedBox(height: 12),
      ],
      Text(l10n.coachShareParagraphsLegend, style: legend),
      const SizedBox(height: 4),
      for (var i = 0; i < _paragraphs.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            shape: RoundedRectangleBorder(
              side: BorderSide(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: CheckboxListTile(
              key: ValueKey('coach-share-paragraph-$i'),
              value: _picked.contains(i),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _picked.add(i);
                } else {
                  _picked.remove(i);
                }
              }),
              title: SharedText(text: _paragraphs[i]),
            ),
          ),
        ),
      if (tooLong)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.coachShareTooLong(kCoachShareMaxChars),
            key: const ValueKey('coach-share-too-long'),
            style: TextStyle(color: cs.error),
          ),
        ),
      if (_sendError != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(
            liveRegion: true,
            child: Text(
              _sendError!,
              key: const ValueKey('coach-share-error'),
              style: TextStyle(color: cs.error),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Text(
        l10n.coachShareLabelNote,
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 12),
      OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 8,
        overflowAlignment: OverflowBarAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('coach-share-send'),
            onPressed: canSend ? _send : null,
            child: Text(
              _sending ? l10n.coachShareSending : l10n.coachShareSend,
            ),
          ),
        ],
      ),
    ];
  }
}
