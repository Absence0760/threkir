import 'package:flutter/material.dart';

/// A term and its value: on one line, the value at the end, while both fit;
/// the value under the term when they don't.
///
/// A `Row` of an unflexed term beside an `Expanded`, ellipsized value gives
/// the term whatever it asks for and the value what is left, so at large
/// text or in a long translation the number the reader came for is the
/// part that is cut: run detail's "Official result" showed French
/// "Classement dans la catégorie primée" with no place beside it from 1.5x
/// (issue #1374 TO-5). Web's race result grid reflows the same way.
class TermValueRow extends StatelessWidget {
  const TermValueRow({
    super.key,
    required this.term,
    required this.value,
    this.termStyle,
    this.valueStyle,
  });

  final String term;
  final String value;

  /// Defaults: the term in `bodySmall`, the value in `bodyMedium` w600.
  final TextStyle? termStyle;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(term, style: termStyle ?? theme.textTheme.bodySmall),
            Text(
              value,
              textAlign: TextAlign.end,
              style: valueStyle ??
                  theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
