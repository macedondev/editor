import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/lsp/lsp_connection.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';
import 'package:flutter_monaco/src/protocol/envelope.dart';
import 'package:flutter_monaco/src/protocol/protocol.dart';

/// A callback function that provides completion items for a given
/// [CompletionRequest]. It should return a [Future] that resolves to a
/// [CompletionList].
typedef CompletionProvider =
    Future<CompletionList> Function(CompletionRequest request);

/// Describes why Monaco input focus is being requested.
///
/// The distinction matters on desktop platform views: background maintenance
/// must not steal the keyboard from Flutter text inputs, while direct user
/// interaction with Monaco is an intentional keyboard handoff that may release
/// Flutter's active text input before Monaco is focused.
enum MonacoFocusIntent {
  /// Focus requested because the user directly interacted with Monaco.
  user,

  /// Focus requested by background maintenance such as route or lifecycle sync.
  maintenance,
}

/// Manages the lifecycle and interaction with a Monaco Editor instance.
///
/// The [MonacoController] bridges Dart and the underlying JavaScript editor,
/// providing methods to read/write content, manage selection, and execute commands.
///
/// ### Usage
/// * Call [create] to instantiate a controller off-widget (headless or advanced usage).
/// * Use [setValue] / [getValue] to manage content.
/// * Listen to [onContentChanged] for real-time updates.
class MonacoController {
  MonacoController._(this._protocol, this._webViewController) {
    _wireEvents();
    _lspManager = MonacoLspManager(protocol: _protocol);
  }

  final MonacoProtocol _protocol;
  final PlatformWebViewController _webViewController;
  final Completer<void> _onReady = Completer<void>();
  late final MonacoLspManager _lspManager;
  bool _disposed = false;
  bool _interactionEnabled = true;

  /// Real-time statistics from the editor, updated on every cursor/content
  /// change via the `stats` protocol event.
  final ValueNotifier<LiveStats> _liveStats = ValueNotifier(
    LiveStats.defaults(),
  );

  // Event streams
  final _onContentChanged = StreamController<bool>.broadcast();
  final _onSelectionChanged = StreamController<Range?>.broadcast();
  final _onFocus = StreamController<void>.broadcast();
  final _onBlur = StreamController<void>.broadcast();
  final _onScrollHandoff =
      StreamController<MonacoScrollHandoffDetails>.broadcast();
  StreamSubscription<ProtocolEvent>? _eventSubscription;

  // Decoration tracking
  List<String> _decorationIds = const [];

  // Content queuing for pre-ready calls
  String? _queuedValue;
  MonacoLanguage? _queuedLanguage;
  final List<_RegisteredCompletion> _queuedCompletionSources = [];
  final Map<String, _RegisteredCompletion> _completionSources = {};
  bool _completionListenerWired = false;

  /// Completes when the editor is fully initialized and ready to accept commands.
  Future<void> get onReady => _onReady.future;

  /// Returns `true` if the editor has finished initializing.
  bool get isReady => _onReady.isCompleted;

  /// Returns `true` if the editor currently accepts user interaction.
  bool get isInteractionEnabled => _interactionEnabled;

  /// Exposes real-time statistics (cursor position, selection, line count).
  ValueNotifier<LiveStats> get liveStats => _liveStats;

  /// Stream emitting `true` (flush) or `false` (partial) when content changes.
  Stream<bool> get onContentChanged => _onContentChanged.stream;

  /// Stream emitting the new [Range] whenever the cursor selection changes.
  Stream<Range?> get onSelectionChanged => _onSelectionChanged.stream;

  /// Stream emitting Monaco DOM focus events.
  ///
  /// This is not a native input-readiness guarantee on desktop platform views.
  Stream<void> get onFocus => _onFocus.stream;

  /// Stream emitting Monaco DOM blur events.
  Stream<void> get onBlur => _onBlur.stream;

  /// Stream emitting scroll deltas the editor could not consume.
  ///
  /// Events only arrive after a source was enabled with
  /// [setScrollHandoffSources] (the `MonacoEditor.scrollHandoff`
  /// configuration does this automatically). Malformed bridge payloads are
  /// dropped silently. See [MonacoScrollHandoffDetails] for the delta
  /// conventions.
  Stream<MonacoScrollHandoffDetails> get onScrollHandoff =>
      _onScrollHandoff.stream;

