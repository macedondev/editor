part of 'webview_native.dart';

/// WebView implementation for Windows using Microsoft Edge WebView2.
///
/// This controller wraps the `webview_flutter_windows` package to provide Monaco editor
/// hosting on Windows. It requires the WebView2 runtime, which is pre-installed
/// on Windows 11 and available as a separate download for Windows 10.
///
/// ### JavaScript Communication
///
/// Unlike `webview_flutter`, WebView2 uses `chrome.webview.postMessage` for
/// native communication. However, the Monaco HTML defines a `window.flutterChannel`
/// shim that forwards to this API, providing a consistent interface.
///
/// Messages are received via the [webMessage] stream and dispatched to all
/// registered channel handlers in [_channels].
///
/// ### Result Parsing
///
/// WebView2's `ExecuteScript` returns JSON-encoded results, which may need
/// unwrapping. Use [parseWindowsScriptResult] to normalize return values.
///
/// ### Initialization
///
/// The first call to [initialize] may take longer if WebView2 needs to
/// install its runtime. Subsequent initializations are fast.
///
/// See also:
/// - [FlutterWebViewController] for Android/iOS/macOS implementation.
/// - [ww.WebviewController] for the underlying Windows WebView controller.
/// - [parseWindowsScriptResult] for result normalization.
class WindowsWebViewController extends WebViewController {
  /// Creates a new controller backed by `webview_flutter_windows` (WebView2).
  WindowsWebViewController() : super._() {
    _controller = ww.WebviewController();
  }

  @override
  Widget get widget => ww.Webview(_controller);

  late final ww.WebviewController _controller;
  final Map<String, void Function(String)> _channels = {};
  StreamSubscription<dynamic>? _webMessageSubscription;
  bool _isInitialized = false;
  bool _disposed = false;

  /// Provides direct access to the underlying `webview_flutter_windows` controller.
  ///
  /// Use this for advanced operations not exposed by [PlatformWebViewController],
  /// such as custom popup policies or DevTools access.
  ww.WebviewController get windowsController => _controller;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('[WindowsWebViewController] Initializing WebView2...');
    await _controller.initialize();
    _isInitialized = true;

    // Set up default configuration
    await _controller.setBackgroundColor(const Color(0xFF1E1E1E));
    await _controller.setPopupWindowPolicy(ww.WebviewPopupWindowPolicy.deny);

    // Set up message handler BEFORE adding any channels
    _setupWebMessageHandler();

    debugPrint('[WindowsWebViewController] WebView2 initialized successfully');
  }

  void _setupWebMessageHandler() {
    _webMessageSubscription?.cancel();

    _webMessageSubscription = _controller.webMessage.listen((
      dynamic rawMessage,
    ) {
      if (kDebugMode) {
        debugPrint(
          '[WindowsWebViewController] Raw message: $rawMessage (${rawMessage.runtimeType})',
        );
      }

      try {
        String messageStr;

        if (rawMessage is String) {
          messageStr = rawMessage;
        } else if (rawMessage is Map) {
          messageStr = json.encode(rawMessage);
        } else {
          messageStr = rawMessage.toString();
        }

        _channels.forEach((channelName, handler) {
          if (kDebugMode) {
            debugPrint(
              '[WindowsWebViewController] Forwarding to channel: $channelName',
            );
          }
          handler(messageStr);
        });
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WindowsWebViewController] Error handling message: $e');
        }
      }
    });
  }

  /// Loads the given HTML string into the WebView.
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    debugPrint(
      '[WindowsWebViewController] Loading HTML string (length: ${html.length})',
    );
    await _controller.loadStringContent(html);
  }

  @override
  Future<void> load({MonacoPageConfig page = const MonacoPageConfig()}) async {
    final htmlFilePath = await _ensureHtmlFile(page);
    await _controller.loadUrl(Uri.file(htmlFilePath).toString());
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    await _controller.setBackgroundColor(color);
  }

  @override
  Future<void> setInteractionEnabled(bool enabled) async {
    // No-op on Windows as WebView2 respects Flutter's overlay stacking.
  }

  @override
  Future<NativeFocusResult> requestNativeFocus() async {
    if (!_isInitialized || _disposed) return NativeFocusResult.failed;
    final alreadyOwned = _controller.hasNativeFocus;
    // Always run the handoff, even when the focus flag reads true: WebView2's
    // MoveFocus is what re-arms keyboard routing after a native boundary.
    // Moves real Win32 keyboard focus to the WebView2 control so that
    // subsequent in-page focus calls (and typing) actually work.
    await _controller.focus();
    return alreadyOwned
        ? NativeFocusResult.alreadyOwned
        : NativeFocusResult.granted;
  }

  @override
  Future<bool?> hasNativeInputFocus() async {
    if (!_isInitialized || _disposed) return null;
    return _controller.hasNativeFocus;
  }

  @override
  Future<void> releaseNativeFocus() async {
    if (!_isInitialized || _disposed) return;
    if (_controller.hasNativeFocus) {
      await ww.WebviewController.releaseFocus();
    }
  }

  @override
  Future<void> enableJavaScript() async {}

  @override
  Future<Object?> runJavaScript(String script) async {
    try {
      return await _controller.executeScript(script);
    } catch (e) {
      debugPrint('[WindowsWebViewController] JS execution error: $e');
      rethrow;
    }
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    try {
      final result = await _controller.executeScript(script);
      return parseWindowsScriptResult(result);
    } catch (e) {
      debugPrint('[WindowsWebViewController] JS result error: $e');
      rethrow;
    }
  }

  @override
  Future<Object?> addJavaScriptChannel(
    String name,
    void Function(String) onMessage,
  ) async {
    debugPrint(
      '[WindowsWebViewController] Registering handler for channel: $name',
    );

    // Store the handler - HTML already defines window.flutterChannel
    _channels[name] = onMessage;

    // No need to inject JavaScript - the HTML already has the channel defined
    return null;
  }

  @override
  Future<Object?> removeJavaScriptChannel(String name) async {
    _channels.remove(name);
    return null; // No-op in JS; HTML owns flutterChannel
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    debugPrint('[WindowsWebViewController] Disposing...');
    _webMessageSubscription?.cancel();
    _channels.clear();
    if (_isInitialized) {
      _controller.dispose();
    }
  }
}
