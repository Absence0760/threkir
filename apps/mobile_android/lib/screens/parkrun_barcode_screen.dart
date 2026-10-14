import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../column_limits.dart';
import '../l10n/gen/app_localizations.dart';
import '../parkrun_barcode.dart';
import '../parkrun_barcode_cache.dart';
import '../screen_brightness_bridge.dart';
import '../widgets/parkrun_barcode_view.dart';

/// The runner's parkrun barcode, full screen, for the finish funnel.
///
/// Offline-first: the device's cached copy renders at once, and the server's
/// `parkrun_number` replaces it when it arrives. Brightness goes to full and
/// the screen stays awake while it is up; both are auxiliary, so a failure in
/// either still shows the code.
class ParkrunBarcodeScreen extends StatefulWidget {
  const ParkrunBarcodeScreen({
    super.key,
    required this.api,
    this.cache = const ParkrunBarcodeCache(),
    this.brightness = const ScreenBrightnessBridge(),
  });

  final ApiClient api;
  final ParkrunBarcodeCache cache;
  final ScreenBrightnessBridge brightness;

  @override
  State<ParkrunBarcodeScreen> createState() => _ParkrunBarcodeScreenState();
}

class _ParkrunBarcodeScreenState extends State<ParkrunBarcodeScreen>
    with WidgetsBindingObserver {
  ParkrunBarcodeLoad _load = const ParkrunBarcodeLoad.loading();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keepAwake(true);
    unawaited(widget.brightness.setMax());
    if (widget.api.userId == null) {
      _load = const ParkrunBarcodeLoad._(ParkrunBarcodeLoadKind.unavailable);
    } else {
      unawaited(_loadNumber());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAwake(false);
    unawaited(widget.brightness.restore());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS changes the device brightness rather than this window's, so it is
    // handed back whenever the app is not in front.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.brightness.setMax());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(widget.brightness.restore());
    }
  }

  void _keepAwake(bool on) {
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable())
          .catchError((Object e) {
        debugPrint('parkrun barcode wakelock ${on ? 'enable' : 'disable'} failed: $e');
      }),
    );
  }

  Future<void> _loadNumber() async {
    final userId = widget.api.userId;
    if (userId == null) {
      setState(() => _load = const ParkrunBarcodeLoad._(ParkrunBarcodeLoadKind.unavailable));
      return;
    }
    final cached = await widget.cache.read(userId);
    if (!mounted) return;
    if (cached != null) {
      setState(() => _load = ParkrunBarcodeLoad.cached(cached));
    }
    try {
      final profile = await widget.api.fetchMyProfile();
      final stored = profile?.parkrunNumber;
      await widget.cache.write(userId, stored);
      if (!mounted) return;
      setState(() => _load = ParkrunBarcodeLoad.fromServer(stored));
    } catch (e) {
      debugPrint('parkrun barcode: profile fetch failed: $e');
      if (!mounted) return;
      setState(() => _load = _load.afterFetchFailed());
    }
  }

  Future<void> _retry() async {
    setState(() => _load = const ParkrunBarcodeLoad.loading());
    await _loadNumber();
  }

  Future<void> _editNumber() async {
    final l10n = AppLocalizations.of(context);
    final userId = widget.api.userId;
    if (userId == null) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => _AthleteNumberDialog(initial: _load.number ?? ''),
    );
    if (saved == null || !mounted) return;
    try {
      await widget.api.setParkrunAthleteNumber(saved);
      await widget.cache.write(userId, saved);
      if (!mounted) return;
      setState(() => _load = ParkrunBarcodeLoad.fromServer(saved));
    } catch (e) {
      debugPrint('parkrun barcode: save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.parkrunBarcodeSaveFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Fixed light surface in both themes: the whole screen is the light the
    // scanner needs, and dark-theme ink would vanish on it.
    return Theme(
      data: ThemeData.from(
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        textTheme: Theme.of(context).textTheme,
      ),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(l10n.parkrunBarcodeTitle)),
          body: SafeArea(child: _body(context, l10n)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final load = _load;
    final Widget content;
    switch (load.kind) {
      case ParkrunBarcodeLoadKind.loading:
        content = const Center(child: CircularProgressIndicator());
      case ParkrunBarcodeLoadKind.unavailable:
        content = _message(
          text,
          l10n.parkrunBarcodeLoadFailed,
          FilledButton(onPressed: _retry, child: Text(l10n.parkrunBarcodeRetry)),
        );
      case ParkrunBarcodeLoadKind.none:
        content = _message(
          text,
          l10n.parkrunBarcodeEmpty,
          FilledButton(
            key: const ValueKey('parkrun-barcode-add'),
            onPressed: _editNumber,
            child: Text(l10n.parkrunBarcodeAdd),
          ),
        );
      case ParkrunBarcodeLoadKind.invalid:
        content = _message(
          text,
          l10n.parkrunBarcodeInvalid,
          FilledButton(onPressed: _editNumber, child: Text(l10n.parkrunBarcodeEdit)),
        );
      case ParkrunBarcodeLoadKind.ready:
        content = ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.parkrunBarcodeHint, style: text.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ParkrunBarcodeView(number: load.number!, barHeight: 140),
            if (load.fromCache) ...[
              const SizedBox(height: 12),
              Text(
                l10n.parkrunBarcodeOfflineCopy,
                key: const ValueKey('parkrun-barcode-offline'),
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Text(l10n.parkrunBarcodePaperNote, style: text.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: _editNumber,
                child: Text(l10n.parkrunBarcodeEdit),
              ),
            ),
          ],
        );
    }
    return content;
  }

  Widget _message(TextTheme text, String body, Widget action) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(body, style: text.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              action,
            ],
          ),
        ),
      );
}

