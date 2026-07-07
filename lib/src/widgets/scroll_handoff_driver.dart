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

  /// Handles one forwarded delta from the editor page.
  void handle(MonacoScrollHandoffDetails details) {
    final config = _config();
    if (!config.isEnabled) return;
    final sourceEnabled = switch (details.source) {
      MonacoScrollHandoffSource.wheel => config.desktopWheel,
      MonacoScrollHandoffSource.touch => config.mobileTouch,
    };
    if (!sourceEnabled) return;

    // The callback sees every raw delta; coalescing below only affects the
    // built-in parent scrolling.
    final onHandoff = config.onHandoff;
    if (onHandoff != null && onHandoff(details)) return;

    if (details.deltaY == 0) return;
    _pendingDelta += details.deltaY;
    _scheduleFlush();
  }

  /// Drops any accumulated delta; call when the controller goes away so a
  /// pending flush cannot scroll on behalf of a dead editor.
  void clearPending() {
    _pendingDelta = 0;
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
