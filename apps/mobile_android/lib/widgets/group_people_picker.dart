import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' show UserProfileRow;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show IdentityAvatar;

import '../dm_recipients.dart';
import '../l10n/gen/app_localizations.dart';

/// Picks people to invite to a group (issue #1365 slice 3). The list is the
/// viewer's follow graph in both directions, the people they could message
/// 1:1 without a request (D1); a shared club or event also admits an invite,
/// and the server decides every one with a single refusal (dm_recipients.dart
/// explains why a block is never drawn here). Mirrors web
/// `GroupPeoplePicker.svelte`.
///
/// It lays out as a column, not a scrollable, so the screen or sheet that
/// holds it owns the scrolling.
class GroupPeoplePicker extends StatefulWidget {
  const GroupPeoplePicker({
    super.key,
    required this.api,
    required this.selected,
    required this.onChanged,
    required this.max,
    this.exclude = const {},
    this.disabled = false,
  });

  final ApiClient api;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  /// Seats left; further people cannot be ticked once it is reached.
  final int max;

  /// People already in the group or holding an invite.
  final Set<String> exclude;
  final bool disabled;

  @override
  State<GroupPeoplePicker> createState() => _GroupPeoplePickerState();
}

class _GroupPeoplePickerState extends State<GroupPeoplePicker> {
  bool _loading = true;
  bool _loadFailed = false;
  List<DmRecipient> _candidates = const [];
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final me = widget.api.userId;
    if (me == null) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final pages = await Future.wait([
        widget.api.fetchFollowers(me, limit: 500),
        widget.api.fetchFollowing(me, limit: 500),
      ]);
      DmCandidateProfile candidate(UserProfileRow p) => DmCandidateProfile(
            id: p.id,
            displayName: p.displayName,
            avatarUrl: p.avatarUrl,
          );
      final candidates = dmRecipientCandidates(
        pages[0].rows.map(candidate),
        pages[1].rows.map(candidate),
        selfId: me,
      );
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _loading = false;
      });
    } catch (e) {
      // "Nobody to invite" and "couldn't find out who" are different answers.
      debugPrint('group people picker load failed: ${safeErrorLabel(e)}');
      if (!mounted) return;
      setState(() {
        _candidates = const [];
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  void _toggle(String id, bool on) {
    final selected = widget.selected;
    if (on) {
      if (!selected.contains(id) && selected.length < widget.max) {
        widget.onChanged([...selected, id]);
      }
    } else {
      widget.onChanged([
        for (final s in selected)
          if (s != id) s,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: CircularProgressIndicator(semanticsLabel: l10n.commonLoading),
        ),
      );
    }
    if (_loadFailed) {
      return Row(
        key: const ValueKey('group-people-error'),
        children: [
          Expanded(child: Text(l10n.groupsPeopleLoadFailed, style: muted)),
          TextButton(onPressed: _load, child: Text(l10n.errorStateRetry)),
        ],
      );
    }
    final available = [
      for (final c in _candidates)
        if (!widget.exclude.contains(c.id)) c,
    ];
    if (available.isEmpty) {
      return Padding(
        key: const ValueKey('group-people-empty'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(l10n.groupsPeopleEmpty, style: muted),
      );
    }
    final shown = filterDmRecipients(available, _query.text);
    final full = widget.selected.length >= widget.max;
    return Column(
      key: const ValueKey('group-people-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('group-people-search'),
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: l10n.groupsPeopleSearch,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(
              l10n.groupsPeopleSelected(widget.selected.length, widget.max),
              key: const ValueKey('group-people-count'),
              style: muted,
            ),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l10n.groupsPeopleNoMatches, style: muted),
          )
        else
          for (final r in shown)
            CheckboxListTile(
              key: ValueKey('group-person-${r.id}'),
              contentPadding: EdgeInsets.zero,
              value: widget.selected.contains(r.id),
              onChanged: widget.disabled ||
                      (!widget.selected.contains(r.id) && full)
                  ? null
                  : (on) => _toggle(r.id, on ?? false),
              secondary: IdentityAvatar(
                seed: r.id,
                name: r.displayName,
                imageUrl: r.avatarUrl,
                size: 36,
              ),
              title: Text(
                r.displayName ?? l10n.profileRunnerFallback,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        if (full)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.groupsPeopleFull(widget.max),
              key: const ValueKey('group-people-full'),
              style: muted,
            ),
          ),
      ],
    );
  }
}
