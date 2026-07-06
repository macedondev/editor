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
  });

  /// The input source that produced this delta.
  final MonacoScrollHandoffSource source;

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
  /// [source], or a missing, non-numeric, or non-finite delta. Absent or
  /// non-boolean edge flags default to `false`.
  static MonacoScrollHandoffDetails? tryParse(Map<String, dynamic> json) {
    final source = switch (json['source']) {
      'wheel' => MonacoScrollHandoffSource.wheel,
      'touch' => MonacoScrollHandoffSource.touch,
      _ => null,
    };
    if (source == null) return null;

    final deltaX = _finiteDouble(json['deltaX']);
    final deltaY = _finiteDouble(json['deltaY']);
    if (deltaX == null || deltaY == null) return null;

    return MonacoScrollHandoffDetails(
      source: source,
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

  @override
  bool operator ==(Object other) {
    return other is MonacoScrollHandoffDetails &&
        other.source == source &&
        other.deltaX == deltaX &&
        other.deltaY == deltaY &&
        other.atTop == atTop &&
        other.atBottom == atBottom &&
        other.atLeft == atLeft &&
        other.atRight == atRight;
  }

  @override
  int get hashCode =>
      Object.hash(source, deltaX, deltaY, atTop, atBottom, atLeft, atRight);

  @override
  String toString() {
    return 'MonacoScrollHandoffDetails('
        'source: ${source.name}, '
        'deltaX: $deltaX, deltaY: $deltaY, '
        'atTop: $atTop, atBottom: $atBottom, '
        'atLeft: $atLeft, atRight: $atRight)';
  }
}

/// Configures edge scroll handoff for a `MonacoEditor`.
///
/// Disabled by default. When enabled with [MonacoScrollHandoff.edge], wheel
/// or trackpad input over the editor keeps scrolling Monaco until the editor
/// reaches its scroll edge; deltas the editor cannot consume are forwarded
/// to a Flutter scroll target so the surrounding page continues scrolling.
/// Reversing direction hands the input back to Monaco immediately.
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
      onHandoff = null;

  /// Enables edge handoff.
  ///
  /// [desktopWheel] controls the wheel/trackpad source (on by default).
  /// [mobileTouch] additionally opts in to experimental touch forwarding.
  /// See the class docs for how the scroll target is resolved from
  /// [onHandoff], [controller], and [useNearestScrollable].
  const MonacoScrollHandoff.edge({
    this.controller,
    this.useNearestScrollable = true,
    this.desktopWheel = true,
    this.mobileTouch = false,
    this.onHandoff,
  }) : mode = MonacoScrollHandoffMode.edge;

  /// The active handoff mode.
  final MonacoScrollHandoffMode mode;

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
