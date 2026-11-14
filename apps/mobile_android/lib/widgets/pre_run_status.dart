import 'dart:async';

import 'package:core_models/core_models.dart' show DistanceUnit, Waypoint;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:ui_kit/ui_kit.dart';

import '../l10n/gen/app_localizations.dart';
import '../map_tile_readiness.dart';
import '../pre_run_status.dart';
import '../preferences.dart' show UnitFormat;
import 'live_run_map.dart';

/// How often the page re-reads location services and permissions while it
/// shows. Quick settings and the permission prompt do not always pause the
/// app, so a resume alone would miss a toggle.
const Duration kPreRunRecheckInterval = Duration(seconds: 5);

/// The idle Run page below its setup row: everything that decides whether the
/// next run gets a route, said before START rather than discovered after it.
///
/// A sliver, because the area it fills is "whatever the page has left": the
/// map preview takes the rest of the viewport, and a blocked state centres
/// its message there. Above it sit the warnings that cost the run something
/// without stopping it (approximate location, Physical activity, notifications).
///
/// Layering (run_recording.md § Layering): this is L2 and L4 around an L1
/// question. Every platform call is caught on its own, an unreadable answer is
/// never reported as a block, and the map's failure is said in the map area
/// with recording called out as unaffected. START makes its own checks and
/// does not wait on anything here.
///
/// The page listens for fixes only while it shows ([shown] true and the app in
/// the foreground) and stops the moment either changes, or the page leaves
/// idle and this sliver is disposed. RunRecorder opens its own stream at the
/// countdown.
class PreRunStatusSliver extends StatefulWidget {
  const PreRunStatusSliver({
    super.key,
    this.probe = const PlatformPreRunProbe(),
    this.shown,
    this.fixesAllowed,
    required this.unit,
    this.plannedRoute,
    this.offlinePackRouteId,
    this.bottomPadding = 0,
    this.minStageHeight = 200,
    this.clock = DateTime.now,
  });

  final PreRunProbe probe;

  /// Whether the Run page is the shell page on screen. Null outside the shell.
  final ValueListenable<bool>? shown;

  /// False while a recorder exists. geolocator shares one position stream
  /// per process with whoever opened it first, so the page lets go before
  /// the recorder opens its own (`_newRecorder` in run_screen.dart).
  final ValueListenable<bool>? fixesAllowed;

  final DistanceUnit unit;
  final List<Waypoint>? plannedRoute;
  final String? offlinePackRouteId;

  /// Space under the stage for whatever floats over the bottom of the page.
  final double bottomPadding;

  /// The stage never gets shorter than this, so a page whose setup cards fill
  /// the view still scrolls to a usable map.
  final double minStageHeight;

  @visibleForTesting
  final DateTime Function() clock;

  @override
  State<PreRunStatusSliver> createState() => _PreRunStatusSliverState();
}

