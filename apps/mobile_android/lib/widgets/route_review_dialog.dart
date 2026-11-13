import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show AppSemanticColors, StarRatingInput;

import '../l10n/gen/app_localizations.dart';

typedef RouteReviewDraft = ({int rating, String? comment});

/// The Rate dialog on route detail. Resolves to the picked rating and the
/// trimmed comment (null when blank), or null on Cancel / dismiss.
Future<RouteReviewDraft?> showRouteReviewDialog(
  BuildContext context, {
  int initialRating = 4,
  String? initialComment,
}) {
  return showDialog<RouteReviewDraft>(
    context: context,
    builder: (_) => _RouteReviewDialog(
      initialRating: initialRating,
      initialComment: initialComment,
    ),
  );
}

class _RouteReviewDialog extends StatefulWidget {
  const _RouteReviewDialog({
    required this.initialRating,
    required this.initialComment,
  });

  final int initialRating;
  final String? initialComment;

  @override
  State<_RouteReviewDialog> createState() => _RouteReviewDialogState();
}

class _RouteReviewDialogState extends State<_RouteReviewDialog> {
  late int _rating = widget.initialRating;
  late final TextEditingController _comment =
      TextEditingController(text: widget.initialComment ?? '');

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.routeDetailRateDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarRatingInput(
            value: _rating,
            starLabel: l10n.routeDetailRateStars,
            color: AppSemanticColors.of(context).crown,
            onChanged: (star) => setState(() => _rating = star),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            decoration: InputDecoration(labelText: l10n.routeDetailCommentLabel),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.routeDetailCancel),
        ),
        FilledButton(
          onPressed: () {
            final text = _comment.text.trim();
            Navigator.pop<RouteReviewDraft>(
                context, (rating: _rating, comment: text.isEmpty ? null : text));
          },
          child: Text(l10n.routeDetailSubmit),
        ),
      ],
    );
  }
}
