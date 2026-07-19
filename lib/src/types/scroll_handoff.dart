import 'package:flutter/widgets.dart';

/// How unconsumed Monaco scroll input is handed to the Flutter host.
///
/// This is intentionally named "handoff", not "nested scroll": Monaco lives
/// inside a WebView or iframe, so the original platform gesture never enters
/// Flutter's gesture arena. Edge handoff forwards the scroll intent Monaco
/// cannot consume; it does not make the editor a native Flutter scrollable.
enum MonacoScrollHandoffMode {
  /// No handoff. The editor keeps trapping scroll input, matching the
  /// behavior of every release before 2.3.0.
  disabled,

  /// Forward scroll deltas to the Flutter host once the editor cannot
  /// consume them in the requested direction (its scroll edge, or a
  /// non-scrollable document).
  edge,
}

/// The input source that produced a [MonacoScrollHandoffDetails] delta.
enum MonacoScrollHandoffSource {
  /// A mouse wheel or trackpad scroll. The stable, fully supported source.
  wheel,

  /// A touch drag. Experimental: forwarding is observation-only and has no
  /// native momentum or fling transfer.
  touch,
}

/// How gesture ownership is resolved when a scroll gesture meets the
/// editor's scroll boundary.
///
/// The policy decides one thing: whether the *remainder* of a gesture that
/// started inside the editor may spill into the Flutter host once the editor
/// runs out of scroll range. It is applied inside the editor page, before
/// any delta crosses the bridge, so the host never has to guess whether a
/// delta was leftover inertia.
enum MonacoScrollBoundaryPolicy {
  /// Unconsumed deltas chain to the host immediately (the 2.3.0 behavior).
  ///
  /// Fast wheels and trackpad momentum spill into the surrounding page the
  /// instant the editor hits its edge, mid-gesture. Use this only when the
  /// embedding wants Android-style continuous nested-scroll chaining.
  continuous,

  /// The editor keeps every gesture it started; the host gets new gestures
  /// that start at the boundary (the default).
  ///
  /// A gesture (and its whole inertial tail) that reaches the editor's edge
  /// is absorbed there, like a native macOS/iOS nested scroll "wall". To
  /// scroll the surrounding page, the user stops and starts a physically
  /// distinct gesture while the editor is already at its edge; reversing
  /// direction hands the input back to the editor immediately. Forwarded
  /// gestures arrive as begin/update/end sessions (see
  /// [MonacoScrollHandoffDetails.phase]).
  newGestureOnly,
}

/// The position of one [MonacoScrollHandoffDetails] message within a
/// host-owned scroll gesture.
///
/// Only gestures the editor page decided the host owns are sessionized;
/// under [MonacoScrollBoundaryPolicy.continuous] every delta arrives as a
/// standalone [update] with [MonacoScrollHandoffDetails.gestureId] `0`.
enum MonacoScrollHandoffPhase {
  /// The first delta of a host-owned gesture. Carries a payload delta and
  /// resets any pending state from earlier gestures.
  begin,

  /// A continuation delta of the gesture announced by [begin] with the same
  /// [MonacoScrollHandoffDetails.gestureId].
  update,

  /// The gesture ended (quiet period elapsed, direction reversed back into
  /// the editor, or it was superseded). Carries zero deltas; already
  /// accumulated deltas still apply.
  end,

  /// The gesture was cancelled (handoff disabled, policy changed, or touch
  /// forwarding yielded to text selection). Carries zero deltas; the host
  /// drops any deltas of this gesture it has not applied yet.
  cancel,
}

/// One unconsumed scroll intent reported by the editor page.
///
/// Deltas use wheel semantics normalized to pixels: positive [deltaY] means
/// "scroll down". Touch drags are converted to the same convention before
/// they reach Dart. The `at*` flags describe the editor's scroll position at
/// the moment the event fired.
@immutable
class MonacoScrollHandoffDetails {
  /// Creates immutable handoff details.
  const MonacoScrollHandoffDetails({
    required this.source,
    required this.deltaX,
    required this.deltaY,
    required this.atTop,
    required this.atBottom,
    required this.atLeft,
    required this.atRight,
    this.phase = MonacoScrollHandoffPhase.update,
    this.gestureId = 0,
    this.momentum = false,
  });

  /// The input source that produced this delta.
  final MonacoScrollHandoffSource source;

  /// Where this message sits in its gesture's lifecycle.
  ///
  /// Payload deltas arrive as [MonacoScrollHandoffPhase.begin] or
  /// [MonacoScrollHandoffPhase.update]; [MonacoScrollHandoffPhase.end] and
  /// [MonacoScrollHandoffPhase.cancel] close a gesture and carry zero
  /// deltas. Under [MonacoScrollBoundaryPolicy.continuous] every message is
  /// an [MonacoScrollHandoffPhase.update].
  final MonacoScrollHandoffPhase phase;

