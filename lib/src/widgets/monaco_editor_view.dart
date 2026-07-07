import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/widgets/monaco_status_bar.dart';
import 'package:flutter_monaco/src/widgets/scroll_handoff_driver.dart';

/// An enumeration representing the connection state of the Monaco Editor.
enum _ConnectionState {
  /// The editor is currently initializing and not yet ready for interaction.
  connecting,

  /// The editor has successfully initialized and is ready.
  ready,

  /// An error occurred during the initialization of the editor.
  error,
}

bool _pointerMayClaimKeyboard(PointerDownEvent event) {
  if (event.kind == PointerDeviceKind.mouse ||
      event.kind == PointerDeviceKind.trackpad) {
    return event.buttons == kPrimaryMouseButton;
  }
  return true;
}

bool _pointerShouldRecoverInputFocus(
  PointerDownEvent event, {
  required bool hasFlutterFocus,
  required bool monacoReportsFocused,
  TargetPlatform? platform,
}) {
  if (!_pointerMayClaimKeyboard(event)) return false;
  final targetPlatform = platform ?? defaultTargetPlatform;
  if (targetPlatform == TargetPlatform.macOS) {
    // macOS focus signals cannot be trusted for the skip decision: the
    // WKWebView can silently lose NSWindow first-responder status while both
    // the Flutter focus node and Monaco's DOM focus still read `true`. Every
    // primary click therefore routes a user focus intent; the controller
    // verifies real first-responder state through the native plugin, so a
    // fresh editor costs one no-op channel query, not a focus replay.
    return true;
  }
  // Windows/Linux: re-assert focus only when a signal says it is lost.
  // Replaying focus on an already-focused editor flickers the caret and can
  // tear down Monaco's context menu.
  return !hasFlutterFocus || !monacoReportsFocused;
}

/// A widget that renders a Monaco Editor instance.
///
/// This widget manages the lifecycle of the underlying WebView and the [MonacoController].
/// It handles initialization, resizing, and exposes callbacks for editor events.
///
/// ### Behavior
/// * **Initialization**: Displays [loadingBuilder] (or a spinner) until the editor is ready.
/// * **Updates**: Rebuilds when [options] change, applying the new configuration dynamically.
/// * **Error Handling**: Displays [errorBuilder] (or an error message) if initialization fails.
///
/// ### Example
///
/// ```dart
/// MonacoEditor(
///   initialValue: 'print("Hello World");',
///   options: EditorOptions(
///     language: MonacoLanguage.python,
///     theme: MonacoTheme.vsDark,
///   ),
///   onContentChanged: (value) => print('New content: $value'),
/// )
/// ```
class MonacoEditor extends StatefulWidget {
  /// Creates a new [MonacoEditor] widget.
  const MonacoEditor({
    super.key,
    this.controller,
    this.controllerFactory,
    this.initialText,
    this.options = const EditorOptions(),
    this.initialSelection,
    this.autofocus = false,
    this.page = const MonacoPageConfig(),
    this.readyTimeout = MonacoDefaults.readyTimeout,
    this.onReady,
    this.onError,
    this.onContentChanged,
    this.onRawContentChanged,
    this.fullTextOnFlushOnly = false,
    this.contentDebounce = const Duration(milliseconds: 120),
    this.onSelectionChanged,
    this.onFocus,
    this.onBlur,
    this.onLiveStats,
    this.loadingBuilder,
    this.errorBuilder,
    this.showStatusBar = false,
    this.statusBarBuilder,
    this.backgroundColor,
    this.interactionEnabled = true,
    this.padding,
    this.constraints,
    this.scrollHandoff = const MonacoScrollHandoff.disabled(),
  });

  /// The controller that manages the editor instance.
  ///
  /// If provided, you are responsible for disposing of it.
  /// If `null`, a controller is created and managed internally by this widget.
  final MonacoController? controller;

  /// Test-only hook to supply a controller factory when this widget
  /// owns the controller lifecycle.
  @visibleForTesting
  final Future<MonacoController> Function()? controllerFactory;

