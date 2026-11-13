// Debug-build-only tool for the timing-line calibration session (#1304 § 6).
// Nothing here is reachable in a release build: the Settings entry and the
// run screen's capture sit behind `kDebugMode`, and this screen and its entry
// render nothing when [kLineCalibrationAvailable] is false.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_models/core_models.dart' show parseIsoStrictValue;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:ui_kit/ui_kit.dart'
    show AppInsets, AppSpace, FieldColumn, PageHeader, PushedPage;

import '../gate_crossing.dart';
import '../l10n/gen/app_localizations.dart';
import '../line_calibration.dart';
import '../share_sheet.dart' show shareTextFrom;
import '../typed_decimal.dart' show parseTypedDecimal;

/// Whether the calibration tools exist in this build.
const bool kLineCalibrationAvailable = kDebugMode;

/// Round trips per clock measurement; the shortest wins.
const int kClockSamples = 10;

/// One round trip to `server_now`, on the device clock and the server's.
typedef ServerClockSample = ({
  DateTime sentAt,
  DateTime receivedAt,
  DateTime serverAt,
});

/// The Settings row that opens [LineCalibrationScreen], debug builds only.
class LineCalibrationEntry extends StatelessWidget {
  const LineCalibrationEntry({
    super.key,
    required this.onOpen,
    this.available = kLineCalibrationAvailable,
  });

  final VoidCallback onOpen;
  final bool available;

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('line-calibration-entry'),
      leading: const Icon(Icons.straighten),
      title: Text(l10n.lineCalibrationEntryTitle),
      subtitle: Text(l10n.lineCalibrationEntrySubtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
    );
  }
}

class LineCalibrationScreen extends StatefulWidget {
  const LineCalibrationScreen({
    super.key,
    this.available = kLineCalibrationAvailable,
    this.capture,
    this.sampleServerClock,
    this.shareCsv,
  });

  final bool available;

  /// Defaults to the run screen's [LineCalibrationCapture.instance].
  final LineCalibrationCapture? capture;

  /// One round trip to the server clock, as a seam for tests.
  final Future<ServerClockSample?> Function()? sampleServerClock;

  /// Hands the CSV on, as a seam for tests. Defaults to the share sheet.
  final Future<void> Function(String csv)? shareCsv;

  @override
  State<LineCalibrationScreen> createState() => _LineCalibrationScreenState();
}

