import 'package:flutter/material.dart';

/// A named section whose body the reader can collapse. Controlled: the host
/// owns [open] so it can persist the choice (see `disclosure_state.dart`).
/// Web twin: `apps/web/src/lib/components/DisclosureSection.svelte`.
///
/// The body stays mounted while collapsed, so a section with its own state —
/// the calendar's visible month — is where the reader left it on reopening.
class DisclosureSection extends StatelessWidget {
  final String title;

  /// One short line saying what is inside, so a collapsed section can be
  /// judged without opening it.
  final String? hint;
  final bool open;
  final ValueChanged<bool> onToggle;
  final Widget child;

  const DisclosureSection({
    super.key,
    required this.title,
    this.hint,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onToggle(!open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (hint != null)
                              Text(
                                hint!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Visibility(
          visible: open,
          maintainState: true,
          child: Padding(padding: const EdgeInsets.only(top: 4), child: child),
        ),
      ],
    );
  }
}
