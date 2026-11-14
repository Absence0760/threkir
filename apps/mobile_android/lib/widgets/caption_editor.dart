import 'package:flutter/material.dart';

/// The inline caption editor the photo galleries share (run, route and club
/// photos). It owns the typed text and stays open, with the field locked and
/// a spinner on Save, until the write settles: [onSave] answers whether the
/// caption was stored, and only a stored caption closes the editor. A failed
/// write leaves the person's text in the field to retry (issue #1374 FS-11;
/// conventions § A write that failed keeps what the person typed). The caller
/// reports the failure, since it knows which gallery's copy to use.
class CaptionEditor extends StatefulWidget {
  const CaptionEditor({
    super.key,
    required this.initial,
    required this.hint,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onSave,
    required this.onClose,
    this.maxLength = 280,
  });

  final String? initial;
  final String hint;
  final String cancelLabel;
  final String saveLabel;

  /// Writes the caption (null when cleared) and answers whether it was stored.
  final Future<bool> Function(String? caption) onSave;

  /// Closes the editor: after a stored caption, or on Cancel.
  final VoidCallback onClose;
  final int maxLength;

  @override
  State<CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<CaptionEditor> {
  late final _ctrl = TextEditingController(text: widget.initial ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final next = _ctrl.text.trim();
    setState(() => _saving = true);
    final stored = await widget.onSave(next.isEmpty ? null : next);
    if (!mounted) return;
    if (stored) {
      widget.onClose();
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _ctrl,
          maxLength: widget.maxLength,
          readOnly: _saving,
          decoration: InputDecoration(
            hintText: widget.hint,
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 4),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            TextButton(
              onPressed: _saving ? null : widget.onClose,
              child: Text(widget.cancelLabel),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: widget.saveLabel,
                      ),
                    )
                  : Text(widget.saveLabel),
            ),
          ],
        ),
      ],
    );
  }
}
