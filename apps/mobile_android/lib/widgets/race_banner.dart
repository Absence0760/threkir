import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/gen/app_localizations.dart';
import '../preferences.dart' show formatDistanceForPref;
import '../quiet_location.dart';
import '../race_controller.dart';
import '../race_finish.dart' show raceDistanceM;
import '../course_gates.dart' show SessionStartMode;
import '../race_start_modes.dart';

/// The idle run screen's banner for a race this runner is going to (#1306).
///
/// * Host GO: armed waits for GO, running shows elapsed and asks for Start.
/// * Scheduled GO: armed counts down to the scheduled instant on the server
///   clock and, through [onCountdownCue], lets the run screen speak the
///   10, 5, 3, 2, 1 marks; at the instant it turns live by itself.
/// * Self-timed: while the window is open it says how the attempt works,
///   shows the distance to the frozen start line, and holds the explicit
///   "This run is my attempt" switch (owner decision 4a): nothing binds
///   without it.
class RaceBanner extends StatefulWidget {
  const RaceBanner({
    super.key,
    required this.race,
    required this.controller,
    this.onCountdownCue,
    this.positionFixes,
    this.now,
  });

  final ActiveRace race;
  final RaceController controller;

  /// A countdown mark reached (seconds left). The caller speaks it.
  final void Function(int secondsLeft)? onCountdownCue;

  /// Where the runner is, for the distance to a self-timed start line.
  /// Defaults to [quietPositionFixes], which never prompts for permission.
  final Stream<Position> Function()? positionFixes;

  /// The device clock, as a seam for tests.
  final DateTime Function()? now;

  @override
  State<RaceBanner> createState() => _RaceBannerState();
}

class _RaceBannerState extends State<RaceBanner> {
  Timer? _tick;
  Timer? _locateTimer;
  StreamSubscription<Position>? _positions;
  Position? _here;
  int? _lastCountdownS;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _onTick());
    _syncLocator();
  }

  @override
  void didUpdateWidget(covariant RaceBanner old) {
    super.didUpdateWidget(old);
    if (old.race.isSelfTimed != widget.race.isSelfTimed) _syncLocator();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _locateTimer?.cancel();
    _positions?.cancel();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final secs = _countdownS();
    final cue = voiceCountdownCue(_lastCountdownS, secs);
    _lastCountdownS = secs;
    if (cue != null) {
      // L4: a speech failure never touches the banner.
      try {
        widget.onCountdownCue?.call(cue);
      } catch (e) {
        debugPrint('RaceBanner countdown cue failed: $e');
      }
    }
    setState(() {});
  }

  /// A self-timed banner refreshes the runner's position every 20 s while
  /// shown, quietly: no prompt, and no fix means no distance line.
  void _syncLocator() {
    _locateTimer?.cancel();
    _locateTimer = null;
    if (!widget.race.isSelfTimed) return;
    _locate();
    _locateTimer = Timer.periodic(const Duration(seconds: 20), (_) => _locate());
  }

  void _locate() {
    _positions?.cancel();
    try {
      final source = widget.positionFixes ?? quietPositionFixes;
      _positions = source().listen(
        (p) {
          if (mounted) setState(() => _here = p);
        },
        onError: (Object e) => debugPrint('RaceBanner position failed: $e'),
      );
    } catch (e) {
      debugPrint('RaceBanner position failed: $e');
    }
  }

  DateTime get _serverNow =>
      widget.controller.clockOffset.toServer(_now()).toUtc();

  int? _countdownS() {
    final race = widget.race;
    if (race.startMode != SessionStartMode.scheduled) return null;
    if (race.statusAt(_serverNow) != RaceStatus.armed) return null;
    return raceCountdownS(race.startInstant, _now(),
        widget.controller.clockOffset.offset.inMilliseconds);
  }

  static String _fmt(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  String _clock(BuildContext context, DateTime? t) {
    if (t == null) return '';
    return MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final race = widget.race;
    final status = race.statusAt(_serverNow);
    final label = race.eventTitle ?? l10n.runRaceFallbackTitle;
    final primary = theme.colorScheme.primary;
    final armed = status == RaceStatus.armed;
    final running = status == RaceStatus.running;

    String heading;
    String body;
    switch (race.startMode) {
      case SessionStartMode.scheduled:
        heading = armed ? l10n.runRaceScheduled : l10n.runRaceLive;
        final countdown = _countdownS();
        body = armed
            ? l10n.runRaceStartsIn(label, _fmt(countdown ?? 0))
            : l10n.runRaceElapsedTapStart(label, _fmt(_elapsed(race)));
      case SessionStartMode.selfTimed:
        heading = running ? l10n.runRaceSelfTimed : l10n.runRaceSelfTimedSoon;
        body = running
            ? l10n.runRaceSelfTimedHow(label, _clock(context, race.windowClosesAt))
            : l10n.runRaceSelfTimedOpens(label, _clock(context, race.windowOpensAt));
      case SessionStartMode.hostGo:
        heading = armed ? l10n.runRaceArmed : l10n.runRaceLive;
        body = armed
            ? l10n.runRaceWaitingForGo(label)
            : l10n.runRaceElapsedTapStart(label, _fmt(_elapsed(race)));
    }

    final startLat = race.startLineLat;
    final startLng = race.startLineLng;
    final here = _here;
    final toStartM = race.isSelfTimed && running && here != null &&
            startLat != null && startLng != null
        ? raceDistanceM(here.latitude, here.longitude, startLat, startLng)
        : null;

    return Container(
      key: const ValueKey('race-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        border: Border.all(color: primary, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            armed ? Icons.sports_score : Icons.directions_run,
            color: primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  heading,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Semantics(
                  liveRegion: race.startMode == SessionStartMode.scheduled && armed,
                  child: Text(
                    body,
                    key: const ValueKey('race-banner-body'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (toStartM != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.runRaceToStartLine(formatDistanceForPref(toStartM)),
                      key: const ValueKey('race-banner-to-start'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (race.isSelfTimed && running)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (_, __) {
                        final armedAttempt = widget.controller.attemptArmed;
                        return armedAttempt
                            ? OutlinedButton.icon(
                                key: const ValueKey('race-attempt-cancel'),
                                onPressed: widget.controller.cancelAttempt,
                                icon: const Icon(Icons.check_circle),
                                label: Text(l10n.runRaceAttemptReady),
                              )
                            : FilledButton.icon(
                                key: const ValueKey('race-attempt'),
                                onPressed: widget.controller.armAttempt,
                                icon: const Icon(Icons.flag),
                                label: Text(l10n.runRaceThisIsMyAttempt),
                              );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _elapsed(ActiveRace race) {
    final go = race.goAt;
    if (go == null) return 0;
    final s = _serverNow.difference(go.toUtc()).inSeconds;
    return s < 0 ? 0 : s;
  }
}
