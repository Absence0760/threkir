// Debug-build-only tool for the timing-line calibration session (#1304 § 6).
// Nothing here is reachable in a release build: the Settings entry and the
// run screen's capture sit behind `kDebugMode`, and this screen and its entry
// render nothing when [kLineCalibrationAvailable] is false. Its copy is
// English on purpose: no runner ever sees it.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_models/core_models.dart' show parseIsoStrictValue;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../gate_crossing.dart';
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
    return ListTile(
      key: const ValueKey('line-calibration-entry'),
      leading: const Icon(Icons.straighten),
      title: const Text('Line calibration'),
      subtitle: const Text('Debug build: timing-line error figures'),
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
  String? _problem;

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
        _problem = 'Could not reach the server clock; enter the offset by hand.';
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
      if (mounted) setState(() => _problem = 'No position fix.');
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
    String? problem;
    if (lat == null || lng == null || bearing == null || half == null) {
      problem = 'Enter the line: centre, bearing of travel, half-width.';
    } else if (offset == null) {
      problem = 'Measure or enter the clock offset.';
    } else if (instants == null) {
      problem = 'One instant per line: HH:MM:SS.fff or ISO-8601.';
    } else if (_capture.fixCount < 2) {
      problem = 'The capture holds fewer than two fixes.';
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    final gate =
        Gate(lat: lat!, lng: lng!, bearingDeg: bearing!, halfWidthM: half!);
    if (!gateUsable(gate)) {
      setState(() => _problem = 'That line is not usable.');
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
    final theme = Theme.of(context);
    final capture = _capture;
    return Scaffold(
      appBar: AppBar(title: const Text('Line calibration (debug)')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Start a capture, record a run on the Run tab through the line, '
              'then stop the capture here. Video-time each real crossing '
              'against an NTP-synced clock and enter those instants. The CSV '
              'holds error figures and counts only.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              capture.active
                  ? 'Capturing: ${capture.fixCount} fixes'
                  : 'Idle: ${capture.fixCount} fixes held',
              key: const ValueKey('line-calibration-status'),
              style: theme.textTheme.titleSmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('line-calibration-start'),
                  onPressed: capture.active
                      ? null
                      : () => setState(capture.start),
                  child: const Text('Start capture'),
                ),
                OutlinedButton(
                  key: const ValueKey('line-calibration-stop'),
                  onPressed:
                      capture.active ? () => setState(capture.stop) : null,
                  child: const Text('Stop capture'),
                ),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_lat, 'Line centre latitude')),
                const SizedBox(width: 8),
                Expanded(child: _field(_lng, 'Line centre longitude')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field(_bearing, 'Bearing of travel, deg')),
                const SizedBox(width: 8),
                Expanded(child: _field(_halfWidth, 'Half-width, m')),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _here,
                  child: const Text('Centre at my position'),
                ),
                TextButton(
                  key: const ValueKey('line-calibration-measure'),
                  onPressed: _measure,
                  child: const Text('Measure server clock (10 round trips)'),
                ),
              ],
            ),
            _field(_offset, 'Clock offset, ms (server minus device)',
                key: const ValueKey('line-calibration-offset')),
            const SizedBox(height: 8),
            _picker<CalibrationApproach>('Approach', CalibrationApproach.values,
                _approach, (v) => _approach = v, (v) => v.wire),
            _picker<CalibrationPace>('Pace', CalibrationPace.values, _pace,
                (v) => _pace = v, (v) => v.wire),
            _picker<CalibrationCarry>('Carry', CalibrationCarry.values, _carry,
                (v) => _carry = v, (v) => v.wire),
            TextField(
              key: const ValueKey('line-calibration-instants'),
              controller: _instants,
              minLines: 3,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'True crossing instants, one per line',
                hintText: '07:42:13.480 or 2026-11-10T07:42:13.480+01:00',
                helperText: 'A time of day is read in this phone\'s zone on the '
                    'capture day; give an ISO instant with its zone across '
                    'midnight or when the reference clock shows UTC.',
                helperMaxLines: 3,
              ),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _problem!,
                  key: const ValueKey('line-calibration-problem'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('line-calibration-score'),
              onPressed: _score,
              child: const Text('Score this capture'),
            ),
            const SizedBox(height: 16),
            for (final r in _results)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    '${r.cell.approach.wire} / ${r.cell.pace.wire} / ${r.cell.carry.wire}'),
                subtitle: Text(
                  '${r.matched} of ${r.trueCount} matched, ${r.missed} missed, '
                  '${r.falseCrossings} false, ${r.nearMisses} near; '
                  'median ${r.medianErrorMs ?? '-'} ms, '
                  '|err| p50 ${r.medianAbsErrorMs ?? '-'} ms, '
                  'p95 ${r.p95AbsErrorMs ?? '-'} ms; offset '
                  '±${r.offsetRttMs == null ? '?' : r.offsetRttMs! ~/ 2} ms'
                  '${r.matched == 0 && r.nearestDiffMs != null ? '. Nothing '
                      'matched, yet detections sit a median '
                      '${r.nearestDiffMs} ms from the truths: check the '
                      'clock, offset and time zone' : ''}',
                ),
              ),
            if (_results.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('line-calibration-share'),
                    onPressed: _share,
                    child: const Text('Share CSV'),
                  ),
                  OutlinedButton(
                    onPressed: _copy,
                    child: const Text('Copy CSV'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {Key? key}) =>
      TextField(
        key: key,
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(
            signed: true, decimal: true),
        decoration: InputDecoration(labelText: label),
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
