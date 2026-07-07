import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/widgets/monaco_status_bar.dart';

/// A widget that renders a Monaco diff editor (original vs modified).
///
/// Mirrors `MonacoEditor`'s chrome: shows [loadingBuilder] until the diff
/// editor is ready and [errorBuilder] on boot failure. Content, language,
/// options, and diff options update live via `didUpdateWidget`.
///
/// ### Example
///
/// ```dart
/// MonacoDiffEditor(
///   original: oldSource,
///   modified: newSource,
///   language: MonacoLanguage.dart,
///   diffOptions: MonacoDiffOptions(renderSideBySide: true),
/// )
/// ```
class MonacoDiffEditor extends StatefulWidget {
  /// Creates a new [MonacoDiffEditor] widget.
  const MonacoDiffEditor({
    super.key,
    this.controller,
    this.controllerFactory,
    this.original = '',
    this.modified = '',
    this.language = MonacoLanguage.plaintext,
    this.options = const EditorOptions(),
    this.diffOptions = const MonacoDiffOptions(),
    this.page = const MonacoPageConfig(),
    this.readyTimeout = const Duration(seconds: 20),
    this.onReady,
    this.onError,
    this.loadingBuilder,
    this.errorBuilder,
    this.backgroundColor,
  });

  /// The controller that manages the diff editor instance.
  ///
  /// If provided, you are responsible for disposing of it. If `null`, a
  /// controller is created and managed internally by this widget.
  final MonacoDiffController? controller;

  /// Test-only hook to supply a controller factory when this widget owns
  /// the controller lifecycle.
  @visibleForTesting
  final Future<MonacoDiffController> Function()? controllerFactory;

  /// The original (left) text.
  final String original;

  /// The modified (right) text.
  final String modified;

  /// The language shared by both sides.
  final MonacoLanguage language;

  /// Editor options for the inner editor pair (fonts, minimap, ...).
  ///
  /// A null [EditorOptions.theme] follows the surrounding Flutter
  /// brightness (D27), exactly like `MonacoEditor`.
  final EditorOptions options;

  /// Diff-specific options (side-by-side vs inline, ...).
  final MonacoDiffOptions diffOptions;

  /// Page-level settings; changing this recreates the controller when the
  /// widget owns it.
  final MonacoPageConfig page;

  /// The maximum duration to wait for the diff editor to initialize.
  final Duration readyTimeout;

  /// Callback invoked when the diff editor is ready.
  final ValueChanged<MonacoDiffController>? onReady;

  /// Callback invoked when a background diff operation fails. When `null`,
  /// failures go to [FlutterError.reportError].
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Builder for the widget displayed while the diff editor initializes.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the widget displayed if initialization fails.
  final Widget Function(BuildContext context, Object error, StackTrace? st)?
  errorBuilder;

  /// Background color painted behind the WebView.
  final Color? backgroundColor;

  @override
  State<MonacoDiffEditor> createState() => _MonacoDiffEditorState();
}

enum _DiffConnectionState { connecting, ready, error }

