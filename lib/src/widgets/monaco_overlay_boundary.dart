import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/src/platform/overlay_shield/overlay_shield.dart';

/// Marks a Flutter widget subtree as a static overlay above Monaco on Web.
///
/// On Flutter Web, Monaco runs inside an `<iframe>` registered via
/// `HtmlElementView`. The browser routes pointer events into the iframe
/// before Flutter sees them, so static overlays (FABs, in-tree stacked
/// widgets, custom panels) appear visible but are unclickable.
///
/// Wrap such overlays with [MonacoOverlayBoundary]. On web, this creates
/// a transparent DOM shield over the widget's global bounds and disables
/// pointer events on any intersecting Monaco iframe while the user is
/// hovering or pressing the overlay. On native platforms this is a no-op
/// wrapper.
///
/// For route-based overlays (dialogs, popup menus, dropdown menus, modal
/// bottom sheets), keep using `MonacoFocusGuard` with a
/// `MonacoRouteObserver` - that path was already correct and remains
/// the recommended fix for `ModalRoute`s.
///
/// Most apps will not construct this directly. `MonacoScaffold` wraps
/// the common Scaffold overlay slots automatically.
class MonacoOverlayBoundary extends StatefulWidget {
  /// Create an overlay boundary that protects [child] from being swallowed by
  /// Monaco iframes underneath on web.
  const MonacoOverlayBoundary({
    super.key,
    required this.child,
    this.enabled = true,
    this.debug = false,
    this.margin = EdgeInsets.zero,
  });

  /// The overlay widget that should be reachable on web.
  final Widget child;

  /// Disables the DOM shield entirely (useful when you know there is no
  /// editor underneath, or to opt out of the overlay protection).
  final bool enabled;

  /// Renders the shield as a translucent green rectangle on web. Useful when
  /// validating that the shield's rect matches the visible overlay bounds.
  final bool debug;

  /// Expands the shield rect beyond the child's measured bounds. Use sparingly;
  /// large margins lock more editor area than necessary.
  final EdgeInsetsGeometry margin;

  @override
  State<MonacoOverlayBoundary> createState() => _MonacoOverlayBoundaryState();
}

class _MonacoOverlayBoundaryState extends State<MonacoOverlayBoundary>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  MonacoOverlayDomShield? _shield;
  Ticker? _ticker;
  int? _flutterViewId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (MonacoOverlayDomShield.isSupported) {
      _ticker = createTicker((_) => _syncShield());
      _ticker!.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _flutterViewId = View.of(context).viewId;
    _ensureShield();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant MonacoOverlayBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.debug != widget.debug ||
        oldWidget.enabled != widget.enabled) {
      _disposeShield();
      _ensureShield();
    }

    _scheduleSync();
  }

  @override
  void didChangeMetrics() {
    _scheduleSync();
  }

  @override
  Widget build(BuildContext context) {
    _ensureShield();
    _scheduleSync();
    return widget.child;
  }

  void _ensureShield() {
    if (!MonacoOverlayDomShield.isSupported) return;
    if (!widget.enabled) return;
    if (_shield != null) return;

    final viewId = _flutterViewId;
    if (viewId == null) return;

    _shield = MonacoOverlayDomShield(
      flutterViewId: viewId,
      debug: widget.debug,
    );
  }

  void _scheduleSync() {
    if (!MonacoOverlayDomShield.isSupported) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncShield();
    });
  }

  void _syncShield() {
    final shield = _shield;
    if (shield == null) return;

    if (!mounted || !widget.enabled) {
      shield.update(Rect.zero);
      return;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize ||
        renderObject.size.width <= 0 ||
        renderObject.size.height <= 0) {
      shield.update(Rect.zero);
      return;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    var rect = topLeft & renderObject.size;

    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final margin = widget.margin.resolve(textDirection);

    rect = Rect.fromLTRB(
      rect.left - margin.left,
      rect.top - margin.top,
      rect.right + margin.right,
      rect.bottom + margin.bottom,
    );

    shield.update(rect);
  }

  void _disposeShield() {
    _shield?.dispose();
    _shield = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.dispose();
    _ticker = null;
    _disposeShield();
    super.dispose();
  }
}