class _PreRunStatusSliverState extends State<PreRunStatusSliver>
    with WidgetsBindingObserver {
  bool? _servicesOn;
  LocationPermission? _permission;
  bool? _precise;
  final Map<PreRunExtra, ph.PermissionStatus?> _extras = {};

  Position? _fix;
  DateTime? _fixAt;
  Position? _lastKnown;

  StreamSubscription<Position>? _positions;
  Timer? _recheck;
  bool _running = false;
  bool _foreground = true;
  int _refreshGeneration = 0;

  BasemapHealth _tiles = BasemapHealth();
  int _mapGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    widget.shown?.addListener(_syncRunning);
    widget.fixesAllowed?.addListener(_syncRunning);
    _tiles.addListener(_onTiles);
    _syncRunning();
  }

  @override
  void didUpdateWidget(covariant PreRunStatusSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.shown, oldWidget.shown) ||
        !identical(widget.fixesAllowed, oldWidget.fixesAllowed)) {
      oldWidget.shown?.removeListener(_syncRunning);
      oldWidget.fixesAllowed?.removeListener(_syncRunning);
      widget.shown?.addListener(_syncRunning);
      widget.fixesAllowed?.addListener(_syncRunning);
      _syncRunning();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is the permission prompt and the notification shade: the
    // page is still in view, so only a real departure stops it.
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _syncRunning();
        // Back from a settings page or a prompt: say what changed at once.
        if (_running) unawaited(_refresh());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        _syncRunning();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.shown?.removeListener(_syncRunning);
    widget.fixesAllowed?.removeListener(_syncRunning);
    _stop();
    _tiles.removeListener(_onTiles);
    _tiles.dispose();
    super.dispose();
  }

  void _syncRunning() {
    final want = _foreground &&
        (widget.shown?.value ?? true) &&
        (widget.fixesAllowed?.value ?? true);
    if (want == _running) return;
    if (want) {
      _running = true;
      _recheck = Timer.periodic(kPreRunRecheckInterval, (_) => _refresh());
      unawaited(_refresh());
    } else {
      _stop();
    }
  }

  void _stop() {
    _running = false;
    _recheck?.cancel();
    _recheck = null;
    _closePositions();
  }

  void _closePositions() {
    final sub = _positions;
    _positions = null;
    if (sub != null) unawaited(sub.cancel().catchError((Object _) {}));
  }

  /// Each read is caught on its own: a platform that cannot answer one
  /// question still answers the rest, and an unanswered one reads as unknown.
  Future<T?> _read<T>(String what, Future<T?> Function() call) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('pre-run $what check failed: $e');
      return null;
    }
  }

  Future<void> _refresh() async {
    final generation = ++_refreshGeneration;
    final servicesOn =
        await _read('location services', widget.probe.locationServiceEnabled);
    final permission =
        await _read('location permission', widget.probe.locationPermission);
    final usable = servicesOn != false &&
        permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
    final precise =
        usable ? await _read('precise location', widget.probe.preciseLocation) : null;
    final extras = <PreRunExtra, ph.PermissionStatus?>{
      for (final extra in PreRunExtra.values)
        extra: await _read('${extra.name} permission',
            () => widget.probe.extraStatus(extra)),
    };
    if (!mounted || !_running || generation != _refreshGeneration) return;
    setState(() {
      _servicesOn = servicesOn;
      _permission = permission;
      _precise = precise;
      _extras
        ..clear()
        ..addAll(extras);
    });
    if (usable) {
      _openPositions();
    } else {
      _closePositions();
    }
  }

  void _openPositions() {
    if (_positions != null) return;
    try {
      _positions = widget.probe.positions().listen(
        (p) {
          if (!mounted) return;
          setState(() {
            _fix = p;
            _fixAt = widget.clock();
          });
        },
        // Services switched off, a revoked grant, a platform without the
        // plugin: drop the stream and let the next recheck say why.
        onError: (Object e) {
          debugPrint('pre-run position stream failed: $e');
          _positions = null;
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('pre-run position stream failed to open: $e');
      _positions = null;
    }
    if (_lastKnown == null) unawaited(_readLastKnown());
  }

  Future<void> _readLastKnown() async {
    final last = await _read('last known position', widget.probe.lastKnownPosition);
    if (last != null && mounted) setState(() => _lastKnown = last);
  }

  void _onTiles() {
    if (mounted) setState(() {});
  }

  void _retryMap() {
    setState(() {
      _tiles.removeListener(_onTiles);
      _tiles.dispose();
      _tiles = BasemapHealth()..addListener(_onTiles);
      _mapGeneration++;
    });
  }

  Future<void> _act(String what, Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      debugPrint('pre-run $what failed: $e');
    }
    if (mounted && _running) await _refresh();
  }

  Future<void> _requestLocation() => _act('location request', () async {
        await widget.probe.requestLocationPermission();
      });

  Future<void> _fixExtra(PreRunExtra extra, PreRunRemedy remedy) =>
      _act('${extra.name} remedy', () async {
        if (remedy == PreRunRemedy.request) {
          final status = await widget.probe.requestExtra(extra);
          // Android stops showing the prompt after a second refusal; the
          // next tap has to go to the app's settings instead.
          if (status.isPermanentlyDenied) return;
        } else {
          await widget.probe.openAppSettings();
        }
      });

  PreRunGps get _gps {
    final at = _fixAt;
    return resolvePreRunGps(
      servicesOn: _servicesOn,
      permission: _permission,
      accuracyM: _fix?.accuracy,
      fixAge: at == null ? null : widget.clock().difference(at),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final gps = _gps;
    final warnings = <Widget>[
      if (preRunWantsFixes(gps) && _precise == false)
        _Warning(
          key: const ValueKey('pre-run-approximate'),
          icon: Icons.location_searching,
          text: l10n.runPreciseLocationOff,
          action: l10n.runOpenSettings,
          onAction: () => _act('app settings', widget.probe.openAppSettings),
        ),
      for (final extra in PreRunExtra.values)
        if (preRunRemedy(_extras[extra]) case final remedy?)
          _Warning(
            key: ValueKey('pre-run-${extra.name}'),
            icon: switch (extra) {
              PreRunExtra.activityRecognition => Icons.directions_walk,
              PreRunExtra.notifications => Icons.notifications_off_outlined,
            },
            text: switch (extra) {
              PreRunExtra.activityRecognition => l10n.runPreRunActivityOff,
              PreRunExtra.notifications => l10n.runNotificationsOffHint,
            },
            action: remedy == PreRunRemedy.request
                ? l10n.runPreRunAllow
                : l10n.runOpenSettings,
            onAction: () => _fixExtra(extra, remedy),
          ),
    ];
    return SliverMainAxisGroup(
      slivers: [
        if (warnings.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: warnings,
            ),
          ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: widget.bottomPadding),
            child: _stage(context, l10n, gps),
          ),
        ),
      ],
    );
  }

  Widget _stage(BuildContext context, AppLocalizations l10n, PreRunGps gps) {
    final position = _fix ?? _lastKnown;
    if (preRunWantsFixes(gps) && position != null) {
      return _StageHeight(
        minHeight: widget.minStageHeight,
        measureChild: false,
        child: _mapStage(context, l10n, gps, position),
      );
    }
    final Widget message = switch (gps) {
      PreRunGps.servicesOff => _Message(
          key: const ValueKey('pre-run-services-off'),
          icon: Icons.location_off,
          title: l10n.runPreRunLocationOffTitle,
          body: l10n.runPreRunLocationOffBody,
          action: l10n.runPreRunTurnOnLocation,
          onAction: () =>
              _act('location settings', widget.probe.openLocationSettings),
        ),
      PreRunGps.permissionNeeded => _Message(
          key: const ValueKey('pre-run-permission'),
          icon: Icons.location_disabled,
          title: l10n.runPreRunPermissionTitle,
          body: l10n.runPreRunPermissionBody,
          action: l10n.runPreRunAllowLocation,
          onAction: _requestLocation,
        ),
      PreRunGps.permissionBlocked => _Message(
          key: const ValueKey('pre-run-permission-blocked'),
          icon: Icons.location_disabled,
          title: l10n.runPreRunPermissionBlockedTitle,
          body: l10n.runPreRunPermissionBlockedBody,
          action: l10n.runOpenSettings,
          onAction: () => _act('app settings', widget.probe.openAppSettings),
        ),
      _ => _Message(
          key: const ValueKey('pre-run-searching'),
          icon: Icons.gps_not_fixed,
          title: l10n.runPreRunSearching,
          body: l10n.runPreRunSearchingHint,
        ),
    };
    return _StageHeight(
      minHeight: widget.minStageHeight,
      measureChild: true,
      child: _StageFrame(child: Center(child: message)),
    );
  }

  Widget _mapStage(BuildContext context, AppLocalizations l10n, PreRunGps gps,
      Position position) {
    final accuracy = _fix?.accuracy;
    final distance =
        accuracy == null ? null : UnitFormat.elevation(accuracy, widget.unit);
    final (label, a11y, icon) = switch (gps) {
      PreRunGps.ready when distance != null => (
          l10n.runPreRunGpsReady(distance),
          l10n.runPreRunGpsReadyA11y(distance),
          Icons.gps_fixed,
        ),
      PreRunGps.weak when distance != null => (
          l10n.runPreRunGpsWeak(distance),
          l10n.runPreRunGpsWeakA11y(distance),
          Icons.gps_not_fixed,
        ),
      _ => (l10n.runPreRunSearching, null, Icons.gps_not_fixed),
    };
    final current = _fix != null && gps != PreRunGps.searching;
    // The visible "±" is read as an accuracy sentence instead.
    final chip = MapOverlayChip(label: label, leading: Icon(icon, size: 14));
    return _StageFrame(
      child: Stack(
        children: [
          Positioned.fill(
            child: LiveRunMap(
              key: ValueKey('pre-run-map-$_mapGeneration'),
              track: const [],
              currentPosition:
                  Waypoint(lat: position.latitude, lng: position.longitude),
              plannedRoute: widget.plannedRoute,
              offlinePackRouteId: widget.offlinePackRouteId,
              interactive: false,
              tileHealth: _tiles,
              coarsePosition: !current,
              weakPosition: gps == PreRunGps.weak,
            ),
          ),
          Positioned(
            key: const ValueKey('pre-run-gps-chip'),
            top: AppSpace.smPlus,
            left: AppSpace.smPlus,
            right: AppSpace.smPlus,
            child: Center(
              child: a11y == null
                  ? Semantics(container: true, child: chip)
                  : Semantics(
                      container: true,
                      label: a11y,
                      excludeSemantics: true,
                      child: chip,
                    ),
            ),
          ),
          if (_tiles.unavailable)
            Positioned(
              key: const ValueKey('pre-run-map-failed'),
              left: AppSpace.sm,
              right: AppSpace.sm,
              bottom: AppSpace.sm,
              child: ListCard(
                margin: EdgeInsets.zero,
                actions: [
                  TextButton(
                    onPressed: _retryMap,
                    child: Text(l10n.runPreRunMapRetry),
                  ),
                ],
                child: Text(l10n.runPreRunMapFailed),
              ),
            ),
        ],
      ),
    );
  }
}

