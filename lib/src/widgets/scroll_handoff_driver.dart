import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

/// Shared edge-scroll-handoff engine for `MonacoEditor` and
/// `MonacoDiffEditor`.
///
/// Owns everything between "a `scrollHandoff` event arrived" and "a Flutter
/// scroll position moved": the config and source gates, the [MonacoScrollHandoff.onHandoff]
/// callback, per-frame delta coalescing, and target resolution (explicit
/// controller, else the nearest enclosing vertical scrollable). The host
/// `State` stays responsible for stream wiring, source syncing over the
/// bridge, and calling [clearPending] on teardown.
class ScrollHandoffDriver {
  /// Creates a driver bound to its host `State` through callbacks, so it
  /// always reads the current widget config and context.
  ScrollHandoffDriver({
    required this._config,
    required this._context,
    required this._isMounted,
  });

  final MonacoScrollHandoff Function() _config;
  final BuildContext Function() _context;
  final bool Function() _isMounted;

  /// Scroll handoff deltas accumulated between frames (wheel semantics:
  /// positive scrolls down). Applied once per frame to the resolved target.
  double _pendingDelta = 0;
  bool _frameScheduled = false;

  /// The gestureId whose deltas may move the host, or `null` when no
  /// sessionized gesture is active. The legacy id `0` (continuous policy or
  /// a pre-3.4 page) bypasses the gate entirely.
  int? _activeGestureId;

  /// Handles one forwarded handoff message from the editor page.
  ///
  /// Session bookkeeping happens for every message; only payload-bearing
  /// phases (begin/update) can reach [MonacoScrollHandoff.onHandoff] and the
  /// built-in scrolling.
  void handle(MonacoScrollHandoffDetails details) {
    final config = _config();
    if (!config.isEnabled) return;
    final sourceEnabled = switch (details.source) {
      MonacoScrollHandoffSource.wheel => config.desktopWheel,
      MonacoScrollHandoffSource.touch => config.mobileTouch,
    };
    if (!sourceEnabled) return;

    switch (details.phase) {
      case MonacoScrollHandoffPhase.begin:
        // A new host-owned gesture supersedes whatever came before it,
        // including deltas of the old gesture still waiting for a frame.
        _activeGestureId = details.gestureId;
        _pendingDelta = 0;
      case MonacoScrollHandoffPhase.update:
        // Only the active gesture may move the host. Id 0 is the
        // unsessionized legacy stream and is always live.
        final stale =
            details.gestureId != 0 && details.gestureId != _activeGestureId;
        if (stale) return;
      case MonacoScrollHandoffPhase.end:
        // The gesture is over; deltas it already accumulated still apply.
        if (details.gestureId == _activeGestureId) _activeGestureId = null;
        return;
      case MonacoScrollHandoffPhase.cancel:
        if (details.gestureId == _activeGestureId) {
          _activeGestureId = null;
          _pendingDelta = 0;
        }
        return;
    }

    // The callback sees every payload delta; coalescing below only affects
    // the built-in parent scrolling.
    final onHandoff = config.onHandoff;
    if (onHandoff != null && onHandoff(details)) return;

    if (details.deltaY == 0) return;
    _pendingDelta += details.deltaY;
    _scheduleFlush();
  }

  /// Drops any accumulated delta and forgets the active gesture; call when
  /// the controller goes away so a pending flush cannot scroll on behalf of
  /// a dead editor.
  void clearPending() {
    _pendingDelta = 0;
    _activeGestureId = null;
  }

  /// Coalesces high-frequency bridge deltas into one scroll application per
  /// frame so trackpad streams cannot flood the scroll position.
  void _scheduleFlush() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameScheduled = false;
      final delta = _pendingDelta;
      _pendingDelta = 0;
      if (!_isMounted() || delta == 0) return;
      _applyDelta(delta);
    });
  }

  void _applyDelta(double delta) {
    final config = _config();
    if (!config.isEnabled) return;
    for (final position in _resolvePositions(config)) {
      // Mirror Scrollable's own wheel handling: pointerScroll clamps,
      // fires the correct notifications, and lets NestedScrollView
      // positions coordinate; reversed axes flip the delta sign.
      final directional = axisDirectionIsReversed(position.axisDirection)
          ? -delta
          : delta;
      if (directional == 0) continue;
      position.pointerScroll(directional);
    }
  }

  List<ScrollPosition> _resolvePositions(MonacoScrollHandoff config) {
    final explicit = config.controller;
    if (explicit != null) {
      if (!explicit.hasClients) return const [];
      return explicit.positions
          .where((position) => position.axis == Axis.vertical)
          .toList();
    }
    if (!config.useNearestScrollable) return const [];
    final position = Scrollable.maybeOf(
      _context(),
      axis: Axis.vertical,
    )?.position;
    if (position == null) return const [];
    return [position];
  }
}