  /// The page-unique id of the host-owned gesture this message belongs to.
  ///
  /// `0` marks an unsessionized message
  /// ([MonacoScrollBoundaryPolicy.continuous]); sessionized gestures count up
  /// from `1`. The built-in
  /// handoff applies an [MonacoScrollHandoffPhase.update] only while its
  /// gesture is the active one, so a stale delta can never move the host.
  final int gestureId;

  /// Whether the editor page identified this delta as scroll inertia
  /// rather than direct input.
  ///
  /// Only populated where the browser exposes momentum metadata on wheel
  /// events; `false` otherwise. Informational: ownership was already decided
  /// on the editor side.
  final bool momentum;

  /// Horizontal delta in pixels. Reported for completeness; the built-in
  /// handoff applies only [deltaY] in this release.
  final double deltaX;

  /// Vertical delta in pixels. Positive scrolls down, negative scrolls up.
  final double deltaY;

  /// Whether the editor was at its top scroll edge.
  final bool atTop;

  /// Whether the editor was at its bottom scroll edge (including any
  /// `scrollBeyondLastLine` blank space, which counts as editor-scrollable).
  final bool atBottom;

  /// Whether the editor was at its leftmost scroll position.
  final bool atLeft;

  /// Whether the editor was at its rightmost scroll position.
  final bool atRight;

  /// Parses a `scrollHandoff` bridge payload.
  ///
  /// Returns `null` for malformed payloads instead of throwing: an unknown
  /// [source], an unknown [phase], or a missing, non-numeric, or non-finite
  /// delta. Absent or non-boolean edge flags default to `false`. Legacy
  /// payloads without session fields parse as
  /// [MonacoScrollHandoffPhase.update] with [gestureId] `0` and no
  /// [momentum], and a malformed [gestureId] also falls back to `0`.
  static MonacoScrollHandoffDetails? tryParse(Map<String, dynamic> json) {
    final source = switch (json['source']) {
      'wheel' => MonacoScrollHandoffSource.wheel,
      'touch' => MonacoScrollHandoffSource.touch,
      _ => null,
    };
    if (source == null) return null;

    final phase = switch (json['phase']) {
      null => MonacoScrollHandoffPhase.update,
      'begin' => MonacoScrollHandoffPhase.begin,
      'update' => MonacoScrollHandoffPhase.update,
      'end' => MonacoScrollHandoffPhase.end,
      'cancel' => MonacoScrollHandoffPhase.cancel,
      _ => null,
    };
    if (phase == null) return null;

    final deltaX = _finiteDouble(json['deltaX']);
    final deltaY = _finiteDouble(json['deltaY']);
    if (deltaX == null || deltaY == null) return null;

    return MonacoScrollHandoffDetails(
      source: source,
      phase: phase,
      gestureId: _gestureId(json['gestureId']),
      momentum: json['momentum'] == true,
      deltaX: deltaX,
      deltaY: deltaY,
      atTop: json['atTop'] == true,
      atBottom: json['atBottom'] == true,
      atLeft: json['atLeft'] == true,
      atRight: json['atRight'] == true,
    );
  }

  static double? _finiteDouble(Object? value) {
    if (value is! num) return null;
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }

  /// A malformed gesture id degrades to the legacy id `0` (always applied)
  /// rather than dropping the whole payload: losing session tracking is
  /// recoverable, losing scroll deltas is user-visible.
  static int _gestureId(Object? value) {
    if (value is! num || !value.isFinite) return 0;
    final id = value.toInt();
    return id < 0 ? 0 : id;
  }

  @override
  bool operator ==(Object other) {
    return other is MonacoScrollHandoffDetails &&
        other.source == source &&
        other.phase == phase &&
        other.gestureId == gestureId &&
        other.momentum == momentum &&
        other.deltaX == deltaX &&
        other.deltaY == deltaY &&
        other.atTop == atTop &&
        other.atBottom == atBottom &&
        other.atLeft == atLeft &&
        other.atRight == atRight;
  }

  @override
  int get hashCode => Object.hash(
    source,
    phase,
    gestureId,
    momentum,
    deltaX,
    deltaY,
    atTop,
    atBottom,
    atLeft,
    atRight,
  );

  @override
  String toString() {
    return 'MonacoScrollHandoffDetails('
        'source: ${source.name}, '
        'phase: ${phase.name}, gestureId: $gestureId, '
        'momentum: $momentum, '
        'deltaX: $deltaX, deltaY: $deltaY, '
        'atTop: $atTop, atBottom: $atBottom, '
        'atLeft: $atLeft, atRight: $atRight)';
  }
}

