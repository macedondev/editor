import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/editor/focus_coordinator.dart';
import 'package:flutter_monaco/src/lsp/lsp_connection.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';
import 'package:flutter_monaco/src/protocol/envelope.dart';
import 'package:flutter_monaco/src/protocol/protocol.dart';

/// A callback function that provides completion items for a given
/// [CompletionRequest]. It should return a [Future] that resolves to a
/// [CompletionList].
typedef CompletionProvider =
    Future<CompletionList> Function(CompletionRequest request);

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
  final ValueNotifier<MonacoLiveStats> _liveStats = ValueNotifier(
    const MonacoLiveStats(),
  );

  // Decoded editor events (sealed MonacoEvent union).
  final _events = StreamController<MonacoEvent>.broadcast();
  StreamSubscription<ProtocolEvent>? _eventSubscription;

  late final MonacoFocusCoordinator _focus = MonacoFocusCoordinator(
    webView: _webViewController,
    ensureReady: _ensureReady,
    invoke: (method, params) => _protocol.invoke(method, params),
    isInteractionEnabled: () => _interactionEnabled,
  );

  /// The active-tracking document handle: every call targets whatever
  /// model is currently attached to the editor. See [MonacoDocument].
  late final MonacoDocument document = MonacoDocument.internal(_invoke, null);

  final Map<String, _RegisteredCompletion> _completionSources = {};
  bool _completionListenerWired = false;
  MonacoCapabilities? _capabilities;

  /// Completes when the editor is fully initialized and ready to accept
  /// commands. Completes with the boot error if initialization fails
  /// (asset load, page load, protocol handshake, or editor creation).
  ///
  /// [create] returns immediately on every platform; await this future (or
  /// use the `MonacoEditor` widget, which renders loading/error chrome) for
  /// readiness.
  Future<void> get whenReady => _onReady.future;

  /// Returns `true` if the editor has finished initializing successfully.
  bool get isReady => _onReady.isCompleted && _readyCompletedOk;
  bool _readyCompletedOk = false;

  /// What the loaded page can do, from the protocol handshake.
  ///
  /// Throws [StateError] before [whenReady] completes.
  MonacoCapabilities get capabilities {
    final capabilities = _capabilities;
    if (capabilities == null) {
      throw StateError(
        'capabilities is only available after whenReady completes.',
      );
    }
    return capabilities;
  }

  /// Returns `true` if the editor currently accepts user interaction.
  bool get isInteractionEnabled => _interactionEnabled;

  /// Real-time statistics (cursor position, selection, line count).
  ValueListenable<MonacoLiveStats> get stats => _liveStats;

  /// Every decoded editor event, in arrival order.
  ///
  /// The union is sealed for exhaustive switching; unknown events surface
  /// as [MonacoUnknownEvent]. Prefer the typed convenience streams below
  /// for single-concern listeners.
  Stream<MonacoEvent> get events => _events.stream;

  /// Content changes ([MonacoContentChanged]: flush flag, deltas or a
  /// truncation marker).
  Stream<MonacoContentChanged> get onContentChanged =>
      events.where((e) => e is MonacoContentChanged).cast();

  /// The new primary [Range] (or `null`) whenever the selection changes.
  Stream<Range?> get onSelectionChanged => events
      .where((e) => e is MonacoSelectionChanged)
      .map((e) => (e as MonacoSelectionChanged).selection);

  /// Monaco DOM focus transitions (`true` = focused).
  ///
  /// This is not a native input-readiness guarantee on desktop platform
  /// views; see [hasNativeInputFocus] for the authoritative signal.
  Stream<bool> get onFocusChanged => events
      .where((e) => e is MonacoFocusChanged)
      .map((e) => (e as MonacoFocusChanged).focused);

  /// Scroll deltas the editor could not consume.
  ///
  /// Events only arrive after a source was enabled with
  /// [setScrollHandoffSources] (the `MonacoEditor.scrollHandoff`
  /// configuration does this automatically). Malformed bridge payloads are
  /// dropped silently. See [MonacoScrollHandoffDetails] for the delta
  /// conventions.
  Stream<MonacoScrollHandoffDetails> get onScrollHandoff => events
      .where((e) => e is MonacoScrollHandoffEvent)
      .map((e) => (e as MonacoScrollHandoffEvent).details);

  /// Creates a new [MonacoController] and boots the editor.
  ///
  /// Returns immediately on every platform (the WebView is created and the
  /// page load + boot continue in the background). Await [whenReady] before
  /// issuing commands directly, or hand the controller to the `MonacoEditor`
  /// widget, which renders loading and error chrome. Boot failures complete
  /// [whenReady] with the error.
  ///
  /// The editor is born configured: [options], [initialText], the language,
  /// and the theme travel in the `page.boot` command and apply before the
  /// first frame paints - there is no default-theme flash and no
  /// post-ready re-apply.
  ///
  /// * [options]: Initial configuration (theme, language, fonts, ...).
  /// * [initialText]: Initial document contents (never written to disk; it
  ///   travels over the protocol).
  /// * [page]: Page-level settings (custom CSS, CSP opt-ins). See
  ///   [MonacoPageConfig]; changing these requires a new controller.
  /// * [readyTimeout]: Upper bound for the whole boot (asset extraction
  ///   excluded); on expiry [whenReady] completes with a
  ///   [MonacoTimeoutError].
  static Future<MonacoController> create({
    EditorOptions? options,
    String? initialText,
    MonacoPageConfig page = const MonacoPageConfig(),
    Duration readyTimeout = const Duration(seconds: 20),
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
      controller._startBoot(
        options: options,
        initialText: initialText,
        page: page,
        readyTimeout: readyTimeout,
      );
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

  /// Runs the two-phase boot: load page, await pageReady, dispatch
  /// page.boot, await editor ready. Uniform on all platforms; failures land
  /// in [whenReady].
  void _startBoot({
    required EditorOptions? options,
    required String? initialText,
    required MonacoPageConfig page,
    required Duration readyTimeout,
  }) {
    // Curated defaults under the caller's sparse options (caller wins).
    // A null theme falls back to the dark default here; the MonacoEditor
    // widget resolves it from the surrounding Flutter brightness instead.
    final bootOptions = MonacoDefaults.editorOptions.merge(options);
    final bootLanguage = bootOptions.language ?? MonacoDefaults.language;
    final bootTheme = bootOptions.theme ?? MonacoDefaults.darkTheme;
    // Boot failures must reach callers through [whenReady] (and the commands
    // gated on it), never as an unhandled zone error when nobody awaits it.
    _onReady.future.ignore();
    unawaited(() async {
      try {
        await () async {
          await _webViewController.load(page: page);
          debugPrint(
            '[MonacoController] Page loading (Platform: '
            '${kIsWeb ? 'Web' : defaultTargetPlatform.name})',
          );

          final handshake = await _protocol.pageReady;
          _capabilities = MonacoCapabilities.fromHandshake(handshake);

          // Boot the editor with the merged initial state; the response
          // acknowledges acceptance, the ready lifecycle follows creation.
          await _protocol.invoke('page.boot', {
            'options': bootOptions.toMonacoOptions(),
            'text': initialText ?? '',
            'language': bootLanguage.id,
            'theme': bootTheme.id,
            'scrollHandoff': const {'wheel': false, 'touch': false},
          }, timeout: null);

          await _protocol.editorReady;
        }().timeout(
          readyTimeout,
          onTimeout: () => throw MonacoTimeoutError(
            message:
                'Monaco Editor did not report ready in '
                '${readyTimeout.inSeconds} seconds.',
            timeout: readyTimeout,
            operation: 'boot',
          ),
        );

        _readyCompletedOk = true;
        if (!_onReady.isCompleted) {
          _onReady.complete();
        }
      } catch (e, st) {
        if (!_onReady.isCompleted) {
          _onReady.completeError(e, st);
        }
      }
    }());
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
    _readyCompletedOk = true;
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
  /// Accepts both built-in themes ([MonacoTheme.vsDark], ...) and custom
  /// ids previously registered with [defineTheme]:
  /// `setTheme(MonacoTheme('app-dark'))`. Throws an [ArgumentError] when
  /// the id is empty so callers don't silently activate Monaco's
  /// empty-string fallback. Waits for the editor to be ready.
  Future<void> setTheme(MonacoTheme theme) async {
    if (theme.id.trim().isEmpty) {
      throw ArgumentError.value(
        theme.id,
        'theme',
        'theme id must be a non-empty string',
      );
    }
    await _invoke('editor.setTheme', {'theme': theme.id});
  }

  /// Returns the theme currently active in the editor.
  ///
  /// Reads the live value from Monaco's runtime rather than caching what
  /// Dart most recently sent. Returns `null` when Monaco can't report a
  /// theme (e.g. on engine versions that don't expose `editor.getTheme()`).
  /// Bridge failures throw a [MonacoException].
  Future<MonacoTheme?> getTheme() async {
    final result = await _invoke('editor.getTheme', {});
    return result is String && result.isNotEmpty ? MonacoTheme(result) : null;
  }

  /// Registers or replaces a custom Monaco theme.
  ///
  /// After registration, activate the theme with
  /// `setTheme(MonacoTheme(theme.id))` or by setting
  /// [EditorOptions.theme]. For theme data that only exists as raw
  /// Monaco-shaped JSON, build the definition with
  /// [MonacoThemeDefinition.fromMonacoThemeData]. Throws an
  /// [ArgumentError] when the id is empty.
  Future<void> defineTheme(MonacoThemeDefinition theme) async {
    if (theme.id.trim().isEmpty) {
      throw ArgumentError.value(
        theme.id,
        'theme',
        'theme id must be a non-empty string',
      );
    }
    await _invoke('editor.defineTheme', {
      'id': theme.id,
      'data': theme.toMonacoThemeData(),
    });
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
    await _invoke('completions.unregister', {'id': id});
  }

  /// Runs a Monaco editor action, e.g.
  /// `executeAction(MonacoAction.formatDocument)`. Custom command ids run
  /// via `MonacoAction('my.command')`.
  Future<void> executeAction(MonacoAction action, {Object? args}) async {
    await _invoke('editor.executeAction', {
      'actionId': action.id,
      'args': args,
    });
  }

  /// Requests editor focus, retrying to ride out layout transitions.
  ///
  /// Cooperative by default: background [MonacoFocusIntent.maintenance]
  /// calls never steal the keyboard from a focused Flutter text input.
  /// Pass [MonacoFocusIntent.user] only from direct pointer interaction
  /// with the editor. See [MonacoFocusCoordinator.requestFocus] for the
  /// full platform decision table.
  Future<void> requestFocus({
    MonacoFocusIntent intent = MonacoFocusIntent.maintenance,
    int attempts = 3,
    Duration interval = const Duration(milliseconds: 24),
  }) {
    return _focus.requestFocus(
      intent: intent,
      attempts: attempts,
      interval: interval,
    );
  }

  /// Whether the native layer currently routes keyboard input to the
  /// editor's WebView.
  ///
  /// `true`/`false` where the platform can answer authoritatively (macOS
  /// first responder, Windows WebView2); `null` where it cannot (Android,
  /// iOS, Web, headless tests). This is the real desktop input-readiness
  /// signal - [onFocusChanged] only reports Monaco's DOM focus.
  Future<bool?> hasNativeInputFocus() => _focus.hasNativeInputFocus();

  /// Hands native keyboard focus back to the Flutter view if the editor's
  /// WebView currently holds it. No-op elsewhere.
  Future<void> releaseNativeFocus() => _focus.releaseNativeFocus();

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

  // --- EVENT HANDLING ---

  /// Wire up protocol event listeners.
  void _wireEvents() {
    _eventSubscription = _protocol.events.listen((event) {
      // Stats feed the ValueListenable, not the public event union.
      if (event.name == 'stats') {
        try {
          _liveStats.value = MonacoLiveStats.fromJson(
            Map<String, dynamic>.from(event.data),
          );
        } catch (e) {
          debugPrint('[MonacoController] Failed to parse stats: $e');
        }
        return;
      }
      // LSP internals are consumed by the LSP manager, not surfaced here.
      if (event.name == 'lspStatus' ||
          event.name == 'lspMessage' ||
          event.name == 'completionRequest') {
        return;
      }
      _events.add(MonacoEvent.fromProtocolEvent(event));
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

  // --- SELECTION AND NAVIGATION ---

  /// Retrieves the current primary selection range.
  ///
  /// Returns `null` when the editor reports no selection. Bridge failures
  /// throw a [MonacoException].
  Future<Range?> getSelection() async {
    final result = await _invoke('editor.getSelection', {});
    return result is Map
        ? Range.fromJson(Map<String, dynamic>.from(result))
        : null;
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

  /// Reveal a position in the editor
  Future<void> revealPosition(Position position, {bool center = false}) async {
    final range = Range.fromPositions(position, position);
    await revealRange(range, center: center);
  }

  // --- DECORATIONS ---

  /// Creates an independent decoration set.
  ///
  /// Each set wraps one Monaco decorations collection: setting it replaces
  /// only that set's decorations, so multiple features can decorate the
  /// editor without clobbering each other. Dispose the set to remove its
  /// decorations and release the page-side collection.
  Future<MonacoDecorationSet> createDecorationSet() async {
    final result = await _invoke('decorations.create', {});
    if (result is String && result.isNotEmpty) {
      return MonacoDecorationSet.internal(_invoke, result);
    }
    throw MonacoProtocolError(
      operation: 'decorations.create',
      message: 'Expected a decoration set id, got ${result.runtimeType}.',
    );
  }

  // --- VIEW STATE ---

  /// Captures the current view state (cursor, scroll, folding) as an
  /// opaque, persistable [MonacoViewState].
  ///
  /// Returns an empty state when the editor has no model to capture.
  /// Throws a [MonacoException] on failure.
  Future<MonacoViewState> captureViewState() async {
    final result = await _invoke('editor.captureViewState', {});
    return MonacoViewState.fromJson(
      result is Map ? Map<String, Object?>.from(result) : const {},
    );
  }

  /// Restores a previously captured view state.
  Future<void> restoreViewState(MonacoViewState state) async {
    if (state.isEmpty) return;
    await _invoke('editor.restoreViewState', {'state': state.toJson()});
  }

  // --- DOCUMENTS ---

  /// Opens a new document (Monaco model) and returns a pinned handle.
  ///
  /// Give language servers stable, file-like URIs (`file:///...`) so they
  /// can associate diagnostics and cross-file features correctly. Opening
  /// a document does not activate it; call [activateDocument].
  Future<MonacoDocument> openDocument({
    required String text,
    MonacoLanguage language = MonacoLanguage.plaintext,
    Uri? uri,
  }) async {
    final result = await _invoke('docs.open', {
      'text': text,
      'language': language.id,
      'uri': uri?.toString(),
    });
    final createdUri = result is String ? Uri.tryParse(result) : null;
    if (createdUri == null) {
      throw MonacoProtocolError(
        operation: 'docs.open',
        message: 'Expected a model URI string, got: $result',
      );
    }
    return MonacoDocument.internal(_invoke, createdUri);
  }

  /// Attaches [document] to the editor (making it the active model).
  ///
  /// Throws [ArgumentError] for the active-tracking handle (it has no URI
  /// to activate).
  Future<void> activateDocument(MonacoDocument document) async {
    final uri = document.uri;
    if (uri == null) {
      throw ArgumentError.value(
        document,
        'document',
        'The active-tracking handle is already active; pass a pinned '
            'handle from openDocument/documentByUri/listDocuments.',
      );
    }
    await _invoke('docs.activate', {'uri': uri.toString()});
  }

  /// Pinned handles for every open document.
  Future<List<MonacoDocument>> listDocuments() async {
    final list = await _invoke('docs.list', {});
    if (list is! List) {
      throw MonacoProtocolError(
        operation: 'docs.list',
        message: 'Expected a list of model URIs, got ${list.runtimeType}.',
      );
    }
    return list
        .map((e) => Uri.tryParse(e.toString()))
        .whereType<Uri>()
        .map((uri) => MonacoDocument.internal(_invoke, uri))
        .toList();
  }

  /// A pinned handle for [uri] without a bridge round trip.
  ///
  /// The handle is constructed locally; calls through it throw a
  /// [MonacoJavaScriptError] if no document with that URI is open.
  MonacoDocument documentByUri(Uri uri) =>
      MonacoDocument.internal(_invoke, uri);

  /// Returns the current cursor position.
  ///
  /// Returns `null` when the editor reports no cursor. Throws a
  /// [MonacoException] on bridge failure.
  Future<Position?> getCursorPosition() async {
    final result = await _invoke('editor.getCursor', {});
    return result is Map
        ? Position.fromJson(Map<String, dynamic>.from(result))
        : null;
  }

  /// Set cursor position
  Future<void> setCursorPosition(Position position) async {
    await _invoke('editor.setCursor', {
      'position': {'lineNumber': position.line, 'column': position.column},
    });
  }

  /// Returns a full editor snapshot in ONE bridge round trip
  /// (`editor.getState`).
  Future<EditorState> getEditorState() async {
    final result = await _invoke('editor.getState', {});
    if (result is! Map) {
      throw MonacoProtocolError(
        operation: 'editor.getState',
        message: 'Expected a state map, got ${result.runtimeType}.',
      );
    }
    return EditorState.fromJson(Map<String, dynamic>.from(result));
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
  /// Dart API. Prefer the typed surface - [document] methods such as
  /// `setText`/`setMarkers`, [getSelection], and [executeAction] - when it
  /// covers your use case.
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
  /// Returns [defaultValue] (default `null`) when the expression returns
  /// `undefined` or `null`. Throws a [MonacoProtocolError] when the value
  /// cannot be converted to [T]; JavaScript execution errors propagate as
  /// [MonacoJavaScriptError].
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
    throw MonacoProtocolError(
      operation: 'page.eval',
      message:
          'Expression result of type ${result.runtimeType} cannot be '
          'converted to $T.',
    );
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
    _events.close();
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