  /// The initial content to load into the editor.
  ///
  /// Applied only when the editor is first created (it rides the boot
  /// command and paints in the first frame). To update content
  /// dynamically, use `controller.document.setText`.
  final String? initialText;

  /// Configuration options for the editor (theme, language, font size, etc.).
  ///
  /// Changing this property will dynamically update the editor instance.
  final EditorOptions options;

  /// The text range to select immediately after initialization.
  final Range? initialSelection;

  /// If `true`, the editor requests focus as soon as it becomes ready.
  final bool autofocus;

  /// Page-level settings (custom CSS, CSP opt-ins such as CDN fonts and
  /// WebSocket language-server origins). Only used when this widget owns
  /// the controller (no [controller] supplied). Changing this property
  /// triggers a full reload of the editor.
  final MonacoPageConfig page;

  /// The maximum duration to wait for the editor to initialize before
  /// showing an error.
  ///
  /// Defaults to [MonacoDefaults.readyTimeout]: 20s on native platforms
  /// (local assets, so expiry means a hung boot) and 90s on web, where the
  /// cold-cache first load must download the multi-megabyte editor bundle
  /// and is bound by bandwidth, not by a hang. Hard failures surface
  /// immediately regardless of this deadline.
  final Duration readyTimeout;

  /// Callback invoked when the editor is fully initialized and ready.
  ///
  /// Provides the [MonacoController] for interaction.
  final ValueChanged<MonacoController>? onReady;

  /// Callback invoked when a background editor operation fails.
  ///
  /// The widget performs bridge work outside any caller's await chain
  /// (pulling text for [onContentChanged], re-applying [options], syncing
  /// scroll handoff). Failures in that work land here. When `null`, they
  /// are reported to [FlutterError.reportError] instead of being silently
  /// swallowed. Boot failures render [errorBuilder] and are also routed
  /// through this callback.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Callback invoked when the text content changes.
  ///
  /// This is debounced by [contentDebounce] unless it's a "flush" event (e.g., `setValue`).
  final ValueChanged<String>? onContentChanged;

  /// Callback invoked for every content change signal from Monaco.
  ///
  /// The boolean argument is `true` if the change was a "flush" (full replacement).
  final ValueChanged<bool>? onRawContentChanged;

  /// If `true`, [onContentChanged] is only called for "flush" events, ignoring typing.
  final bool fullTextOnFlushOnly;

  /// The delay before [onContentChanged] is triggered after the user stops typing.
  final Duration contentDebounce;

  /// Callback invoked when the cursor selection changes.
  final ValueChanged<Range?>? onSelectionChanged;

  /// Callback invoked when the editor gains focus.
  final VoidCallback? onFocus;

  /// Callback invoked when the editor loses focus.
  final VoidCallback? onBlur;

  /// Callback for receiving real-time editor statistics (cursor position, line count).
  final ValueChanged<MonacoLiveStats>? onLiveStats;

  /// Builder for the widget displayed while the editor is initializing.
  ///
  /// Defaults to a [CircularProgressIndicator].
  final WidgetBuilder? loadingBuilder;

  /// Builder for the widget displayed if initialization fails.
  ///
  /// Defaults to an error icon and retry button.
  final Widget Function(BuildContext context, Object error, StackTrace? st)?
  errorBuilder;

  /// If `true`, displays a status bar with line/column info at the bottom.
  final bool showStatusBar;

  /// Builder for a custom status bar widget.
  final Widget Function(BuildContext context, MonacoLiveStats stats)?
  statusBarBuilder;

  /// The background color of the WebView container.
  ///
  /// Visible while the editor is loading or if the editor has padding.
  final Color? backgroundColor;

  /// Whether the editor intercepts pointer events.
  ///
  /// Set this to `false` when displaying Flutter overlays (dialogs, dropdowns)
  /// over the editor on Web to ensure the overlays receive pointer events.
  final bool interactionEnabled;