class _MonacoDiffEditorState extends State<MonacoDiffEditor> {
  MonacoDiffController? _controller;
  bool _ownsController = false;
  _DiffConnectionState _connectionState = _DiffConnectionState.connecting;
  Object? _error;
  StackTrace? _stack;
  int _bootstrapSeq = 0;
  MonacoTheme? _appliedResolvedTheme;
  bool _bootstrappedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First bootstrap runs here (not initState): resolving a null theme
    // reads Theme.of(context). See MonacoEditor for the same pattern.
    if (!_bootstrappedOnce) {
      _bootstrappedOnce = true;
      _bootstrap();
      return;
    }
    // D27: a null options.theme follows the ambient brightness.
    if (widget.options.theme != null) return;
    if (_connectionState != _DiffConnectionState.ready || _controller == null) {
      return;
    }
    final resolved = _resolveTheme();
    if (resolved == _appliedResolvedTheme) return;
    _appliedResolvedTheme = resolved;
    _ignoreAsync(_controller!.setTheme(resolved));
  }

  @override
  void didUpdateWidget(covariant MonacoDiffEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      _teardown(disposeOldController: _ownsController);
      _bootstrap();
      return;
    }

    if (_ownsController && oldWidget.page != widget.page) {
      _teardown(disposeOldController: true);
      _bootstrap();
      return;
    }

    if (_connectionState != _DiffConnectionState.ready || _controller == null) {
      return;
    }

    if (widget.original != oldWidget.original ||
        widget.modified != oldWidget.modified ||
        widget.language != oldWidget.language) {
      _ignoreAsync(
        _controller!.setTexts(
          original: widget.original,
          modified: widget.modified,
          language: widget.language,
        ),
      );
    }

    if (widget.options != oldWidget.options) {
      _ignoreAsync(_controller!.updateOptions(widget.options));
      if (widget.options.theme != oldWidget.options.theme) {
        final resolvedTheme = _resolveTheme();
        _appliedResolvedTheme = resolvedTheme;
        _ignoreAsync(_controller!.setTheme(resolvedTheme));
      }
    }

    if (widget.diffOptions != oldWidget.diffOptions) {
      _ignoreAsync(_controller!.updateDiffOptions(widget.diffOptions));
    }
  }

  /// Resolves the effective theme: an explicit options theme always wins;
  /// a null theme follows the surrounding Flutter brightness (D27).
  MonacoTheme _resolveTheme() {
    final explicit = widget.options.theme;
    if (explicit != null) return explicit;
    final brightness = mounted ? Theme.of(context).brightness : Brightness.dark;
    return brightness == Brightness.dark
        ? MonacoDefaults.darkTheme
        : MonacoDefaults.lightTheme;
  }

  bool _isBootstrapCurrent(int token) => token == _bootstrapSeq && mounted;

  Future<void> _bootstrap() async {
    final bootstrapToken = ++_bootstrapSeq;
    setState(() {
      _connectionState = _DiffConnectionState.connecting;
      _error = null;
      _stack = null;
    });

    try {
      final ownsController = widget.controller == null;
      _ownsController = ownsController;
      final usedInternalCreate =
          widget.controller == null && widget.controllerFactory == null;
      final bootTheme = _resolveTheme();
      _appliedResolvedTheme = bootTheme;
      final controller =
          widget.controller ??
          await (widget.controllerFactory?.call() ??
              MonacoDiffController.create(
                options: widget.options.copyWith(theme: bootTheme),
                diff: widget.diffOptions,
                original: widget.original,
                modified: widget.modified,
                language: widget.language,
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

      await _controller!.whenReady;
      if (!_isBootstrapCurrent(bootstrapToken)) {
        return;
      }

      // Externally supplied controllers booted with their own texts and
      // options; apply this widget's configuration post-readiness. Texts
      // are only pushed when the widget actually carries content -
      // otherwise the defaults ('' vs '') would wipe the diff an external
      // controller booted with.
      if (!usedInternalCreate) {
        await _controller!.updateOptions(widget.options);
        await _controller!.updateDiffOptions(widget.diffOptions);
        final resolvedTheme = _resolveTheme();
        _appliedResolvedTheme = resolvedTheme;
        await _controller!.setTheme(resolvedTheme);
        if (widget.original.isNotEmpty || widget.modified.isNotEmpty) {
          await _controller!.setTexts(
            original: widget.original,
            modified: widget.modified,
            language: widget.language,
          );
        }
        if (!_isBootstrapCurrent(bootstrapToken)) {
          return;
        }
      }

      setState(() => _connectionState = _DiffConnectionState.ready);
      widget.onReady?.call(_controller!);
    } catch (e, st) {
      if (!_isBootstrapCurrent(bootstrapToken)) return;
      // Boot failures render the error surface; onError is informed when
      // set, but there is no FlutterError fallback - the failure is
      // already visible.
      widget.onError?.call(e, st);
      setState(() {
        _connectionState = _DiffConnectionState.error;
        _error = e;
        _stack = st;
      });
    }
  }

  void _ignoreAsync(Future<void> future) {
    unawaited(
      future.catchError((Object e, StackTrace st) {
        _reportAsyncError(e, st);
      }),
    );
  }

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
        context: ErrorDescription('while running a MonacoDiffEditor update'),
      ),
    );
  }

  void _teardown({required bool disposeOldController}) {
    if (disposeOldController) {
      _controller?.dispose();
    }
    _controller = null;
    _appliedResolvedTheme = null;
  }

  @override
  void dispose() {
    _teardown(disposeOldController: _ownsController);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        widget.backgroundColor ??
        (theme.brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white);

    return ColoredBox(color: bg, child: _buildChild(context));
  }

  Widget _buildChild(BuildContext context) {
    // No controller yet: plain loading/error chrome.
    if (_controller == null) {
      if (_connectionState == _DiffConnectionState.error) {
        return widget.errorBuilder?.call(context, _error!, _stack) ??
            MonacoDefaultError(
              error: _error!,
              onRetry: _ownsController ? _bootstrap : null,
            );
      }
      return widget.loadingBuilder?.call(context) ??
          const MonacoDefaultLoading();
    }

    // The WebView must be IN the tree while the page boots: on web the
    // iframe only attaches (and can load Monaco) once its platform view
    // renders. Loading/error states overlay it instead of replacing it,
    // exactly like MonacoEditor.
    final webView = SizedBox.expand(child: _controller!.webViewWidget);
    return switch (_connectionState) {
      _DiffConnectionState.ready => webView,
      _DiffConnectionState.connecting => Stack(
        children: [
          webView,
          Positioned.fill(
            child:
                widget.loadingBuilder?.call(context) ??
                const MonacoDefaultLoading(),
          ),
        ],
      ),
      _DiffConnectionState.error => Stack(
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
      ),
    };
  }
}
