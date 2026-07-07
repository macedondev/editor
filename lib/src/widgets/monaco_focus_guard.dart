import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

/// A tiny, no-UI helper that reasserts Monaco focus on common desktop events.
///
/// - Calls [MonacoController.requestFocus] when the app is resumed.
/// - Optionally subscribes to the current [PageRoute] via a [RouteObserver]
///   and re-focuses when the route becomes visible again (didPopNext).
///
/// This is an optional utility for desktop apps that frequently switch routes
/// or windows. Place it near your editor once you have the controller.
class MonacoFocusGuard extends StatefulWidget {
  /// Creates a [MonacoFocusGuard] widget.
  const MonacoFocusGuard({
    super.key,
    required this.controller,
    this.routeObserver,
    this.modalRouteObserver,
    this.ensureAttempts = 3,
    this.autoDisableInteraction = true,
  });

  /// The [MonacoController] for the editor that needs focus management.
  final MonacoController controller;

  /// An optional [RouteObserver] to listen for route changes.
  ///
  /// If provided, the guard will re-focus the editor when the current route
  /// becomes visible again (e.g., after a `pop`).
  final RouteObserver<PageRoute<dynamic>>? routeObserver;

  /// An optional [RouteObserver] for [ModalRoute] (dialogs, menus, popups).
  ///
  /// If set, this is preferred over [routeObserver] and allows the guard to
  /// react to popup routes like `showDialog` and `showMenu`.
  final RouteObserver<ModalRoute<dynamic>>? modalRouteObserver;

  /// The number of times to attempt to focus the editor.
  ///
  /// Defaults to 3 attempts.
  final int ensureAttempts;

  /// If `true`, automatically disables editor interaction when a new route
  /// is pushed on top and re-enables it when the current route is returned to.
  ///
  /// This is useful for ensuring Flutter dialogs and menus remain interactive
  /// over the Monaco editor on Web. Requires [modalRouteObserver] for dialogs
  /// and menus, or [routeObserver] for page routes.
  final bool autoDisableInteraction;

  @override
  State<MonacoFocusGuard> createState() => _MonacoFocusGuardState();
}

class _MonacoFocusGuardState extends State<MonacoFocusGuard>
    with WidgetsBindingObserver, RouteAware {
  PageRoute<dynamic>? _route;
  RouteObserver<PageRoute<dynamic>>? _routeObserver;
  ModalRoute<dynamic>? _modalRoute;
  RouteObserver<ModalRoute<dynamic>>? _modalRouteObserver;
  bool _interactionToggledByGuard = false;
  bool _interactionWasEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.modalRouteObserver != _modalRouteObserver) {
      if (_modalRouteObserver != null && _modalRoute != null) {
        _modalRouteObserver!.unsubscribe(this);
      }
      _modalRouteObserver = widget.modalRouteObserver;
      _modalRoute = null;
    }
    if (widget.routeObserver != _routeObserver) {
      if (_routeObserver != null && _route != null) {
        _routeObserver!.unsubscribe(this);
      }
      _routeObserver = widget.routeObserver;
      _route = null;
    }

    if (_modalRouteObserver != null) {
      final route = ModalRoute.of(context);
      if (route != null && route != _modalRoute) {
        if (_modalRoute != null) {
          _modalRouteObserver!.unsubscribe(this);
        }
        _modalRoute = route;
        _modalRouteObserver!.subscribe(this, route);
      }
      return;
    }

    if (_routeObserver != null) {
      final route = ModalRoute.of(context);
      if (route is PageRoute<dynamic> && route != _route) {
        if (_route != null) {
          _routeObserver!.unsubscribe(this);
        }
        _route = route;
        _routeObserver!.subscribe(this, route);
      }
    }

    if (widget.autoDisableInteraction &&
        widget.modalRouteObserver == null &&
        widget.routeObserver == null) {
      debugPrint(
        '⚠️ [MonacoFocusGuard] autoDisableInteraction is enabled but no route observer was provided. '
        'Pass a MonacoRouteObserver to handle web overlays automatically.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserver != null && _route != null) {
      _routeObserver!.unsubscribe(this);
    }
    if (_modalRouteObserver != null && _modalRoute != null) {
      _modalRouteObserver!.unsubscribe(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.requestFocus(attempts: widget.ensureAttempts);
    }
  }

  @override
  void didPushNext() {
    if (!widget.autoDisableInteraction) return;
    if (_interactionToggledByGuard) return;
    _interactionWasEnabled = widget.controller.isInteractionEnabled;
    if (!_interactionWasEnabled) return;
    _interactionToggledByGuard = true;
    widget.controller.setInteractionEnabled(false);
  }

  @override
  void didPopNext() {
    if (widget.autoDisableInteraction && _interactionToggledByGuard) {
      _interactionToggledByGuard = false;
      widget.controller.setInteractionEnabled(_interactionWasEnabled);
    }
    widget.controller.requestFocus(attempts: widget.ensureAttempts);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