  /// Creates and initializes a new [MonacoController].
  ///
  /// This method spins up the WebView and loads the Monaco resources.
  ///
  /// On native platforms it waits for the `ready` lifecycle signal from
  /// JavaScript before returning. On web it returns as soon as the controller
  /// is created and continues initialization in the background. Use [onReady]
  /// or [isReady] to wait for readiness on web.
  ///
  /// Throws a [TimeoutException] if the editor does not become ready within [readyTimeout] (default 20s).
  ///
  /// * [options]: Initial configuration (theme, language, etc.).
  /// * [customCss]: CSS injected into the HTML (e.g., for custom fonts).
  /// * [allowCdnFonts]: If `true`, allows loading fonts from remote URLs (enables network requests).
  /// * [allowedConnectSources]: Extra Content-Security-Policy `connect-src`
  ///   origins the editor page may reach (e.g. `['ws://127.0.0.1:3000']`).
  ///   Required for [connectLanguageServer] with an [LspWebSocketTransport];
  ///   see that class for details. **Security note:** every listed origin
  ///   becomes reachable from JavaScript inside the editor.
  static Future<MonacoController> create({
    EditorOptions? options,
    String? customCss,
    bool allowCdnFonts = false,
    List<String> allowedConnectSources = const [],
    Duration? readyTimeout,
  }) async {
    // Ensure Monaco assets are ready
    await MonacoAssets.ensureReady();

    // Create platform-specific WebView controller
    final webViewController = PlatformWebViewFactory.createController();
    final protocol = MonacoProtocol(webView: webViewController);
    MonacoController? controller;

    try {
      // Initialize WebView.
      await webViewController.initialize();
      await webViewController.enableJavaScript();
      await webViewController.addJavaScriptChannel(
        'flutterChannel',
        protocol.handleChannelMessage,
      );

      // Create controller first (before loading HTML) so widget can render.
      controller = MonacoController._(protocol, webViewController);

      final readyFuture = (() async {
        try {
          await webViewController.load(
            customCss: customCss,
            allowCdnFonts: allowCdnFonts,
            allowedConnectSources: allowedConnectSources,
          );
          debugPrint(
            '[MonacoController] Loading HTML (Platform: ${kIsWeb ? 'Web' : defaultTargetPlatform.name})',
          );

          // Wait for editor ready signal with configurable timeout
          await protocol.editorReady.timeout(
            readyTimeout ?? const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
              'Monaco Editor did not report ready in ${readyTimeout?.inSeconds ?? 20} seconds.',
            ),
          );

          // Mark ready
          if (!controller!._onReady.isCompleted) {
            controller._onReady.complete();
          }

          // Apply initial options if provided
          if (options != null) {
            await controller.updateOptions(options);
            await controller.setThemeById(options.effectiveThemeId);
            await controller.setLanguage(options.language);
          }

          // Apply any queued content
          if (controller._queuedValue != null) {
            await controller.setValue(controller._queuedValue!);
            controller._queuedValue = null;
          }
          if (controller._queuedLanguage != null) {
            await controller.setLanguage(controller._queuedLanguage!);
            controller._queuedLanguage = null;
          }

          // Register any queued completion sources
          for (final entry in controller._queuedCompletionSources) {
            await controller._registerCompletionSourceInternal(entry);
          }
          controller._queuedCompletionSources.clear();
        } catch (e, st) {
          // Only complete _onReady with error on web, where we return the
          // controller before readyFuture completes. On native, we await
          // readyFuture and throw before returning, so no one listens to
          // _onReady - completing it with an error would be unhandled.
          if (kIsWeb &&
              controller != null &&
              !controller._onReady.isCompleted) {
            controller._onReady.completeError(e, st);
          }
          rethrow;
        }
      })();

      if (kIsWeb) {
        unawaited(readyFuture.catchError((Object _, StackTrace _) {}));
      } else {
        await readyFuture;
      }

      return controller;
    } catch (_) {
      // Clean up resources on failure
      if (controller != null) {
        controller.dispose();
      } else {
        protocol.dispose();
        webViewController.dispose();
      }
      rethrow;
    }
  }

  /// Create a controller for tests without touching assets or platform views.
  ///
  /// When [markReady] is true, synthetic `pageReady` and `ready` lifecycle
  /// envelopes are pushed through the real protocol decode path so the
  /// controller behaves exactly as it does against a live page.
  @visibleForTesting
  static Future<MonacoController> createForTesting({
    required PlatformWebViewController webViewController,
    bool markReady = true,
    String channelName = 'flutterChannel',
  }) async {
    final protocol = MonacoProtocol(webView: webViewController);

    await webViewController.initialize();
    await webViewController.enableJavaScript();
    await webViewController.addJavaScriptChannel(
      channelName,
      protocol.handleChannelMessage,
    );

    final controller = MonacoController._(protocol, webViewController);
    if (markReady) {
      controller.completeReadyForTesting();
    }
    return controller;
  }

  /// Manually complete the ready signal for tests.
  @visibleForTesting
  void completeReadyForTesting() {
    _protocol.handleChannelMessage(
      jsonEncode({
        'v': kMonacoProtocolVersion,
        'kind': 'lifecycle',
        'name': 'pageReady',
        'protocolVersion': kMonacoProtocolVersion,
        'monacoVersion': 'test',
        'capabilities': ['lsp'],
      }),
    );
    _protocol.handleChannelMessage(
      jsonEncode({
        'v': kMonacoProtocolVersion,
        'kind': 'lifecycle',
        'name': 'ready',
      }),
    );
    if (!_onReady.isCompleted) {
      _onReady.complete();
    }
  }

  /// Get the platform-specific WebView widget
  Widget get webViewWidget => _webViewController.widget;

  /// Ensure the editor is ready before executing commands
  Future<void> _ensureReady() async {
    if (!_onReady.isCompleted) {
      await _onReady.future;
    }
  }

  /// Dispatches a protocol command after readiness; maps a JavaScript
  /// `undefined` result to `null`.
  Future<Object?> _invoke(String method, Map<String, Object?> params) async {
    await _ensureReady();
    final result = await _protocol.invoke(method, params);
    return identical(result, monacoJsUndefined) ? null : result;
  }

  /// Switches the editor's syntax highlighting language.
  ///
  /// If the editor is not yet ready, the language is queued and applied upon initialization.
  Future<void> setLanguage(MonacoLanguage language) async {
    if (!_onReady.isCompleted) {
      _queuedLanguage = language;
      if (kIsWeb) return;
      await _ensureReady();
      if (_queuedLanguage == language) {
        // Only use queued value if it hasn't been overwritten
        _queuedLanguage = null;
      } else {
        return; // A newer language was queued, skip this one
      }
    }
    await _invoke('document.setLanguage', {'language': language.id});
  }

  /// Configures Monaco's built-in JSON diagnostics and schema validation.
  ///
  /// This applies globally to all JSON models in the editor, not just the
  /// active one. Call it once after the editor is ready (the method
  /// internally awaits readiness). Calling it again replaces the previous
  /// configuration entirely.
  ///
  /// See [JsonDiagnosticsOptions] for available settings and defaults.
  Future<void> setJsonDiagnostics(JsonDiagnosticsOptions diagnostics) async {
    await _invoke('json.configureDiagnostics', {
      'options': diagnostics.toJson(),
    });
  }

  /// Changes the editor's color theme.
  ///
  /// Waits for the editor to be ready before applying.
  Future<void> setTheme(MonacoTheme theme) async {
    await setThemeById(theme.id);
  }

  /// Changes the editor's color theme using a raw Monaco theme identifier.
  ///
  /// Accepts both built-in Monaco theme ids and custom theme ids previously
  /// registered with [defineTheme] or [defineThemeFromJson]. Throws an
  /// [ArgumentError] when [themeId] is empty so callers don't silently
  /// activate Monaco's empty-string fallback.
  Future<void> setThemeById(String themeId) async {
    if (themeId.trim().isEmpty) {
      throw ArgumentError.value(
        themeId,
        'themeId',
        'themeId must be a non-empty string',
      );
    }
    await _invoke('editor.setTheme', {'theme': themeId});
  }

  /// Returns the Monaco theme id currently active in the editor.
  ///
  /// Reads the live value from Monaco's runtime rather than caching what
  /// Dart most recently sent. Returns `null` when Monaco can't report a
  /// theme (e.g. on engine versions that don't expose `editor.getTheme()`)
  /// or when the bridge call fails - this method follows the same
  /// fallback-on-failure contract as [getValue] / [getLineCount].
  Future<String?> getThemeId() async {
    try {
      final result = await _invoke('editor.getTheme', {});
      return result is String && result.isNotEmpty ? result : null;
    } catch (_) {
      return null;
    }
  }

  /// Registers or replaces a custom Monaco theme.
  ///
  /// After registration, activate the theme by calling
  /// [setThemeById]([MonacoThemeDefinition.id]) or setting
  /// [EditorOptions.themeId].
  ///
  /// Use [defineThemeFromJson] when the theme data only exists in raw
  /// Monaco-shaped JSON.
  Future<void> defineTheme(MonacoThemeDefinition theme) async {
    await defineThemeFromJson(theme.id, theme.toMonacoThemeData());
  }

  /// Registers or replaces a Monaco theme from raw Monaco-shaped JSON.
  ///
  /// This is an escape hatch for Monaco theme fields not yet modeled by
  /// [MonacoThemeDefinition]. Prefer [defineTheme] for type safety. Throws
  /// an [ArgumentError] when [id] is empty.
  ///
  /// [data] must follow Monaco's `IStandaloneThemeData` shape.
  Future<void> defineThemeFromJson(String id, Map<String, Object?> data) async {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(
        id,
        'id',
        'theme id must be a non-empty string',
      );
    }
    await _invoke('editor.defineTheme', {'id': id, 'data': data});
  }

  /// Sets the background color of the native WebView container.
  ///
  /// This targets the platform-side WebView surface only - it does NOT
  /// change Monaco's HTML host page or Monaco's own `editor.background`
  /// theme token. On macOS, native WebView background updates may be
  /// unreliable; prefer [setHostPageBackgroundColor] there or register a
  /// custom `MonacoThemeDefinition` with the desired `editor.background`.
  Future<void> setBackgroundColor(Color color) async {
    await _webViewController.setBackgroundColor(color);
  }

  /// Sets the background color of Monaco's HTML host page.
  ///
  /// Writes a CSS color to `html`, `body`, and the Monaco container element
  /// via the JS bridge. This is the most reliable surface to recolor when
  /// the native WebView's background isn't honored (notably macOS platform
  /// views). To change Monaco's own editor surface, register a
  /// [MonacoThemeDefinition] with an `editor.background` color instead -
  /// this method does not affect Monaco's internal theme tokens.
  Future<void> setHostPageBackgroundColor(Color color) async {
    await _invoke('page.setBackground', {'color': _cssRgba(color)});
  }

  /// Converts a Flutter [Color] to a CSS `rgba(...)` string.
  String _cssRgba(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return 'rgba($r, $g, $b, ${color.a})';
  }

  /// Toggles whether the editor intercepts pointer events.
  ///
  /// On Web, this is used to allow Flutter overlays (like dialogs) to receive
  /// pointer events even when they overlap the editor. When disabled, the
  /// editor will not respond to mouse or touch events.
  ///
  /// On native platforms, this may be a no-op as overlays work correctly by default.
  Future<void> setInteractionEnabled(bool enabled) async {
    // No need to wait for ready, can be set immediately
    if (_disposed) return;
    _interactionEnabled = enabled;
    await _webViewController.setInteractionEnabled(enabled);
  }

  /// Runs [action] with editor interaction temporarily disabled, restoring the
  /// previous state in a `finally` block.
  ///
  /// Useful for transient Flutter overlays that are NOT pushed as routes (so
  /// [`MonacoFocusGuard`] cannot detect them) and that are NOT static enough
  /// to wrap in a [`MonacoOverlayBoundary`] - typically `ScaffoldMessenger`
  /// snackbars with action buttons, toasts, or imperative `Overlay.insert`
  /// entries shown for a known duration.
  ///
  /// On native platforms `setInteractionEnabled` is a no-op, so this is a
  /// thin wrapper around the [action] there.
  ///
  /// Example:
  /// ```dart
  /// await controller.runWithInteractionDisabled(() async {
  ///   ScaffoldMessenger.of(context).showSnackBar(
  ///     SnackBar(
  ///       content: const Text('Saved'),
  ///       action: SnackBarAction(label: 'Undo', onPressed: undo),
  ///     ),
  ///   );
  ///   await Future<void>.delayed(const Duration(seconds: 4));
  /// });
  /// ```
  Future<T> runWithInteractionDisabled<T>(FutureOr<T> Function() action) async {
    if (_disposed) {
      return await Future<T>.value(action());
    }

    final wasEnabled = _interactionEnabled;
    if (wasEnabled) {
      await setInteractionEnabled(false);
    }

    try {
      return await Future<T>.value(action());
    } finally {
      if (wasEnabled && !_disposed) {
        await setInteractionEnabled(true);
      }
    }
  }

  /// Updates the editor configuration options.
  ///
  /// Only the fields present in [options] will be updated; others remain unchanged.
  Future<void> updateOptions(EditorOptions options) async {
    await _invoke('editor.updateOptions', {
      'options': options.toMonacoOptions(),
    });
  }

  /// Registers a dynamic completion provider for the given [languages].
  ///
  /// The [provider] callback is invoked whenever the user requests completions (e.g., Ctrl+Space).
  ///
  /// * [id]: Optional unique identifier. If omitted, one is generated.
  /// * [triggerCharacters]: Characters that automatically trigger the completion (e.g., `.` or `@`).
  ///
  /// Returns the [id] of the registered provider.
  Future<String> registerCompletionSource({
    String? id,
    required List<String> languages,
    List<String> triggerCharacters = const [],
    required CompletionProvider provider,
  }) async {
    if (languages.isEmpty) {
      throw ArgumentError.value(languages, 'languages', 'Cannot be empty');
    }
    if (id != null && _completionSources.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Completion source already exists');
    }

    final providerId =
        id ??
        'flutter_${DateTime.now().millisecondsSinceEpoch}_${_completionSources.length}';
    final entry = _RegisteredCompletion(
      id: providerId,
      languages: List<String>.from(languages),
      triggerCharacters: List<String>.from(triggerCharacters),
      provider: provider,
    );
    _completionSources[providerId] = entry;

    if (!_onReady.isCompleted) {
      // Queue for registration when ready - don't block widget rendering
      _queuedCompletionSources.add(entry);
      return providerId;
    }

    await _registerCompletionSourceInternal(entry);
    return providerId;
  }

  Future<void> _registerCompletionSourceInternal(
    _RegisteredCompletion entry,
  ) async {
    try {
      await _invoke('completions.register', {
        'id': entry.id,
        'languages': entry.languages,
        'triggerCharacters': entry.triggerCharacters,
      });
    } catch (e) {
      _completionSources.remove(entry.id);
      rethrow;
    }

    _wireCompletionListenerOnce();
  }

  /// Registers a static list of completion items.
  ///
  /// Useful for simple keyword lists or fixed snippets.
  Future<String> registerStaticCompletions({
    String? id,
    required List<String> languages,
    List<String> triggerCharacters = const [],
    required List<CompletionItem> items,
    bool isIncomplete = false,
  }) {
    return registerCompletionSource(
      id: id,
      languages: languages,
      triggerCharacters: triggerCharacters,
      provider: (_) async =>
          CompletionList(suggestions: items, isIncomplete: isIncomplete),
    );
  }

  /// Unregisters a previously registered completion source.
  Future<void> unregisterCompletionSource(String id) async {
    _completionSources.remove(id);
    // Also remove from queue if it was pending registration
    _queuedCompletionSources.removeWhere((e) => e.id == id);

    if (!_onReady.isCompleted) {
      // Not registered on JS side yet, just return
      return;
    }
    await _invoke('completions.unregister', {'id': id});
  }

  /// Execute an editor action
  Future<void> executeAction(String actionId, [dynamic args]) async {
    await _invoke('editor.executeAction', {'actionId': actionId, 'args': args});
  }

  /// Whether a Flutter text input (TextField, CupertinoTextField,
  /// SelectableText, ...) currently owns Flutter's primary focus.
  ///
  /// Focus nudges must never steal the keyboard from one: on Windows,
  /// [PlatformWebViewController.requestNativeFocus] moves real Win32
  /// keyboard focus to the WebView, which would make typing land in the
  /// editor instead of, say, a dialog's TextField.
  static bool _flutterTextInputHasFocus() {
    final BuildContext? context;
    try {
      context = FocusManager.instance.primaryFocus?.context;
    } catch (_) {
      // MonacoController also runs headless (no widget binding, e.g. plain
      // Dart tests); without a binding there is no Flutter focus to steal.
      return false;
    }
    if (context == null) return false;
    // Every Flutter text input attaches its focus node inside an
    // EditableText, so it is found as an ancestor state.
    return context.findAncestorStateOfType<EditableTextState>() != null;
  }

  static bool _shouldRespectFlutterTextInput(MonacoFocusIntent intent) {
    return intent == MonacoFocusIntent.maintenance;
  }

  /// Whether the in-page focus path must run a full replay (blur + refocus).
  ///
  /// The replay recovers stale WKWebView input readiness, but it is also the
  /// caret double-blink. With the macOS native first-responder handoff in
  /// place, replay is only the FALLBACK for embeddings where the handoff is
  /// unavailable (no native plugin registered) or did not take effect - when
  /// the handoff succeeded, native readiness is real and the idempotent
  /// in-page focus is enough, exactly as on Windows.
  static bool _shouldReplayInputFocus({
    required MonacoFocusIntent intent,
    required NativeFocusResult nativeFocus,
  }) {
    return !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.macOS &&
        intent == MonacoFocusIntent.user &&
        (nativeFocus == NativeFocusResult.unsupported ||
            nativeFocus == NativeFocusResult.failed);
  }

  static bool _shouldReleaseFlutterTextInput(MonacoFocusIntent intent) {
    if (kIsWeb || intent != MonacoFocusIntent.user) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  static Future<void> _releaseFlutterTextInputForUserFocus() async {
    if (_flutterTextInputHasFocus()) {
      try {
        FocusManager.instance.primaryFocus?.unfocus();
      } catch (_) {}
    }
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
    await Future<void>.delayed(Duration.zero);
  }

  /// Dispatches the in-page focus helper; failures are swallowed exactly as
  /// the 2.x raw-script path did (focus nudges are best-effort).
  Future<void> _forceFocus({bool replayInputFocus = false}) async {
    try {
      await _protocol.invoke('focus.force', {
        'replayInputFocus': replayInputFocus,
      });
    } catch (_) {}
  }

  /// Requests focus for the editor widget.
  ///
  /// Uses a robust method that waits for visibility and layout before attempting focus.
  /// On Android and iOS, the OS soft keyboard may only appear after a user tap
  /// inside the editor.
  ///
  /// This is cooperative: it does nothing while a Flutter text input owns
  /// the primary focus, so programmatic calls cannot steal the keyboard from
  /// a focused TextField (e.g. in a dialog). For direct pointer interaction,
  /// use [ensureEditorFocus] with [MonacoFocusIntent.user].
  Future<void> focus() async {
    if (!_interactionEnabled) return;
    await _ensureReady();
    if (_flutterTextInputHasFocus()) return;
    // Windows: WebView2 must hold real Win32 keyboard focus before the
    // in-page focus below has any effect. macOS: the WKWebView must be the
    // window's first responder. No-op elsewhere.
    await _webViewController.requestNativeFocus();
    // Use robust in-page helper (waits for visibility, layouts, focuses textarea)
    await _forceFocus();
  }

  /// Attempts to focus the editor multiple times to handle race conditions during layout transitions.
  ///
  /// [attempts] defaults to 3, with [interval] of 24ms.
  ///
  /// Like [focus], this defaults to cooperative background maintenance:
  /// attempts made while a Flutter text input owns the primary focus are
  /// skipped, so refocus nudges after content updates, route pops, or app
  /// resume cannot steal the keyboard from a focused TextField.
  ///
  /// Pass [MonacoFocusIntent.user] only from direct user interaction with the
  /// editor, such as a primary pointer down inside the Monaco view. On desktop
  /// that intent first releases Flutter's text-input channel so a stale
  /// TextField/dialog client cannot keep swallowing native input, then hands
  /// native keyboard focus to the WebView (Win32 focus on Windows, NSWindow
  /// first responder on macOS). When the macOS handoff is unavailable (no
  /// native plugin registered) or fails, the first in-page focus attempt
  /// replays the full focus path as a fallback, because WKWebView native
  /// input readiness can become stale while Monaco still reports DOM focus.
  Future<void> ensureEditorFocus({
    int attempts = 3,
    Duration interval = const Duration(milliseconds: 24),
    MonacoFocusIntent intent = MonacoFocusIntent.maintenance,
  }) async {
    if (!_interactionEnabled) return;
    await _ensureReady();

    var nativeFocusRequested = false;
    var replayInputFocus = false;

    // On mobile, multiple async focus() calls interrupt the IME lifecycle.
    final isMobileNative =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final effectiveAttempts = isMobileNative ? 1 : attempts;
    if (effectiveAttempts <= 0) return;

    if (_shouldReleaseFlutterTextInput(intent)) {
      await _releaseFlutterTextInputForUserFocus();
    }

    for (var i = 0; i < effectiveAttempts; i++) {
      // Re-evaluated per attempt: a text input losing focus mid-loop (e.g.
      // a closing dialog) lets the remaining attempts proceed.
      if (!_shouldRespectFlutterTextInput(intent) ||
          !_flutterTextInputHasFocus()) {
        if (!nativeFocusRequested) {
          // Hand native keyboard focus to the WebView first; the JS focus
          // below cannot take effect without it (Win32 focus on Windows,
          // first responder on macOS).
          final nativeFocus = await _webViewController.requestNativeFocus();
          nativeFocusRequested = true;
          replayInputFocus = _shouldReplayInputFocus(
            intent: intent,
            nativeFocus: nativeFocus,
          );
        }
        await _forceFocus(replayInputFocus: replayInputFocus);
        // Replay at most once per call: later attempts are settle-retries,
        // and repeating the blur/refocus cycle would multiply the caret
        // blink the replay already costs.
        replayInputFocus = false;
      }
      if (i + 1 < effectiveAttempts) {
        await Future<void>.delayed(interval);
      }
    }
  }

  /// Whether the native layer currently routes keyboard input to the
  /// editor's WebView.
  ///
  /// Returns `true`/`false` where the platform can answer authoritatively
  /// (macOS: the WKWebView is the window's first responder, via the
  /// `flutter_monaco` native plugin; Windows: WebView2 reports native
  /// focus), and `null` where it cannot (Android, iOS, Web, headless test
  /// environments, or when the WebView cannot be located in the window).
  ///
  /// This is the real desktop input-readiness signal: [onFocus]/[onBlur]
  /// only report Monaco's DOM focus, which can stay `true` while the native
  /// layer stopped routing keys to the WebView (for example after an
  /// app switch, dialog, or tab change). Apps that model input readiness
  /// can use this to verify staleness instead of assuming it.
  Future<bool?> hasNativeInputFocus() {
    return _webViewController.hasNativeInputFocus();
  }

  /// Hands native keyboard focus back to the Flutter view if the editor's
  /// WebView currently holds it.
  ///
  /// Use this for an explicit programmatic handoff out of the editor (for
  /// example before moving focus to a Flutter text field without a user
  /// click). macOS makes the Flutter view first responder; Windows asks
  /// WebView2 to release focus. No-op on other platforms or when the editor
  /// does not own native focus.
  Future<void> releaseNativeInputFocus() {
    return _webViewController.releaseNativeFocus();
  }

  /// Forces the Monaco editor to re-measure its container and update its layout.
  ///
  /// Call this if the widget size changes but the editor does not update automatically.
  Future<void> layout() async {
    await _invoke('editor.layout', {});
  }

  /// Scrolls the editor to the very top (line 1, column 1).
  Future<void> scrollToTop() async {
    await _invoke('editor.scrollToEdge', {'edge': 'top'});
  }

  /// Scrolls the editor to the last line.
  Future<void> scrollToBottom() async {
    await _invoke('editor.scrollToEdge', {'edge': 'bottom'});
  }

  /// Enables or disables edge scroll handoff sources inside the editor page.
  ///
  /// When a source is enabled, the page installs the matching DOM listeners
  /// and posts `scrollHandoff` events (surfaced through [onScrollHandoff])
  /// for deltas the editor cannot consume. Disabling a source removes its
  /// listeners again, so both sources disabled restores the exact
  /// pre-feature behavior. Waits for the editor to be ready.
  ///
  /// `MonacoEditor` calls this automatically from its `scrollHandoff`
  /// configuration; call it directly only for headless or custom-widget
  /// integrations that consume [onScrollHandoff] themselves.
  Future<void> setScrollHandoffSources({
    bool wheel = false,
    bool touch = false,
  }) async {
    await _invoke('page.setScrollHandoff', {'wheel': wheel, 'touch': touch});
  }

  /// Format the document
  Future<void> format() => executeAction(MonacoAction.formatDocument);

  /// Open find dialog
  Future<void> find() => executeAction(MonacoAction.find);

  /// Open replace dialog
  Future<void> replace() => executeAction(MonacoAction.startFindReplaceAction);

  /// Toggle word wrap
  Future<void> toggleWordWrap() => executeAction(MonacoAction.toggleWordWrap);

  /// Select all content
  Future<void> selectAll() => executeAction(MonacoAction.selectAll);

  /// Undo last action
  Future<void> undo() => executeAction(MonacoAction.undo);

  /// Redo last undone action
  Future<void> redo() => executeAction(MonacoAction.redo);

  /// Cut selected text
  Future<void> cut() => executeAction(MonacoAction.clipboardCutAction);

  /// Copy selected text
  Future<void> copy() => executeAction(MonacoAction.clipboardCopyAction);

  /// Paste from clipboard
  Future<void> paste() => executeAction(MonacoAction.clipboardPasteAction);

  /// Fold all foldable regions in the current model.
  Future<void> foldAll() => executeAction(MonacoAction.foldAll);

  /// Unfold all foldable regions in the current model.
  Future<void> unfoldAll() => executeAction(MonacoAction.unfoldAll);

  /// Toggle line comments on the current selection.
  Future<void> toggleLineComment() => executeAction(MonacoAction.commentLine);

  /// Indent the current selection or active line.
  Future<void> indentLines() => executeAction(MonacoAction.indentLines);

  /// Outdent the current selection or active line.
  Future<void> outdentLines() => executeAction(MonacoAction.outdentLines);

  // --- EVENT HANDLING ---

  /// Wire up protocol event listeners.
  void _wireEvents() {
    _eventSubscription = _protocol.events.listen((event) {
      switch (event.name) {
        case 'stats':
          try {
            _liveStats.value = LiveStats.fromJson(
              Map<String, dynamic>.from(event.data),
            );
          } catch (e) {
            debugPrint('[MonacoController] Failed to parse stats: $e');
          }
        case 'contentChanged':
          _onContentChanged.add(event.data['isFlush'] == true);
        case 'selectionChanged':
          final selection = event.data['selection'];
          _onSelectionChanged.add(
            selection is Map
                ? Range.fromJson(Map<String, dynamic>.from(selection))
                : null,
          );
        case 'focusChanged':
          if (event.data['focused'] == true) {
            _onFocus.add(null);
          } else {
            _onBlur.add(null);
          }
        case 'scrollHandoff':
          final details = MonacoScrollHandoffDetails.tryParse(
            Map<String, dynamic>.from(event.data),
          );
          if (details != null) {
            _onScrollHandoff.add(details);
          }
        default:
          break;
      }
    });
  }

  void _wireCompletionListenerOnce() {
    if (_completionListenerWired) return;
    _completionListenerWired = true;

    _protocol.events.where((event) => event.name == 'completionRequest').listen(
      (event) {
        unawaited(() async {
          try {
            await _ensureReady();
            final request = CompletionRequest.fromJson(
              Map<String, dynamic>.from(event.data),
            );
            final registered = _completionSources[request.providerId];
            const emptySuggestions = {'suggestions': <Map<String, dynamic>>[]};

            Future<void> respond(Map<String, dynamic> payload) {
              return _invoke('completions.resolve', {
                'requestId': request.requestId,
                'payload': payload,
              });
            }

            if (registered == null) {
              await respond(emptySuggestions);
              return;
            }

            try {
              final result = await registered.provider(request);
              await respond(result.toJson());
            } catch (e) {
              debugPrint('[MonacoController] completion provider failed: $e');
              await respond(emptySuggestions);
            }
          } catch (e) {
            debugPrint('[MonacoController] completion respond failed: $e');
          }
        }());
      },
    );
  }

  // --- CONTENT AND SELECTION ---

  /// Retrieves the current text content of the editor.
  ///
  /// Returns [defaultValue] if the operation fails or returns null.
  Future<String> getValue({String defaultValue = ''}) async {
    try {
      final result = await _invoke('document.getText', {'uri': null});
      return result is String ? result : defaultValue;
    } catch (_) {
      // Documented fallback contract: reads with defaultValue never propagate
      // bridge errors. Use [evaluateJavaScript] or a typed command if strict
      // failure visibility is required.
      return defaultValue;
    }
  }

  /// Replaces the entire content of the editor.
  ///
  /// If the editor is not yet ready, the value is queued and applied immediately
  /// after initialization.
  Future<void> setValue(String value) async {
    if (!_onReady.isCompleted) {
      _queuedValue = value;
      if (kIsWeb) return;
      await _ensureReady();
      if (_queuedValue == value) {
        // Only use queued value if it hasn't been overwritten
        _queuedValue = null;
      } else {
        return; // A newer value was queued, skip this one
      }
    }
    await _invoke('document.setText', {'uri': null, 'text': value});
  }

  /// Retrieves the current primary selection range.
  ///
  /// Returns `null` if no selection exists or the editor is not ready.
  Future<Range?> getSelection() async {
    try {
      final result = await _invoke('editor.getSelection', {});
      return result is Map
          ? Range.fromJson(Map<String, dynamic>.from(result))
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Selects the specified [range] in the editor.
  Future<void> setSelection(Range range) async {
    await _invoke('editor.setSelection', {'range': range.toJson()});
  }

  // --- NAVIGATION ---

  /// Reveal a line in the editor with validation
  Future<void> revealLine(int line, {bool center = false}) async {
    await revealRange(Range.lines(line, line), center: center);
  }

  /// Reveal a range in the editor
  Future<void> revealRange(Range range, {bool center = false}) async {
    await _invoke('editor.reveal', {'range': range.toJson(), 'center': center});
  }

  /// Reveal multiple lines in the editor
  Future<void> revealLines(
    int startLine,
    int endLine, {
    bool center = false,
  }) async {
    final range = Range.lines(startLine, endLine);
    await revealRange(range, center: center);
  }

  /// Reveal a position in the editor
  Future<void> revealPosition(Position position, {bool center = false}) async {
    final range = Range.fromPositions(position, position);
    await revealRange(range, center: center);
  }

  // --- LINE OPERATIONS ---

  /// Get the total line count with enhanced conversion
  Future<int> getLineCount({int defaultValue = 0}) async {
    try {
      final result = await _invoke('document.lineCount', {'uri': null});
      if (result is int) return result;
      if (result is num) return result.toInt();
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Get the content of a specific line with validation
  Future<String> getLineContent(int line, {String defaultValue = ''}) async {
    // Validate line number (JS clamps, so an out-of-range request would
    // otherwise return the nearest line instead of the documented default).
    final lineCount = await getLineCount();
    if (line < 1 || line > lineCount) return defaultValue;

    try {
      final result = await _invoke('document.getLines', {
        'uri': null,
        'startLine': line,
        'endLine': line,
      });
      return result is List && result.isNotEmpty
          ? (result.first?.toString() ?? defaultValue)
          : defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Get multiple lines content at once
  Future<List<String>> getLinesContent(
    List<int> lines, {
    String lineDefaultValue = '',
  }) async {
    final results = <String>[];
    if (lines.isEmpty) return results;

    final lineCount = await getLineCount();
    for (final line in lines) {
      if (line < 1 || line > lineCount) {
        results.add(lineDefaultValue);
        continue;
      }
      try {
        final result = await _invoke('document.getLines', {
          'uri': null,
          'startLine': line,
          'endLine': line,
        });
        results.add(
          result is List && result.isNotEmpty
              ? (result.first?.toString() ?? lineDefaultValue)
              : lineDefaultValue,
        );
      } catch (_) {
        results.add(lineDefaultValue);
      }
    }
    return results;
  }

  // --- EDITS ---

  /// Applies a list of edit operations to the document.
  ///
  /// This is the most efficient way to make multiple changes at once.
  Future<void> applyEdits(List<EditOperation> edits) async {
    if (edits.isEmpty) return;
    await _invoke('document.applyEdits', {
      'uri': null,
      'edits': edits.map((e) => e.toJson()).toList(),
    });
  }

  /// Inserts [text] at the specified [position].
  Future<void> insertText(Position position, String text) async {
    final edit = EditOperation.insert(position: position, text: text);
    await applyEdits([edit]);
  }

  /// Deletes the text within the specified [range].
  Future<void> deleteRange(Range range) async {
    final edit = EditOperation.delete(range: range);
    await applyEdits([edit]);
  }

  /// Replaces the text within [range] with [text].
  Future<void> replaceRange(Range range, String text) async {
    final edit = EditOperation(range: range, text: text);
    await applyEdits([edit]);
  }

  /// Deletes the specified [line] (1-based index).
  Future<void> deleteLine(int line) async {
    final range = Range.lines(line, line);
    await deleteRange(range);
  }

  // --- DECORATIONS ---

  /// Sets the decorations (highlights, glyphs, etc.) in the editor.
  ///
  /// Replaces any previously set decorations tracked by this controller.
  /// Returns the IDs of the newly created decorations.
  Future<List<String>> setDecorations(
    List<DecorationOptions> decorations,
  ) async {
    final raw = await _invoke('decorations.delta', {
      'previousIds': _decorationIds,
      'decorations': decorations.map((d) => d.toJson()).toList(),
    });
    if (raw is! List) {
      throw MonacoJavaScriptException(
        operation: 'decorations.delta',
        message: 'Expected deltaDecorations to return a list of IDs.',
        details: raw,
      );
    }

    return _decorationIds = raw
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Adds inline style decorations (e.g., text color, background) to specific [ranges].
  ///
  /// [className] should be a CSS class available in the WebView (injected via `customCss`).
  Future<List<String>> addInlineDecorations(
    List<Range> ranges,
    String className, {
    String? hoverMessage,
  }) async {
    final decorations = ranges
        .map(
          (range) => DecorationOptions.inlineClass(
            range: range,
            className: className,
            hoverMessage: hoverMessage,
          ),
        )
        .toList();

    return setDecorations(decorations);
  }

  /// Adds decorations to entire lines (e.g., for breakpoints or diffs).
  Future<List<String>> addLineDecorations(
    List<int> lines,
    String className, {
    bool isWholeLine = true,
  }) async {
    final decorations = lines
        .map(
          (line) => DecorationOptions.line(
            range: Range.singleLine(line),
            className: className,
            isWholeLine: isWholeLine,
          ),
        )
        .toList();

    return setDecorations(decorations);
  }

  /// Removes all decorations set by this controller.
  Future<void> clearDecorations() => setDecorations(const []);

  // --- MARKERS (DIAGNOSTICS) ---

  /// Sets the diagnostics (errors, warnings, hints) for the editor.
  ///
  /// [owner] is a string identifier for the source of these markers.
  Future<void> setMarkers(
    List<MarkerData> markers, {
    String owner = 'flutter',
  }) async {
    await _invoke('document.setMarkers', {
      'uri': null,
      'owner': owner,
      'markers': markers.map((m) => m.toJson()).toList(),
    });
  }

  /// Convenience method to set error markers.
  Future<void> setErrorMarkers(
    List<MarkerData> errors, {
    String owner = 'flutter-errors',
  }) async {
    await setMarkers(errors, owner: owner);
  }

  /// Convenience method to set warning markers.
  Future<void> setWarningMarkers(
    List<MarkerData> warnings, {
    String owner = 'flutter-warnings',
  }) async {
    await setMarkers(warnings, owner: owner);
  }

  /// Clears all markers for the specified [owner].
  Future<void> clearMarkers({String owner = 'flutter'}) async {
    await setMarkers([], owner: owner);
  }

  /// Clears all markers from common owners ('flutter', 'flutter-errors', 'flutter-warnings').
  Future<void> clearAllMarkers() async {
    await Future.wait([
      clearMarkers(owner: 'flutter'),
      clearMarkers(owner: 'flutter-errors'),
      clearMarkers(owner: 'flutter-warnings'),
    ]);
  }

  // --- FIND AND REPLACE ---

  /// Find matches in the document with enhanced parsing
  Future<List<FindMatch>> findMatches(
    String query, {
    FindOptions options = const FindOptions(),
    int limit = 1000,
  }) async {
    try {
      final matches = await _invoke('document.findMatches', {
        'uri': null,
        'query': query,
        'isRegex': options.isRegex,
        'matchCase': options.matchCase,
        'wholeWord': options.wholeWord,
        'limit': limit,
      });
      if (matches is! List || matches.isEmpty) return [];
      return matches
          .whereType<Map>()
          .map((match) => FindMatch.fromJson(Map<String, dynamic>.from(match)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Replace all matches in the document
  Future<int> replaceMatches(
    String query,
    String replacement, {
    FindOptions options = const FindOptions(),
    int defaultCount = 0,
  }) async {
    try {
      final result = await _invoke('document.replaceMatches', {
        'uri': null,
        'query': query,
        'replacement': replacement,
        'isRegex': options.isRegex,
        'matchCase': options.matchCase,
        'wholeWord': options.wholeWord,
      });
      if (result is int) return result;
      if (result is num) return result.toInt();
      return defaultCount;
    } catch (_) {
      return defaultCount;
    }
  }

  // --- VIEW STATE ---

  /// Save the current view state with enhanced conversion
  Future<Map<String, dynamic>> saveViewState() async {
    try {
      final result = await _invoke('editor.captureViewState', {});
      return result is Map ? Map<String, dynamic>.from(result) : {};
    } catch (_) {
      return {};
    }
  }

  /// Restore a previously saved view state
  Future<void> restoreViewState(Map<String, dynamic> state) async {
    if (state.isEmpty) return;
    await _invoke('editor.restoreViewState', {'state': state});
  }

  // --- MULTI-MODEL ---

  /// Create a new model with enhanced URI handling
  Future<Uri> createModel(
    String value, {
    String language = 'plaintext',
    Uri? uri,
    Uri? defaultUri,
  }) async {
    final result = await _invoke('docs.open', {
      'text': value,
      'language': language,
      'uri': uri?.toString(),
    });

    final createdUri = result is String ? Uri.tryParse(result) : null;
    if (createdUri != null) {
      return createdUri;
    }
    if (defaultUri != null) {
      return defaultUri;
    }
    throw StateError('docs.open returned invalid uri: $result');
  }

  /// Set the active model
  Future<void> setModel(Uri uri) async {
    await _invoke('docs.activate', {'uri': uri.toString()});
  }

  /// Dispose a model
  Future<void> disposeModel(Uri uri) async {
    await _invoke('docs.close', {'uri': uri.toString()});
  }

  /// List all models with enhanced conversion
  Future<List<Uri>> listModels() async {
    try {
      final list = await _invoke('docs.list', {});
      if (list is! List || list.isEmpty) return [];
      return list
          .map((e) => Uri.tryParse(e.toString()))
          .whereType<Uri>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // --- ADDITIONAL HELPER METHODS ---

  /// Get editor statistics from the live stats stream
  LiveStats getStatistics() {
    return _liveStats.value;
  }

  /// Check if the editor has unsaved changes
  Future<bool> hasUnsavedChanges() async {
    try {
      final result = await _invoke('document.isDirty', {'uri': null});
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Mark the current content as saved (baseline for dirty tracking)
  Future<void> markSaved() async {
    await _invoke('document.markSaved', {'uri': null});
  }

  /// Get cursor position with enhanced conversion
  Future<Position?> getCursorPosition() async {
    try {
      final result = await _invoke('editor.getCursor', {});
      return result is Map
          ? Position.fromJson(Map<String, dynamic>.from(result))
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Set cursor position
  Future<void> setCursorPosition(Position position) async {
    await _invoke('editor.setCursor', {
      'position': {'lineNumber': position.line, 'column': position.column},
    });
  }

  /// Set cursor position from zero-based coordinates
  Future<void> setCursorPositionZeroBased(int line, int column) async {
    final position = Position.fromZeroBased(line, column);
    await setCursorPosition(position);
  }

  /// Get word at position
  Future<String?> getWordAtPosition(Position position) async {
    try {
      final result = await _invoke('document.getWordAt', {
        'uri': null,
        'position': {'lineNumber': position.line, 'column': position.column},
      });
      return result is String ? result : null;
    } catch (_) {
      return null;
    }
  }

  // --- BATCH OPERATIONS ---

  /// Execute multiple operations in batch
  Future<void> executeBatch(List<Future<void> Function()> operations) async {
    for (final operation in operations) {
      await operation();
    }
  }

  /// Get multiple editor properties at once
  Future<EditorState> getEditorState() async {
    final content = await getValue();
    final selection = await getSelection();
    final cursorPosition = await getCursorPosition();
    final lineCount = await getLineCount();
    final hasChanges = await hasUnsavedChanges();
    final stats = getStatistics(); // Now synchronous

    return EditorState(
      content: content,
      selection: selection,
      cursorPosition: cursorPosition,
      lineCount: lineCount,
      hasUnsavedChanges: hasChanges,
      language: stats.language,
      theme: null,
      // Would need a separate API call to get theme
      stats: stats,
    );
  }

  // --- LANGUAGE SERVER PROTOCOL ---

  /// Connects the editor to a language server and returns a handle to the
  /// live connection.
  ///
  /// Monaco's built-in LSP client (Monaco 0.55+) registers every language
  /// feature the server advertises - completions, hover, go-to-definition,
  /// references, rename, formatting, code actions, folding, inlay hints,
  /// semantic tokens, and diagnostics - directly inside the editor. After
  /// this call resolves, the editor "just works"; nothing needs to be
  /// mirrored into Dart.
  ///
  /// The call waits for editor readiness, establishes the [transport], and
  /// resolves only after the LSP `initialize` handshake completes. On
  /// failure (unreachable server, CSP-blocked WebSocket, handshake timeout)
  /// it throws and no connection is registered.
  ///
  /// * [id]: Unique identifier for this connection within the controller.
  ///   Reusing an id that is still connected throws a [StateError].
  /// * [transport]: Where the server lives - [LspWebSocketTransport],
  ///   [LspBridgedTransport] (see [LspServerProcess] for local stdio servers
  ///   on desktop), or [LspCustomTransport].
  /// * [reconnectPolicy]: Optional automatic reconnect for unexpected
  ///   transport drops after the connection was open. Defaults to no
  ///   reconnecting. Not supported for bridged transports.
  /// * [initializationTimeout]: Upper bound for transport setup plus the
  ///   `initialize` handshake, per attempt.
  ///
  /// ### Model URIs matter
  ///
  /// Language servers key their state on document URIs. Create models with
  /// stable, file-like URIs ([createModel] with a `file:///...` uri) so the
  /// server can associate diagnostics and cross-file features correctly.
  ///
  /// ### Scoping and multiple servers
  ///
  /// Monaco's LSP client synchronizes **all** models to the server and
  /// scopes feature providers by the server's advertised
  /// `documentSelector`s. Servers that advertise capabilities without a
  /// selector are registered for every language. Multiple concurrent
  /// connections are allowed, but note that LSP diagnostics from all
  /// connections share the Monaco marker owner `'lsp'` - prefer one server
  /// per editor unless your servers publish diagnostics for disjoint files.
  ///
  /// ### Example (WebSocket)
  ///
  /// ```dart
  /// final controller = await MonacoController.create(
  ///   allowedConnectSources: ['ws://127.0.0.1:3000'],
  /// );
  /// final connection = await controller.connectLanguageServer(
  ///   id: 'pyright',
  ///   transport: LspWebSocketTransport(
  ///     url: Uri.parse('ws://127.0.0.1:3000/python'),
  ///   ),
  /// );
  /// connection.stateChanges.listen(print);
  /// ```
  Future<LanguageServerConnection> connectLanguageServer({
    required String id,
    required LspTransport transport,
    LspReconnectPolicy reconnectPolicy = const LspReconnectPolicy.none(),
    Duration initializationTimeout = const Duration(seconds: 30),
  }) async {
    await _ensureReady();
    return _lspManager.connect(
      id: id,
      transport: transport,
      reconnectPolicy: reconnectPolicy,
      initializationTimeout: initializationTimeout,
    );
  }

  /// Disconnects the language server connection registered under [id].
  ///
  /// No-op when the id is unknown or already closed. Equivalent to calling
  /// `disconnect()` on the [LanguageServerConnection] handle.
  Future<void> disconnectLanguageServer(String id) {
    return _lspManager.disconnect(id);
  }

  /// The language server connections that have not permanently closed.
  List<LanguageServerConnection> get languageServerConnections =>
      _lspManager.connections;

  /// The active language server connection registered under [id], or `null`.
  LanguageServerConnection? languageServerConnection(String id) =>
      _lspManager.connection(id);

  // --- JAVASCRIPT ESCAPE HATCH ---

  /// Executes arbitrary JavaScript in the editor WebView.
  ///
  /// This is an advanced escape hatch for scenarios not covered by the typed
  /// Dart API. Prefer typed [MonacoController] methods such as [setValue],
  /// [getSelection], [setMarkers], and [executeAction] when they cover your
  /// use case.
  ///
  /// Useful for configuring Monaco language services, such as JSON schemas or
  /// TypeScript options, or for calling Monaco APIs not yet wrapped by this
  /// package.
  ///
  /// Loading third-party plugin scripts at runtime requires bundling those
  /// scripts with your app and respecting the editor page's
  /// Content-Security-Policy. The default CSP does not allow remote script
  /// origins.
  ///
  /// Waits for the editor to be ready before executing.
  ///
  /// ## Security
  ///
  /// Do not interpolate untrusted or user-provided values directly into
  /// [script]. This is raw JavaScript execution and string concatenation can
  /// create a script-injection vulnerability. Use `jsonEncode` for dynamic
  /// values:
  ///
  /// ```dart
  /// // Bad if userInput is attacker-controlled.
  /// await controller.runJavaScript('window.setName("$userInput")');
  ///
  /// // Good: jsonEncode creates a safe JavaScript literal.
  /// await controller.runJavaScript(
  ///   'window.setName(${jsonEncode(userInput)})',
  /// );
  /// ```
  ///
  /// See also:
  /// - [evaluateJavaScript] for typed, cross-platform result normalization.
  /// - [runJavaScriptReturningResultRaw] for raw platform return values.
  Future<void> runJavaScript(String script) async {
    await _ensureReady();
    await _webViewController.runJavaScript(script);
  }

  /// Evaluates a JavaScript expression and returns a Dart value of type [T].
  ///
  /// This is the recommended way to read values from the editor's JavaScript
  /// context. It normalizes platform differences so numeric, boolean, string,
  /// list, map, and null values behave consistently across supported
  /// platforms (the expression rides the `page.eval` protocol command).
  ///
  /// [expression] must be a JavaScript expression. For multi-statement logic,
  /// pass an IIFE expression:
  ///
  /// ```dart
  /// final count = await controller.evaluateJavaScript<int>(
  ///   '(() => { const editors = monaco.editor.getEditors(); return editors.length; })()',
  /// );
  /// ```
  ///
  /// Returns [defaultValue] when the expression returns `undefined`, when the
  /// decoded value is `null`, or when the value cannot be converted to [T].
  ///
  /// JavaScript execution errors are allowed to propagate. This keeps raw
  /// JavaScript integrations easier to debug.
  ///
  /// ## Security
  ///
  /// Same caveat as [runJavaScript]: do not interpolate untrusted input into
  /// [expression]. Use `jsonEncode` for dynamic values.
  ///
  /// ## JSON compatibility
  ///
  /// The returned JavaScript value must be JSON-serializable. Values such as
  /// functions, symbols, BigInts, DOM nodes, and circular objects are not
  /// supported by this typed evaluator. Use [runJavaScriptReturningResultRaw]
  /// if you need raw platform behavior.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final editorCount = await controller.evaluateJavaScript<int>(
  ///   'monaco.editor.getEditors().length',
  /// );
  /// ```
  Future<T?> evaluateJavaScript<T>(String expression, {T? defaultValue}) async {
    await _ensureReady();
    final result = await _protocol.invoke('page.eval', {
      'expression': expression,
    });
    if (identical(result, monacoJsUndefined) || result == null) {
      return defaultValue;
    }
    if (result is T) return result as T;
    // Number normalization: platforms and JSON round-trips blur int/double.
    if (T == int && result is num) return result.toInt() as T;
    if (T == double && result is num) return result.toDouble() as T;
    if (T == String) return result.toString() as T;
    return defaultValue;
  }

  /// Executes JavaScript and returns the platform-native result.
  ///
  /// Advanced use only. Return types vary by platform:
  ///
  /// - iOS, macOS, and Web usually return native Dart values.
  /// - Android may return JSON-encoded strings.
  /// - Windows WebView2 may return strings where numeric and boolean literals
  ///   remain strings.
  ///
  /// Prefer [evaluateJavaScript] for cross-platform consistency. Use this
  /// method only when you specifically need the raw platform return shape, for
  /// example for debugging or advanced WebView interop.
  ///
  /// Waits for the editor to be ready before executing.
  ///
  /// ## Security
  ///
  /// Same caveat as [runJavaScript].
  Future<Object?> runJavaScriptReturningResultRaw(String script) async {
    await _ensureReady();
    return _webViewController.runJavaScriptReturningResult(script);
  }

  // --- HELPERS ---
  /// Dispose the controller and clean up resources
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // LSP connections must come down before the WebView: closing them fires
    // bridged-transport onClose callbacks (e.g. killing server processes)
    // and finalizes connection state streams.
    _lspManager.dispose();
    _eventSubscription?.cancel();
    _onContentChanged.close();
    _onSelectionChanged.close();
    _onFocus.close();
    _onBlur.close();
    _onScrollHandoff.close();
    _liveStats.dispose();
    _protocol.dispose();
    _webViewController.dispose();
  }
}

class _RegisteredCompletion {
  _RegisteredCompletion({
    required this.id,
    required this.languages,
    required this.triggerCharacters,
    required this.provider,
  });

  final String id;
  final List<String> languages;
  final List<String> triggerCharacters;
  final CompletionProvider provider;
}