class _LineCalibrationScreenState extends State<LineCalibrationScreen> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _bearing = TextEditingController();
  final _halfWidth =
      TextEditingController(text: kGateHalfWidthRaceM.toStringAsFixed(0));
  final _offset = TextEditingController();
  final _instants = TextEditingController();

  CalibrationApproach _approach = CalibrationApproach.deg90;
  CalibrationPace _pace = CalibrationPace.run;
  CalibrationCarry _carry = CalibrationCarry.hand;
  final List<CalibrationResult> _results = [];
  _Problem? _problem;

  LineCalibrationCapture get _capture =>
      widget.capture ?? LineCalibrationCapture.instance;

  @override
  void dispose() {
    for (final c in [_lat, _lng, _bearing, _halfWidth, _offset, _instants]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The offset text this measurement wrote, so a hand edit drops its
  /// round trip from the export.
  String? _measuredText;
  int? _measuredRttMs;

  /// [kClockSamples] round trips; the shortest one wins.
  Future<void> _measure() async {
    final sample = widget.sampleServerClock ?? _sampleServerClock;
    final clock = CalibrationClock();
    for (var i = 0; i < kClockSamples; i++) {
      final s = await sample();
      if (s != null) {
        clock.addSample(
            sentAt: s.sentAt, receivedAt: s.receivedAt, serverAt: s.serverAt);
      }
    }
    if (!mounted) return;
    final offset = clock.offset;
    final rtt = clock.rtt;
    setState(() {
      if (offset == null || rtt == null) {
        _problem = _Problem.clockFailed;
      } else {
        _offset.text = '${offset.inMilliseconds}';
        _measuredText = _offset.text;
        _measuredRttMs = rtt.inMilliseconds;
        _problem = null;
      }
    });
  }

  static Future<ServerClockSample?> _sampleServerClock() async {
    try {
      final sent = DateTime.now();
      final raw = await Supabase.instance.client
          .rpc('server_now', params: const {}, get: true);
      final received = DateTime.now();
      final server = parseIsoStrictValue(raw);
      if (server == null) return null;
      return (sentAt: sent, receivedAt: received, serverAt: server);
    } catch (e) {
      debugPrint('LineCalibrationScreen server clock failed: $e');
      return null;
    }
  }

  Future<void> _here() async {
    try {
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat.text = p.latitude.toStringAsFixed(7);
        _lng.text = p.longitude.toStringAsFixed(7);
      });
    } catch (e) {
      debugPrint('LineCalibrationScreen position failed: $e');
      if (mounted) setState(() => _problem = _Problem.noFix);
    }
  }

  void _score() {
    final lat = parseTypedDecimal(_lat.text);
    final lng = parseTypedDecimal(_lng.text);
    final bearing = parseTypedDecimal(_bearing.text);
    final half = parseTypedDecimal(_halfWidth.text);
    final offset = int.tryParse(_offset.text.trim());
    final first = _capture.firstFixMs;
    final day = first == null
        ? DateTime.now()
        : DateTime.fromMicrosecondsSinceEpoch((first * 1000).round());
    final instants = parseCalibrationInstants(_instants.text, day);
    _Problem? problem;
    if (lat == null || lng == null || bearing == null || half == null) {
      problem = _Problem.lineMissing;
    } else if (offset == null) {
      problem = _Problem.offsetMissing;
    } else if (instants == null) {
      problem = _Problem.instantsInvalid;
    } else if (_capture.fixCount < 2) {
      problem = _Problem.fewFixes;
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final gate =
        Gate(lat: lat!, lng: lng!, bearingDeg: bearing!, halfWidthM: half!);
    if (!gateUsable(gate)) {
      setState(() => _problem = _Problem.lineUnusable);
      return;
    }
    final result = analyseCalibration(
      cell: CalibrationCell(_approach, _pace, _carry),
      recordings: _capture.recordings,
      gate: gate,
      trueCrossings: instants!,
      clockOffsetMs: offset!,
      offsetRttMs: _offset.text == _measuredText ? _measuredRttMs : null,
    );
    setState(() {
      _results.add(result);
      _problem = null;
      _instants.clear();
    });
  }

  Future<void> _share() async {
    final csv = calibrationCsv(_results);
    final share = widget.shareCsv;
    if (share != null) return share(csv);
    await shareTextFrom(context, text: csv);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: calibrationCsv(_results)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final capture = _capture;
    final title = l10n.lineCalibrationTitle;
    final problem = _problem;
    return PushedPage(
      title: title,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppInsets.gutter),
          children: [
            PageHeader(
              title: title,
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
            ),
            Text(l10n.lineCalibrationIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpace.smPlus),
            Text(
              capture.active
                  ? l10n.lineCalibrationCapturing(capture.fixCount)
                  : l10n.lineCalibrationIdle(capture.fixCount),
              key: const ValueKey('line-calibration-status'),
              style: theme.textTheme.titleSmall,
            ),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                FilledButton(
                  key: const ValueKey('line-calibration-start'),
                  onPressed: capture.active
                      ? null
                      : () => setState(capture.start),
                  child: Text(l10n.lineCalibrationStart),
                ),
                OutlinedButton(
                  key: const ValueKey('line-calibration-stop'),
                  onPressed:
                      capture.active ? () => setState(capture.stop) : null,
                  child: Text(l10n.lineCalibrationStop),
                ),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: Text(l10n.lineCalibrationRefresh),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.smPlus),
            FieldColumn(children: [
              _field(_lat, l10n.lineCalibrationLatLabel),
              _field(_lng, l10n.lineCalibrationLngLabel),
              _field(_bearing, l10n.lineCalibrationBearingLabel),
              _field(_halfWidth, l10n.lineCalibrationHalfWidthLabel),
            ]),
            Wrap(
              spacing: AppSpace.sm,
              children: [
                TextButton(
                  onPressed: _here,
                  child: Text(l10n.lineCalibrationHere),
                ),
                TextButton(
                  key: const ValueKey('line-calibration-measure'),
                  onPressed: _measure,
                  child: Text(l10n.lineCalibrationMeasure(kClockSamples)),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            FieldColumn(children: [
              _field(_offset, l10n.lineCalibrationOffsetLabel,
                  helper: l10n.lineCalibrationOffsetHelper,
                  key: const ValueKey('line-calibration-offset')),
              _picker<CalibrationApproach>(
                  l10n.lineCalibrationApproachLabel,
                  CalibrationApproach.values,
                  _approach,
                  (v) => _approach = v,
                  (v) => _approachLabel(l10n, v)),
              _picker<CalibrationPace>(
                  l10n.lineCalibrationPaceLabel,
                  CalibrationPace.values,
                  _pace,
                  (v) => _pace = v,
                  (v) => _paceLabel(l10n, v)),
              _picker<CalibrationCarry>(
                  l10n.lineCalibrationCarryLabel,
                  CalibrationCarry.values,
                  _carry,
                  (v) => _carry = v,
                  (v) => _carryLabel(l10n, v)),
              TextField(
                key: const ValueKey('line-calibration-instants'),
                controller: _instants,
                minLines: 3,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: l10n.lineCalibrationInstantsLabel,
                  hintText: l10n.lineCalibrationInstantsHint(
                      '07:42:13.480', '2026-11-10T07:42:13.480+01:00'),
                  helperText: l10n.lineCalibrationInstantsHelper,
                  helperMaxLines: 6,
                ),
              ),
            ]),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  _problemText(l10n, problem),
                  key: const ValueKey('line-calibration-problem'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: AppSpace.sm),
            FilledButton(
              key: const ValueKey('line-calibration-score'),
              onPressed: _score,
              child: Text(l10n.lineCalibrationScore),
            ),
            const SizedBox(height: AppSpace.md),
            for (final r in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text([
                  _approachLabel(l10n, r.cell.approach),
                  _paceLabel(l10n, r.cell.pace),
                  _carryLabel(l10n, r.cell.carry),
                ].join(' / ')),
                subtitle: Text([
                  l10n.lineCalibrationResult(
                    r.matched,
                    r.trueCount,
                    r.missed,
                    r.falseCrossings,
                    r.nearMisses,
                    '${r.medianErrorMs ?? '-'}',
                    '${r.medianAbsErrorMs ?? '-'}',
                    '${r.p95AbsErrorMs ?? '-'}',
                    r.offsetRttMs == null ? '?' : '${r.offsetRttMs! ~/ 2}',
                  ),
                  if (r.matched == 0 && r.nearestDiffMs != null)
                    l10n.lineCalibrationNothingMatched(r.nearestDiffMs!),
                ].join('\n')),
              ),
            if (_results.isNotEmpty)
              Wrap(
                spacing: AppSpace.sm,
                children: [
                  FilledButton(
                    key: const ValueKey('line-calibration-share'),
                    onPressed: _share,
                    child: Text(l10n.lineCalibrationShare),
                  ),
                  OutlinedButton(
                    onPressed: _copy,
                    child: Text(l10n.lineCalibrationCopy),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
          {Key? key, String? helper}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(
            signed: true, decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
        ),
      );

  Widget _picker<T>(String label, List<T> values, T value,
          void Function(T) set, String Function(T) name) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final v in values)
            DropdownMenuItem<T>(value: v, child: Text(name(v))),
        ],
        onChanged: (v) {
          if (v != null) setState(() => set(v));
        },
      );
}

/// Why the session cannot go on; worded at build time in the reader's
/// language.
enum _Problem {
  clockFailed,
  noFix,
  lineMissing,
  offsetMissing,
  instantsInvalid,
  fewFixes,
  lineUnusable,
}

String _problemText(AppLocalizations l10n, _Problem p) => switch (p) {
      _Problem.clockFailed => l10n.lineCalibrationClockFailed,
      _Problem.noFix => l10n.lineCalibrationNoFix,
      _Problem.lineMissing => l10n.lineCalibrationLineMissing,
      _Problem.offsetMissing => l10n.lineCalibrationOffsetMissing,
      _Problem.instantsInvalid =>
        l10n.lineCalibrationInstantsInvalid('HH:MM:SS.fff'),
      _Problem.fewFixes => l10n.lineCalibrationFewFixes,
      _Problem.lineUnusable => l10n.lineCalibrationLineUnusable,
    };

String _approachLabel(AppLocalizations l10n, CalibrationApproach a) =>
    switch (a) {
      CalibrationApproach.deg90 => l10n.lineCalibrationApproach90,
      CalibrationApproach.deg30 => l10n.lineCalibrationApproach30,
      CalibrationApproach.parallel20 => l10n.lineCalibrationApproachParallel20,
      CalibrationApproach.parallel40 => l10n.lineCalibrationApproachParallel40,
      CalibrationApproach.standing => l10n.lineCalibrationApproachStanding,
    };

String _paceLabel(AppLocalizations l10n, CalibrationPace p) => switch (p) {
      CalibrationPace.walk => l10n.lineCalibrationPaceWalk,
      CalibrationPace.run => l10n.lineCalibrationPaceRun,
      CalibrationPace.still => l10n.lineCalibrationPaceStill,
    };

String _carryLabel(AppLocalizations l10n, CalibrationCarry c) => switch (c) {
      CalibrationCarry.hand => l10n.lineCalibrationCarryHand,
      CalibrationCarry.pocket => l10n.lineCalibrationCarryPocket,
    };
