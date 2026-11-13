import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSpace, FieldColumn, ListCard;

import '../l10n/gen/app_localizations.dart';
import '../race_service.dart';
import '../undo_queue.dart';
import 'top_banner.dart';
import 'undo_bar.dart';

/// Organiser course alerts on a race or a route (issue #1190, decisions
/// § 2407): reroutes, closures, the course direction, notices. Anyone who can
/// see the course reads them; only an owner/admin of the verified club that
/// organises the race (or owns the route) is offered the form. The RPCs
/// re-check that, so this only decides what to show. Twin of web's
/// `CourseAlerts`.
class CourseAlertsSection extends StatefulWidget {
  final RaceService service;
  final String? listingId;
  final String? routeId;

  /// The club that may post: the race's organiser club or the route's owning
  /// club. Null hides the form.
  final String? clubId;

  const CourseAlertsSection({
    super.key,
    required this.service,
    this.listingId,
    this.routeId,
    this.clubId,
  }) : assert((listingId == null) != (routeId == null));

  @override
  State<CourseAlertsSection> createState() => _CourseAlertsSectionState();
}

IconData courseAlertIcon(String kind) => switch (kind) {
      'reroute' => Icons.alt_route,
      'closure' => Icons.block,
      'direction' => Icons.route,
      'notice' => Icons.info_outline,
      _ => Icons.info_outline,
    };

String courseAlertKindLabel(AppLocalizations l, String kind) => switch (kind) {
      'reroute' => l.courseAlertsKindReroute,
      'closure' => l.courseAlertsKindClosure,
      'direction' => l.courseAlertsKindDirection,
      'notice' => l.courseAlertsKindNotice,
      _ => l.courseAlertsKindNotice,
    };

class _CourseAlertsSectionState extends State<CourseAlertsSection> {
  static const _messageMax = 500;

  List<CourseAlertView> _alerts = const [];
  bool _loadFailed = false;
  bool _canPost = false;
  bool _busy = false;
  String _kind = 'notice';
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadAccess();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.service.isReady) return;
    try {
      final rows = await widget.service.fetchCourseAlerts(
        listingId: widget.listingId,
        routeId: widget.routeId,
      );
      if (mounted) setState(() {
        _alerts = rows;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('CourseAlertsSection: read failed: $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  // Auxiliary: a failed membership read hides the form, never the screen.
  Future<void> _loadAccess() async {
    final club = widget.clubId;
    if (club == null || !widget.service.isSignedIn) return;
    try {
      final mine = await widget.service.fetchMyOrganiserClubs();
      if (mounted) setState(() => _canPost = mine.any((c) => c.id == club));
    } catch (e) {
      debugPrint('CourseAlertsSection: club read failed: $e');
    }
  }

  Future<void> _post() async {
    final l = AppLocalizations.of(context);
    final text = _message.text.trim();
    if (text.isEmpty || text.length > _messageMax || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.postCourseAlert(
        listingId: widget.listingId,
        routeId: widget.routeId,
        kind: _kind,
        message: text,
      );
      _message.clear();
      if (!mounted) return;
      setState(() => _kind = 'notice');
      showTopBanner(context, l.courseAlertsPosted);
      await _load();
    } catch (e) {
      debugPrint('CourseAlertsSection: post failed: $e');
      if (mounted) showTopBanner(context, l.courseAlertsPostFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Removing an alert also withdraws the notices it sent, and posting it
  // again would notify everyone a second time, so the removal is held for
  // the undo window rather than run at once (conventions.md § Destructive
  // actions). Web's `remove`.
  void _remove(CourseAlertView alert) {
    final l = AppLocalizations.of(context);
    final service = widget.service;
    final before = _alerts;
    setState(() => _alerts = _alerts.where((a) => a.id != alert.id).toList());
    deferDestructive(
      context,
      DeferredDestruction(
        message: l.courseAlertsRemoved,
        commit: () => service.deleteCourseAlert(alert.id),
        restore: () {
          if (mounted) setState(() => _alerts = before);
        },
        onCommitError: (e) {
          debugPrint('CourseAlertsSection: remove failed: $e');
          if (mounted) showTopBanner(context, l.courseAlertsRemoveFailed);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_alerts.isEmpty && !_canPost && !_loadFailed) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      key: const Key('course-alerts'),
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(l.courseAlertsHeading, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          if (_loadFailed)
            Row(
              key: const Key('course-alerts-error'),
              children: [
                Expanded(child: Text(l.courseAlertsLoadFailed)),
                TextButton(onPressed: _load, child: Text(l.courseAlertsRetry)),
              ],
            ),
          if (_alerts.isEmpty && !_loadFailed)
            Text(
              l.courseAlertsEmpty,
              key: const Key('course-alerts-empty'),
              style: theme.textTheme.bodySmall,
            ),
          for (final a in _alerts)
            ListCard.row(
              key: Key('course-alert-${a.id}'),
              margin: const EdgeInsets.only(bottom: AppSpace.sm),
              dense: true,
              leading: Icon(courseAlertIcon(a.kind)),
              title: courseAlertKindLabel(l, a.kind),
              subtitle: a.createdAt.length >= 10
                  ? a.createdAt.substring(0, 10)
                  : a.createdAt,
              meta: Text(a.message),
              trailing: _canPost
                  ? IconButton(
                      key: Key('course-alert-remove-${a.id}'),
                      tooltip: l.courseAlertsRemoveLabel(
                          courseAlertKindLabel(l, a.kind)),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(a),
                    )
                  : null,
            ),
          if (_canPost) ...[
            const SizedBox(height: 8),
            FieldColumn(children: [
              DropdownButtonFormField<String>(
                key: const Key('course-alert-kind'),
                // Expanded, so a long kind label ellipsizes inside the field
                // rather than running past it at 320 dp and 2x.
                isExpanded: true,
                initialValue: _kind,
                decoration: InputDecoration(labelText: l.courseAlertsKindLabel),
                items: [
                  for (final k in kCourseAlertKinds)
                    DropdownMenuItem(
                      value: k,
                      child: Text(courseAlertKindLabel(l, k)),
                    ),
                ],
                onChanged: _busy ? null : (v) => setState(() => _kind = v ?? 'notice'),
              ),
              TextField(
                key: const Key('course-alert-message'),
                controller: _message,
                maxLength: _messageMax,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: l.courseAlertsMessageLabel),
                onChanged: (_) => setState(() {}),
              ),
            ]),
            Text(l.courseAlertsPostHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('course-alert-post'),
              onPressed: _busy || _message.text.trim().isEmpty ? null : _post,
              child: Text(l.courseAlertsPost),
            ),
          ],
        ],
      ),
    );
  }
}