  /// Padding applied around the editor WebView.
  final EdgeInsetsGeometry? padding;

  /// Constraints applied to the editor container.
  final BoxConstraints? constraints;

  /// Edge scroll handoff configuration. Disabled by default.
  ///
  /// When set to [MonacoScrollHandoff.edge], wheel or trackpad input over
  /// the editor scrolls Monaco until it reaches its scroll edge; deltas the
  /// editor cannot consume then scroll the configured target (an explicit
  /// [MonacoScrollHandoff.controller] or the nearest enclosing vertical
  /// scrollable). Reversing direction hands input back to Monaco.
  ///
  /// This is edge handoff, not native nested scrolling; see
  /// [MonacoScrollHandoff] for the exact behavior, target resolution, and
  /// the experimental [MonacoScrollHandoff.mobileTouch] source.
  final MonacoScrollHandoff scrollHandoff;

  /// Creates the mutable state for this widget.
  @override
  State<MonacoEditor> createState() => _MonacoEditorState();
}

class _MonacoEditorState extends State<MonacoEditor> {
  /// The current state of the editor connection.
  _ConnectionState _connectionState = _ConnectionState.connecting;

  /// The controller for the editor. Can be external or internal.
  MonacoController? _controller;

  /// `true` if this widget is responsible for creating and disposing the controller.
  bool _ownsController = false;

  /// Holds any error that occurred during bootstrap.
  Object? _error;
  StackTrace? _stack;

  /// Subscriptions to controller events to be managed across the widget lifecycle.
  final List<StreamSubscription<dynamic>> _streamSubscriptions = [];
  StreamSubscription<MonacoContentChanged>? _contentSub;
  VoidCallback? _statsListener;

  /// Content sequence number for race condition prevention.
  int _contentSeq = 0;

  /// Bootstrap sequence number to ignore stale async work.
  int _bootstrapSeq = 0;

  /// Timer for debouncing content changes.
  Timer? _contentDebounceTimer;

  /// FocusNode to explicitly request platform view focus for the WebView.
  final FocusNode _webFocusNode = FocusNode(debugLabel: 'MonacoWebViewFocus');

  /// Whether Monaco itself reports DOM focus, driven by the controller's
  /// focus/blur stream. On macOS this is not proof that WKWebView is still
  /// native input-ready.
  bool _monacoReportsFocused = false;

  /// Applies forwarded scroll deltas to the configured Flutter target
  /// (shared with `MonacoDiffEditor`).
  late final ScrollHandoffDriver _scrollHandoffDriver = ScrollHandoffDriver(
    config: () => widget.scrollHandoff,
    context: () => context,
    isMounted: () => mounted,
  );

  /// The handoff sources last pushed to the editor page, so config rebuilds
  /// only produce bridge traffic when the effective sources change.
  bool _syncedWheelSource = false;
  bool _syncedTouchSource = false;

  /// The theme most recently pushed to the editor, so ambient brightness
  /// changes (D27) only produce bridge traffic when the resolved theme
  /// actually flips.
  MonacoTheme? _appliedResolvedTheme;