enum ParkrunBarcodeLoadKind { loading, unavailable, none, invalid, ready }

/// What the screen can show: a code (from the device's copy or the server),
/// nothing saved, a saved value that is not an athlete number, or nothing
/// at all because neither the copy nor the server answered.
class ParkrunBarcodeLoad {
  const ParkrunBarcodeLoad._(this.kind, {this.number, this.fromCache = false});

  const ParkrunBarcodeLoad.loading() : this._(ParkrunBarcodeLoadKind.loading);

  const ParkrunBarcodeLoad.cached(String number)
      : this._(ParkrunBarcodeLoadKind.ready, number: number, fromCache: true);

  factory ParkrunBarcodeLoad.fromServer(String? stored) {
    final number = normalizeParkrunAthleteNumber(stored);
    if (number != null) {
      return ParkrunBarcodeLoad._(ParkrunBarcodeLoadKind.ready, number: number);
    }
    return (stored ?? '').trim().isEmpty
        ? const ParkrunBarcodeLoad._(ParkrunBarcodeLoadKind.none)
        : const ParkrunBarcodeLoad._(ParkrunBarcodeLoadKind.invalid);
  }

  final ParkrunBarcodeLoadKind kind;
  final String? number;
  final bool fromCache;

  /// A failed refresh keeps a code already on screen; with none, there is
  /// nothing to show but the failure.
  ParkrunBarcodeLoad afterFetchFailed() => kind == ParkrunBarcodeLoadKind.ready
      ? this
      : const ParkrunBarcodeLoad._(ParkrunBarcodeLoadKind.unavailable);
}

class _AthleteNumberDialog extends StatefulWidget {
  const _AthleteNumberDialog({required this.initial});

  final String initial;

  @override
  State<_AthleteNumberDialog> createState() => _AthleteNumberDialogState();
}

class _AthleteNumberDialogState extends State<_AthleteNumberDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  bool _showError = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final number = normalizeParkrunAthleteNumber(_ctrl.text);
    if (number == null) {
      setState(() => _showError = true);
      return;
    }
    Navigator.pop(context, number);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.parkrunBarcodeTitle),
      content: TextField(
        key: const ValueKey('parkrun-barcode-field'),
        controller: _ctrl,
        autofocus: true,
        autocorrect: false,
        maxLength: columnLength('user_profiles.parkrun_number'),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.integrationsParkrunFieldLabel,
          hintText: 'A123456',
          errorText: _showError ? l10n.parkrunBarcodeFieldInvalid : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.integrationsCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.parkrunBarcodeSave),
        ),
      ],
    );
  }
}
