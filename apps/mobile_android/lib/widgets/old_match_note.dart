import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

/// The board note for a catalogue segment timed by its start and end lines
/// while some of its efforts were still measured by the circles (issue
/// #1308). Mirrors web `OldMatchNote.svelte`. Auxiliary: a failed read hides
/// the note and never touches the board beside it.
class OldMatchNote extends StatefulWidget {
  final ApiClient? api;
  final GlobalSegmentRow segment;

  const OldMatchNote({super.key, required this.api, required this.segment});

  @override
  State<OldMatchNote> createState() => _OldMatchNoteState();
}

class _OldMatchNoteState extends State<OldMatchNote> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OldMatchNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segment.id != widget.segment.id) {
      _show = false;
      _load();
    }
  }

  Future<void> _load() async {
    final api = widget.api;
    final segment = widget.segment;
    if (api == null ||
        segment.startGateSource == null ||
        segment.endGateSource == null) {
      return;
    }
    try {
      final has = await api.globalSegmentHasZoneEfforts(segment.id);
      if (!mounted || widget.segment.id != segment.id) return;
      setState(() => _show = has);
    } catch (e) {
      debugPrint('old match note read failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              AppLocalizations.of(context).segmentOldMatchNote,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
