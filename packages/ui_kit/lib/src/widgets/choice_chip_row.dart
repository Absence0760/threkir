import 'package:flutter/material.dart';

/// One option in a [ChoiceChipRow].
@immutable
class ChoiceChipOption<T> {
  const ChoiceChipOption({required this.value, required this.label, this.icon});

  final T value;

  /// Already localized — `ui_kit` has no catalogue, so a default here could
  /// only be English.
  final String label;

  /// Optional leading glyph, replaced by a checkmark while the chip is
  /// selected — which is what makes selection legible without relying on the
  /// fill colour alone. Without one the chip still reserves the slot, so
  /// selecting it does not change its width.
  final IconData? icon;
}

/// A single-select control that **reflows** — the replacement for
/// `SegmentedButton` everywhere in this app.
///
/// `SegmentedButton` divides whatever width it is given equally between its
/// segments and then clips the labels inside them, with no ellipsis, no fade
/// and no overflow banner: the text simply stops. Measured against real Roboto
/// across the seven ARB locales at 320 / 360 / 411 dp and 1.0x / 2.0x, ten of
/// the app's eleven segmented controls lost characters — worst, the route
/// builder's Spanish "Carretera" got 91.0 px of the 117.7 it needs at 411 dp /
/// 2x, and its "Sendero" got 36.7 of 52.5 at **1.0x**, no text scaling
/// involved. Widening the parent hides nothing: the control takes its
/// intrinsic width when it has room and bursts the container instead
/// (decisions § 500).
///
/// A `Wrap` of `ChoiceChip`s cannot do either. A chip is sized by its own
/// label, so nothing is clipped; when the run no longer fits, it moves to a
/// second line. One run of chips lays out exactly as the segmented row did, so
/// the common case is unchanged. It also restores the checkmark that
/// `SegmentedButton` sites had been switching off to save width, so selection
/// stops being signalled by fill colour alone.
class ChoiceChipRow<T> extends StatelessWidget {
  const ChoiceChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.alignment = WrapAlignment.start,
  });

  final List<ChoiceChipOption<T>> options;
  final T selected;

  /// Null disables the whole row, the way a null `onPressed` disables a
  /// button — the state a `SegmentedButton` with a null `onSelectionChanged`
  /// was in.
  final ValueChanged<T>? onChanged;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: alignment,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.label),
            // Never a null avatar. With no avatar, Material grows the chip to
            // fit the checkmark as it animates in and shrinks the one losing
            // it, so every selection resized two chips and slid the row
            // sideways. With one, every chip holds the same square slot.
            //
            // The checkmark is ours, not Material's: Material paints its own
            // over the avatar after darkening the avatar's circle, so a chip
            // with an icon showed a dark disc with the glyph and the check
            // drawn through each other. Swapping the glyph for the check
            // keeps the cue and drops the collision.
            avatar: option.value == selected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).chipTheme.checkmarkColor,
                  )
                : option.icon == null
                    ? const SizedBox.shrink()
                    : Icon(option.icon, size: 18),
            showCheckmark: false,
            selected: option.value == selected,
            onSelected:
                onChanged == null ? null : (_) => onChanged!(option.value),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
      ],
    );
  }
}