/// The rounded area the map or a message fills.
class _StageFrame extends StatelessWidget {
  const _StageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: child,
      ),
    );
  }
}

/// A centred message in the stage: what is wrong, what it costs, and the one
/// thing that fixes it.
class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: AppSpace.smPlus),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpace.md),
            FilledButton(onPressed: onAction, child: Text(action!)),
          ],
        ],
      ),
    );
  }
}

/// A loss the run can still start with, and the tap that undoes it.
class _Warning extends StatelessWidget {
  const _Warning({
    super.key,
    required this.icon,
    required this.text,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return ListCard.row(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      dense: true,
      leading: Icon(icon),
      title: text,
      titleMaxLines: 6,
      actions: [TextButton(onPressed: onAction, child: Text(action))],
    );
  }
}

/// Answers [SliverFillRemaining]'s height question for the stage.
///
/// The sliver sizes its child to the larger of the space left and the child's
/// intrinsic height. A message measures fine, so [measureChild] lets it grow
/// past [minHeight] at large text. The map cannot be measured — flutter_map
/// lays out through a `LayoutBuilder`, which throws on an intrinsic query —
/// so for it the answer is [minHeight] alone.
class _StageHeight extends SingleChildRenderObjectWidget {
  const _StageHeight({
    required this.minHeight,
    required this.measureChild,
    required super.child,
  });

  final double minHeight;
  final bool measureChild;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderStageHeight(minHeight, measureChild);

  @override
  void updateRenderObject(
      BuildContext context, _RenderStageHeight renderObject) {
    renderObject
      ..minHeight = minHeight
      ..measureChild = measureChild;
  }
}

class _RenderStageHeight extends RenderProxyBox {
  _RenderStageHeight(this._minHeight, this._measureChild);

  double _minHeight;
  set minHeight(double v) {
    if (v == _minHeight) return;
    _minHeight = v;
    markNeedsLayout();
  }

  bool _measureChild;
  set measureChild(bool v) {
    if (v == _measureChild) return;
    _measureChild = v;
    markNeedsLayout();
  }

  double _height(double width) {
    final child = this.child;
    if (!_measureChild || child == null) return _minHeight;
    final measured = child.getMaxIntrinsicHeight(width);
    return measured > _minHeight ? measured : _minHeight;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _height(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _height(width);
}