  bool _bootstrappedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The first bootstrap runs here, not in initState: resolving a null
    // options.theme (D27) reads Theme.of(context), which the framework
    // forbids before initState completes.
    if (!_bootstrappedOnce) {
      _bootstrappedOnce = true;
      _bootstrap();
      return;
    }
    // D27: a null options.theme follows the surrounding brightness, so an
    // ambient Theme change (e.g. the platform dark-mode toggle) re-resolves
    // it. An explicit theme never reacts to brightness.
    if (widget.options.theme != null) return;
    if (_connectionState != _ConnectionState.ready || _controller == null) {
      return;
    }
    final resolved = _resolveTheme();
    if (resolved == _appliedResolvedTheme) return;
    _appliedResolvedTheme = resolved;
    _ignoreAsync(_controller!.setTheme(resolved));
  }

  @override
  void didUpdateWidget(covariant MonacoEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the controller is swapped externally, we need to re-bootstrap.
    if (oldWidget.controller != widget.controller) {
      _teardown(disposeOldController: _ownsController);
      _bootstrap();
      return;
    }

    // If we OWN the controller and HTML-affecting knobs changed, rebuild.
    final htmlKnobsChanged = oldWidget.page != widget.page;
    if (_ownsController && htmlKnobsChanged) {
      _teardown(disposeOldController: true);
      _bootstrap();
      return;
    }

    if (widget.interactionEnabled != oldWidget.interactionEnabled &&
        _controller != null) {
      _ignoreAsync(
        _controller!.setInteractionEnabled(widget.interactionEnabled),
      );
    }

    if (widget.scrollHandoff != oldWidget.scrollHandoff) {
      // Identity compare is enough: the sync method dedupes against the
      // last pushed source flags, so rebuilds with equivalent configs are
      // free.
      _syncScrollHandoffSources();
    }

    if (_connectionState != _ConnectionState.ready || _controller == null) {
      return;
    }

    // If options change, apply only the fields that actually differ
    // (sparse diff: unchanged fields are never re-sent, so Monaco state
    // adjusted elsewhere is not clobbered).
    if (widget.options != oldWidget.options) {
      final diff = _diffOptions(oldWidget.options, widget.options);
      if (diff.toMonacoOptions().isNotEmpty) {
        _ignoreAsync(_controller!.updateOptions(diff));
      }
      if (widget.options.theme != oldWidget.options.theme) {
        final resolvedTheme = _resolveTheme();
        _appliedResolvedTheme = resolvedTheme;
        _ignoreAsync(_controller!.setTheme(resolvedTheme));
      }
      final language = widget.options.language;
      if (language != null && language != oldWidget.options.language) {
        _ignoreAsync(_controller!.document.setLanguage(language));
      }
    }

    if (widget.backgroundColor != oldWidget.backgroundColor &&
        widget.backgroundColor != null) {
      _ignoreAsync(_controller!.setBackgroundColor(widget.backgroundColor!));
      _ignoreAsync(
        _controller!.setHostPageBackgroundColor(widget.backgroundColor!),
      );
    }

    // If the content change callback has been updated, we need to rewire the listener.
    if (widget.onContentChanged != oldWidget.onContentChanged) {
      _wireContentListener();
    }
  }

  /// Initializes the editor controller and sets up listeners.
  Future<void> _bootstrap() async {
    final bootstrapToken = ++_bootstrapSeq;
    setState(() {
      _connectionState = _ConnectionState.connecting;
      _error = null;
      _stack = null;
    });

    try {
      final ownsController = widget.controller == null;
      _ownsController = ownsController;
      // Only the internal create path carries initialValue/options into the
      // boot command; external controllers and factories get them applied
      // after readiness below.
      final usedInternalCreate =
          widget.controller == null && widget.controllerFactory == null;
      final bootTheme = _resolveTheme();
      _appliedResolvedTheme = bootTheme;
      final controller =
          widget.controller ??
          await (widget.controllerFactory?.call() ??
              MonacoController.create(
                options: widget.options.copyWith(theme: bootTheme),
                initialText: widget.initialText,
                page: widget.page,
                readyTimeout: widget.readyTimeout,
              ));

      if (!_isBootstrapCurrent(bootstrapToken)) {
        if (ownsController) {
          controller.dispose();
        }
        return;
      }

      setState(() => _controller = controller);
      _ownsController = ownsController;

      await _controller!.setInteractionEnabled(widget.interactionEnabled);
      if (!_isBootstrapCurrent(bootstrapToken)) {
        return;
      }

      // Wait for the underlying web view to be ready.
      await _controller!.whenReady;
      if (!_isBootstrapCurrent(bootstrapToken)) {
        return;
      }

      // Apply initial values and settings post-readiness. Background is
      // cosmetic - the widget already paints its own container behind the
      // WebView - so a platform failure here must not abort initialization.
      // The split exists because macOS native backgrounds are unreliable;
      // both layers can fail independently.
      if (widget.backgroundColor != null) {
        try {
          await _controller!.setBackgroundColor(widget.backgroundColor!);
        } catch (e) {
          debugPrint('[MonacoEditor] setBackgroundColor failed: $e');
        }
        try {
          await _controller!.setHostPageBackgroundColor(
            widget.backgroundColor!,
          );
        } catch (e) {
          debugPrint('[MonacoEditor] setHostPageBackgroundColor failed: $e');
        }
      }
      // The internal create path boots the editor with options, theme,
      // language, and initial text already applied (two-phase boot); only
      // externally supplied controllers need them applied here.
      if (!usedInternalCreate && _isBootstrapCurrent(bootstrapToken)) {
        await _controller!.updateOptions(widget.options);
        final resolvedTheme = _resolveTheme();
        _appliedResolvedTheme = resolvedTheme;
        await _controller!.setTheme(resolvedTheme);
        final language = widget.options.language;
        if (language != null) {
          await _controller!.document.setLanguage(language);
        }
        if (widget.initialText != null) {
          await _controller!.document.setText(widget.initialText!);
        }
        if (!_isBootstrapCurrent(bootstrapToken)) {
          return;
        }
      }
      if (widget.initialSelection != null) {
        await _controller!.setSelection(widget.initialSelection!);
        if (!_isBootstrapCurrent(bootstrapToken)) {
          return;
        }
      }
      if (widget.autofocus &&
          widget.interactionEnabled &&
          !_isMobileInputPlatform()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isBootstrapCurrent(bootstrapToken)) return;
          _webFocusNode.requestFocus();
          unawaited(_controller!.requestFocus());
        });
      }

      _wireListeners();
      _syncScrollHandoffSources();

      if (_isBootstrapCurrent(bootstrapToken)) {
        setState(() => _connectionState = _ConnectionState.ready);
        widget.onReady?.call(_controller!);
      }
    } catch (e, st) {
      if (!_isBootstrapCurrent(bootstrapToken)) return;
      widget.onError?.call(e, st);
      _teardown(disposeOldController: _ownsController);
      setState(() {
        _connectionState = _ConnectionState.error;
        _error = e;
        _stack = st;
      });
    }
  }

  bool _isBootstrapCurrent(int token) => mounted && token == _bootstrapSeq;

  bool _isMobileInputPlatform() {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// The sparse difference between two option sets: only keys whose
  /// serialized value changed survive. Fields that went from set to unset
  /// cannot be "un-applied" and are dropped (Monaco keeps the last value).
  static EditorOptions _diffOptions(EditorOptions before, EditorOptions after) {
    final beforeJson = before.toJson();
    final afterJson = after.toJson();
    final diff = <String, dynamic>{};
    for (final entry in afterJson.entries) {
      if (!_jsonEquals(beforeJson[entry.key], entry.value)) {
        diff[entry.key] = entry.value;
      }
    }
    return EditorOptions.fromJson(diff);
  }

  static bool _jsonEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Resolves the effective theme: an explicit [MonacoEditor.options] theme
  /// always wins; a null theme follows the surrounding Flutter brightness.
  MonacoTheme _resolveTheme() {
    final explicit = widget.options.theme;
    if (explicit != null) return explicit;
    final brightness = mounted ? Theme.of(context).brightness : Brightness.dark;
    return brightness == Brightness.dark
        ? MonacoDefaults.darkTheme
        : MonacoDefaults.lightTheme;
  }

  /// Subscribes to all relevant event streams from the controller.
  void _wireListeners() {
    if (_controller == null) return;

    // Clear any existing subscriptions before wiring new ones.
    _teardownListeners();

    _wireContentListener();
    if (widget.onSelectionChanged != null) {
      final selectionSub = _controller!.onSelectionChanged.listen(
        (r) => widget.onSelectionChanged?.call(r),
      );
      _streamSubscriptions.add(selectionSub);
    }
    final focusSub = _controller!.onFocusChanged.listen((focused) {
      _monacoReportsFocused = focused;
      if (focused) {
        widget.onFocus?.call();
      } else {
        widget.onBlur?.call();
      }
    });
    _streamSubscriptions.add(focusSub);

    final scrollHandoffSub = _controller!.onScrollHandoff.listen(
      _scrollHandoffDriver.handle,
    );
    _streamSubscriptions.add(scrollHandoffSub);

    _statsListener = () => widget.onLiveStats?.call(_controller!.stats.value);
    _controller!.stats.addListener(_statsListener!);
  }

  void _ignoreAsync(Future<void> future) {
    unawaited(
      future.catchError((Object e, StackTrace st) {
        _reportAsyncError(e, st);
      }),
    );
  }

  /// Routes a background failure to [MonacoEditor.onError], falling back to
  /// [FlutterError.reportError] so nothing disappears silently.
  void _reportAsyncError(Object error, StackTrace stackTrace) {
    final handler = widget.onError;
    if (handler != null) {
      handler(error, stackTrace);
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'flutter_monaco',
        context: ErrorDescription('while running a MonacoEditor update'),
      ),
    );
  }

  /// Pushes the desired handoff sources to the editor page when they differ
  /// from what was last pushed. A disabled config therefore produces no
  /// bridge traffic at all.
  void _syncScrollHandoffSources() {
    final controller = _controller;
    if (controller == null) return;
    final wheel = widget.scrollHandoff.wheelSourceEnabled;
    final touch = widget.scrollHandoff.touchSourceEnabled;
    if (wheel == _syncedWheelSource && touch == _syncedTouchSource) return;
    _syncedWheelSource = wheel;
    _syncedTouchSource = touch;
    _ignoreAsync(
      controller.setScrollHandoffSources(wheel: wheel, touch: touch),
    );
  }

  /// Wires only the content changed listener, allowing it to be updated separately.
  void _wireContentListener() {
    // Cancel any previous content subscription first.
    _contentSub?.cancel();
    _contentSub = null;

    _contentSub = _controller!.onContentChanged.listen((event) {
      final isFlush = event.isFlush;
      // 1) Always surface raw signal if requested.
      widget.onRawContentChanged?.call(isFlush);

      // 2) Nothing else to do?
      if (widget.onContentChanged == null) return;
      if (widget.fullTextOnFlushOnly && !isFlush) return;

      // 3) Flush = immediate fetch (no debounce), else debounced.
      Future<void> pullAndEmit() async {
        final seq = ++_contentSeq;
        final text = await _controller!.document.getText();
        if (!mounted || seq != _contentSeq) return; // drop stale
        widget.onContentChanged!(text);
      }

      if (isFlush) {
        _contentDebounceTimer?.cancel();
        _ignoreAsync(pullAndEmit());
        return;
      }

      _contentDebounceTimer?.cancel();
      _contentDebounceTimer = Timer(
        widget.contentDebounce,
        () => _ignoreAsync(pullAndEmit()),
      );
    });
  }

  /// Cancels all active event subscriptions.
  void _teardownListeners() {
    for (final sub in _streamSubscriptions) {
      sub.cancel();
    }
    _streamSubscriptions.clear();

    _contentSub?.cancel();
    _contentSub = null;

    _contentDebounceTimer?.cancel();
    _contentDebounceTimer = null;

    if (_controller != null && _statsListener != null) {
      _controller!.stats.removeListener(_statsListener!);
      _statsListener = null;
    }
  }

  /// Cleans up all resources, including listeners and the controller if owned.
  void _teardown({required bool disposeOldController}) {
    _teardownListeners();
    final controller = _controller;
    if (controller != null &&
        !disposeOldController &&
        (_syncedWheelSource || _syncedTouchSource)) {
      // The external controller outlives this widget: stop the page from
      // posting handoff events nobody consumes.
      _ignoreAsync(controller.setScrollHandoffSources());
    }
    _syncedWheelSource = false;
    _syncedTouchSource = false;
    _scrollHandoffDriver.clearPending();
    _appliedResolvedTheme = null;
    if (disposeOldController) {
      controller?.dispose();
    }
    _controller = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        widget.backgroundColor ??
        (theme.brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white);

    return Container(
      color: bg,
      constraints: widget.constraints,
      padding: widget.padding,
      child: _buildChild(context),
    );
  }

  /// Builds the main content based on the current connection state.
  Widget _buildChild(BuildContext context) {
    // No controller yet - show loading or error
    if (_controller == null) {
      if (_connectionState == _ConnectionState.error) {
        return widget.errorBuilder?.call(context, _error!, _stack) ??
            MonacoDefaultError(
              error: _error!,
              onRetry: _ownsController ? _bootstrap : null,
            );
      }
      return widget.loadingBuilder?.call(context) ??
          const MonacoDefaultLoading();
    }

    // On mobile, let the WebView own the full tap-to-keyboard chain.
    // Flutter's Focus/Listener wrapper steals the gesture context, which
    // causes the OS to refuse the soft keyboard.
    final isMobileInputPlatform = _isMobileInputPlatform();

    final Widget webView;
    if (isMobileInputPlatform) {
      webView = SizedBox.expand(child: _controller!.webViewWidget);
    } else {
      webView = SizedBox.expand(
        child: Focus(
          focusNode: _webFocusNode,
          canRequestFocus: widget.interactionEnabled,
          autofocus: widget.autofocus && widget.interactionEnabled,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent) {
              return KeyEventResult.skipRemainingHandlers;
            }
            return KeyEventResult.ignored;
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (!widget.interactionEnabled) return;
              if (!_pointerShouldRecoverInputFocus(
                event,
                hasFlutterFocus: _webFocusNode.hasFocus,
                monacoReportsFocused: _monacoReportsFocused,
              )) {
                return;
              }
              _webFocusNode.requestFocus();
              // Routed through _ignoreAsync: a click during a boot that
              // later fails must land in onError/FlutterError, not as an
              // unhandled zone error from this queued focus request.
              _ignoreAsync(
                _controller!.requestFocus(
                  attempts: 1,
                  intent: MonacoFocusIntent.user,
                ),
              );
            },
            child: _controller!.webViewWidget,
          ),
        ),
      );
    }

    Widget content = webView;
    if (_connectionState == _ConnectionState.connecting) {
      // Overlay the webView with a loading indicator, this ensures the
      // webView already exists and is ready to be rendered.
      content = Stack(
        children: [
          webView,
          Positioned.fill(
            child:
                widget.loadingBuilder?.call(context) ??
                const MonacoDefaultLoading(),
          ),
        ],
      );
    } else if (_connectionState == _ConnectionState.error) {
      // Overlay the webView with an error indicator, this ensures the
      // webView already exists and is ready to be rendered.
      content = Stack(
        children: [
          webView,
          Positioned.fill(
            child:
                widget.errorBuilder?.call(context, _error!, _stack) ??
                MonacoDefaultError(
                  error: _error!,
                  onRetry: _ownsController ? _bootstrap : null,
                ),
          ),
        ],
      );
    }

    final showBar = widget.showStatusBar || widget.statusBarBuilder != null;

    if (!showBar) {
      return content;
    }

    // The status bar is built here, listening to the controller's stats.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: content),
        if (widget.statusBarBuilder != null)
          ValueListenableBuilder<MonacoLiveStats>(
            valueListenable: _controller!.stats,
            builder: (context, stats, _) =>
                widget.statusBarBuilder!(context, stats),
          )
        else
          MonacoStatusBar(controller: _controller!),
      ],
    );
  }

  @override
  void dispose() {
    _webFocusNode.dispose();
    _teardown(disposeOldController: _ownsController);
    super.dispose();
  }
}