/// Configures edge scroll handoff for a `MonacoEditor`.
///
/// Disabled by default. When enabled with [MonacoScrollHandoff.edge], wheel
/// or trackpad input over the editor keeps scrolling Monaco until the editor
/// reaches its scroll edge; scroll gestures the editor cannot consume are
/// forwarded to a Flutter scroll target so the surrounding page continues
/// scrolling. Reversing direction hands the input back to Monaco
/// immediately.
///
/// What happens to the gesture that *reaches* the edge is governed by
/// [policy]. Under the default [MonacoScrollBoundaryPolicy.newGestureOnly],
/// that gesture (and its trackpad momentum) stops dead at the boundary like
/// a native nested scroll view; the host page scrolls only when a new
/// gesture starts while the editor is already at its edge. Under
/// [MonacoScrollBoundaryPolicy.continuous] every unconsumed delta chains to
/// the host immediately, which lets fast scrolls jerk the page.
///
/// The forwarded delta is applied to the first available target:
///
/// 1. [onHandoff], when provided and it returns `true` (the app consumed
///    the delta itself).
/// 2. [controller], when provided (only its vertical scroll positions).
/// 3. The nearest enclosing vertical `Scrollable` above the editor, when
///    [useNearestScrollable] is `true`.
///
/// When no target resolves, the delta is dropped silently.
///
/// ### What edge handoff is not
///
/// This is not native nested scrolling. The gesture itself stays inside the
/// WebView or iframe; only the unconsumed intent crosses the bridge. Wheel
/// and trackpad input feels natural. Touch forwarding ([mobileTouch]) is
/// experimental and has no momentum or fling transfer.
///
/// Ctrl/meta wheel input (editor zoom, browser zoom, macOS pinch) is never
/// handed off, and Monaco-owned overlays that scroll (suggest list, hover,
/// menus, peek editors) keep their own wheel handling.
@immutable
class MonacoScrollHandoff {
  /// Disables scroll handoff entirely (the default).
  ///
  /// No JavaScript listeners are installed and no bridge traffic occurs.
  const MonacoScrollHandoff.disabled()
    : mode = MonacoScrollHandoffMode.disabled,
      controller = null,
      useNearestScrollable = true,
      desktopWheel = true,
      mobileTouch = false,
      policy = MonacoScrollBoundaryPolicy.newGestureOnly,
      onHandoff = null;

  /// Enables edge handoff.
  ///
  /// [desktopWheel] controls the wheel/trackpad source (on by default).
  /// [mobileTouch] additionally opts in to experimental touch forwarding.
  /// [policy] selects the boundary behavior (momentum-absorbing
  /// [MonacoScrollBoundaryPolicy.newGestureOnly] by default). See the class
  /// docs for how the scroll target is resolved from [onHandoff],
  /// [controller], and [useNearestScrollable].
  const MonacoScrollHandoff.edge({
    this.controller,
    this.useNearestScrollable = true,
    this.desktopWheel = true,
    this.mobileTouch = false,
    this.policy = MonacoScrollBoundaryPolicy.newGestureOnly,
    this.onHandoff,
  }) : mode = MonacoScrollHandoffMode.edge;

  /// The active handoff mode.
  final MonacoScrollHandoffMode mode;

  /// How gestures that meet the editor's scroll boundary are owned.
  ///
  /// Defaults to [MonacoScrollBoundaryPolicy.newGestureOnly]: a gesture that
  /// starts inside the editor is absorbed at the edge, momentum included,
  /// and the host scrolls only on a subsequent gesture that starts at the
  /// edge. Set [MonacoScrollBoundaryPolicy.continuous] to restore the 2.3.0
  /// unconsumed-delta chaining.
  final MonacoScrollBoundaryPolicy policy;

  /// Explicit scroll target. Wins over [useNearestScrollable]. Only its
  /// vertical positions receive deltas; horizontal positions are ignored.
  final ScrollController? controller;

  /// Whether to fall back to `Scrollable.maybeOf(context, axis: vertical)`
  /// when [controller] is null. Defaults to `true`.
  final bool useNearestScrollable;

  /// Whether wheel/trackpad deltas are forwarded. Defaults to `true` when
  /// edge handoff is enabled.
  final bool desktopWheel;

  /// Whether touch-drag deltas are forwarded. Experimental; defaults to
  /// `false`. Forwarding is observation-only: it never blocks Monaco's own
  /// touch handling, never opens the keyboard, and yields to text selection.
  final bool mobileTouch;

  /// Called for every forwarded delta before the built-in scrolling.
  ///
  /// Return `true` to consume the delta (the built-in target resolution is
  /// skipped for that event). Return `false` to let the default handling
  /// run.
  final bool Function(MonacoScrollHandoffDetails details)? onHandoff;

  /// Whether edge handoff is enabled at all.
  bool get isEnabled => mode == MonacoScrollHandoffMode.edge;

  /// Whether the wheel source should emit events.
  bool get wheelSourceEnabled => isEnabled && desktopWheel;

  /// Whether the experimental touch source should emit events.
  bool get touchSourceEnabled => isEnabled && mobileTouch;
}
