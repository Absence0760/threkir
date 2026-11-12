import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../l10n/gen/app_localizations.dart';
import '../park_course_report.dart';
import 'top_banner.dart';

/// "Report a problem with this course" (issue #1346, decisions § 2449): the
/// mobile twin of web's ParkCourseReportDialog. The runner picks a reason,
/// writes a note and may leave an email for a reply; the
/// `park-course-report` Edge Function files it. A report never closes the
/// course: an admin reviews it on the web (decisions § 24).
Future<void> showParkCourseReportSheet(
  BuildContext context, {
  required ApiClient api,
  required String courseId,
  required String courseName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => ParkCourseReportSheet(
      api: api,
      courseId: courseId,
      courseName: courseName,
      onSent: () {
        Navigator.of(ctx).pop();
        showTopBanner(context, AppLocalizations.of(context).parkCourseReportSent);
      },
    ),
  );
}

String courseReportReasonLabel(AppLocalizations l10n, String reason) {
  switch (reason) {
    case 'course_hazard':
      return l10n.parkCourseReportReasonHazard;
    case 'course_closure':
      return l10n.parkCourseReportReasonClosure;
    case 'course_off_trail':
      return l10n.parkCourseReportReasonOffTrail;
    case 'land_manager_request':
      return l10n.parkCourseReportReasonLandManager;
    case 'rights_holder_request':
      return l10n.parkCourseReportReasonRightsHolder;
    case 'other':
      return l10n.parkCourseReportReasonOther;
    default:
      return l10n.parkCourseReportReasonOther;
  }
}

String _refusalCopy(AppLocalizations l10n, CourseReportRefusal refusal) {
  switch (refusal) {
    case CourseReportRefusal.rateLimited:
      return l10n.parkCourseReportErrorRateLimited;
    case CourseReportRefusal.alreadyReported:
      return l10n.parkCourseReportErrorAlreadyReported;
    case CourseReportRefusal.notFound:
      return l10n.parkCourseReportErrorNotFound;
    case CourseReportRefusal.invalidEmail:
      return l10n.parkCourseReportErrorEmail;
    case CourseReportRefusal.emailRequired:
      return l10n.parkCourseReportErrorEmailRequired;
    case CourseReportRefusal.invalid:
      return l10n.parkCourseReportErrorInvalid;
    case CourseReportRefusal.failed:
      return l10n.parkCourseReportErrorFailed;
  }
}

class ParkCourseReportSheet extends StatefulWidget {
  final ApiClient api;
  final String courseId;
  final String courseName;
  final VoidCallback onSent;

  const ParkCourseReportSheet({
    super.key,
    required this.api,
    required this.courseId,
    required this.courseName,
    required this.onSent,
  });

  @override
  State<ParkCourseReportSheet> createState() => _ParkCourseReportSheetState();
}

class _ParkCourseReportSheetState extends State<ParkCourseReportSheet> {
  String _reason = kCourseReportReasons.first;
  final _notesCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _emailRequired => courseReportEmailRequired(_reason);
  bool get _emailOk => courseReportEmailOk(_emailCtl.text, reason: _reason);
  // An empty required field is not yet a mistake: the helper says what it is
  // for until something is typed, and Send stays disabled meanwhile.
  bool get _emailShapeOk => courseReportEmailOk(_emailCtl.text);
  bool get _canSubmit =>
      !_busy && _notesCtl.text.trim().isNotEmpty && _emailOk;

  @override
  void dispose() {
    _notesCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.submitParkCourseReport(
        courseId: widget.courseId,
        reason: _reason,
        notes: _notesCtl.text,
        contactEmail: _emailCtl.text,
      );
      if (!mounted) return;
      widget.onSent();
    } on FunctionException catch (e) {
      debugPrint('park course report refused: ${e.status}');
      if (!mounted) return;
      setState(() => _error = _refusalCopy(
            AppLocalizations.of(context),
            courseReportRefusal(e.details),
          ));
    } catch (e) {
      debugPrint('park course report failed: $e');
      if (!mounted) return;
      setState(() =>
          _error = AppLocalizations.of(context).parkCourseReportErrorFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    return SingleChildScrollView(
      key: const Key('park-course-report-sheet'),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + insets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.parkCourseReportAction, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${widget.courseName}. ${l10n.parkCourseReportExplainer}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.parkCourseReportReasonLegend,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          for (final reason in kCourseReportReasons)
            RadioListTile<String>(
              key: Key('park-course-report-reason-$reason'),
              value: reason,
              groupValue: _reason,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _reason = v ?? _reason),
              title: Text(courseReportReasonLabel(l10n, reason)),
              subtitle: switch (reason) {
                'land_manager_request' =>
                  Text(l10n.parkCourseReportReasonLandManagerHint),
                'rights_holder_request' =>
                  Text(l10n.parkCourseReportReasonRightsHolderHint),
                _ => null,
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('park-course-report-notes'),
            controller: _notesCtl,
            maxLines: 4,
            maxLength: kCourseReportNotesMax,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.parkCourseReportNotesLabel,
              hintText: l10n.parkCourseReportNotesHint,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('park-course-report-email'),
            controller: _emailCtl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            maxLength: kCourseReportEmailMax,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _emailRequired
                  ? l10n.parkCourseReportEmailLabelRequired
                  : l10n.parkCourseReportEmailLabel,
              helperText: !_emailShapeOk
                  ? null
                  : _emailRequired
                      ? l10n.parkCourseReportEmailHintRequired
                      : l10n.parkCourseReportEmailHint,
              helperMaxLines: 3,
              errorText:
                  _emailShapeOk ? null : l10n.parkCourseReportErrorEmail,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('park-course-report-error'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.parkCourseReportCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('park-course-report-submit'),
                  onPressed: _canSubmit ? _submit : null,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.parkCourseReportSubmit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
