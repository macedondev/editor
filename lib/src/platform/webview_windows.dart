// ignore_for_file: public_member_api_docs

part of 'webview_native.dart';

// dart:convert is available via parent import; ensure jsonEncode visible

/// WebView implementation for Windows using `flutter_inappwebview` (WebView2).
///
/// Previously used `webview_flutter_windows` (`WebviewController`/`Webview`).
/// Now uses `InAppWebView` which on Windows also wraps WebView2 via
/// `flutter_inappwebview_windows`. The Monaco HTML defines a `window.flutterChannel`
/// shim that now forwards to `window.flutter_inappwebview.callHandler`.
class WindowsWebViewController extends WebViewController {
  WindowsWebViewController() : super._();

  InAppWebViewController? _controller;
  final Completer<InAppWebViewController> _controllerCompleter =
      Completer<InAppWebViewController>();
  final Map<String, void Function(String)> _channels = {};
  bool _isInitialized = false;
  bool _disposed = false;
  Widget? _cachedWidget;
  final GlobalKey _widgetKey = GlobalKey();

  InAppWebViewController? get windowsController => _controller;

  @override
  Widget get widget {
    if (_cachedWidget != null) return _cachedWidget!;
    _cachedWidget = InAppWebView(
      key: _widgetKey,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
        isInspectable: kDebugMode,
        allowFileAccess: true,
        allowContentAccess: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        cacheEnabled: true,
        supportZoom: false,
        disableContextMenu: true,
      ),
      initialData: InAppWebViewInitialData(
        data: '<!DOCTYPE html><html><head></head><body></body></html>',
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source:
              "window.flutterChannel = { postMessage: function(msg){ window.flutter_inappwebview.callHandler('flutterChannel', msg); } };",
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      ]),
      onWebViewCreated: (controller) {
        _controller = controller;
        if (!_controllerCompleter.isCompleted) {
          _controllerCompleter.complete(controller);
        }
        for (final entry in _channels.entries) {
          _addHandler(entry.key, entry.value);
        }
        debugPrint('[WindowsWebViewController] InAppWebView created');
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint(
          '[WindowsWebViewController] ${consoleMessage.messageLevel.name}: ${consoleMessage.message}',
        );
      },
      onLoadStop: (controller, url) {
        debugPrint('[WindowsWebViewController] Page finished: $url');
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
          '[WindowsWebViewController] Error: ${error.description} on ${request.url}',
        );
      },
    );
    return _cachedWidget!;
  }

  void _addHandler(String name, void Function(String) onMessage) {
    final c = _controller;
    if (c == null) return;
    try {
      c.removeJavaScriptHandler(handlerName: name);
    } catch (_) {}
    c.addJavaScriptHandler(
      handlerName: name,
      callback: (args) {
        String messageStr;
        final raw = args.isNotEmpty ? args.first : null;
        if (raw is String) {
          messageStr = raw;
        } else if (raw is Map) {
          messageStr = jsonEncode(raw);
        } else {
          messageStr = raw.toString();
        }
        onMessage(messageStr);
      },
    );
  }

  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    debugPrint(
      '[WindowsWebViewController] Loading HTML string (length: ${html.length})',
    );
    final c = await _controllerCompleter.future;
    await c.loadData(
      data: html,
      mimeType: 'text/html',
      encoding: 'utf8',
      baseUrl: baseUrl != null ? WebUri(baseUrl) : null,
    );
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    debugPrint(
      '[WindowsWebViewController] Initializing InAppWebView (WebView2)...',
    );
    _isInitialized = true;
    debugPrint('[WindowsWebViewController] Initialized');
  }

  @override
  Future<void> load({MonacoPageConfig page = const MonacoPageConfig()}) async {
    final htmlFilePath = await _ensureHtmlFile(page);
    final c = await _controllerCompleter.future;
    final fileUri = Uri.file(htmlFilePath);
    await c.loadUrl(urlRequest: URLRequest(url: WebUri.uri(fileUri)));
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    try {
      final c = _controller;
      if (c != null) {
        final r = (color.r * 255).round();
        final g = (color.g * 255).round();
        final b = (color.b * 255).round();
        final css = 'rgba($r, $g, $b, ${color.a})';
        await c.evaluateJavascript(
          source:
              "document.documentElement.style.backgroundColor='$css';document.body.style.backgroundColor='$css';",
        );
      }
    } catch (_) {}
  }

  @override
  Future<void> setInteractionEnabled(bool enabled) async {}

  @override
  Future<NativeFocusResult> requestNativeFocus() async {
    if (!_isInitialized || _disposed) return NativeFocusResult.failed;
    try {
      final c = _controller;
      if (c != null) {
        await c.evaluateJavascript(source: 'window.focus();');
      }
      return NativeFocusResult.granted;
    } catch (_) {
      return NativeFocusResult.failed;
    }
  }

  @override
  Future<bool?> hasNativeInputFocus() async => null;

  @override
  Future<void> releaseNativeFocus() async {
    try {
      final c = _controller;
      if (c != null) {
        await c.evaluateJavascript(
          source: 'document.activeElement&&document.activeElement.blur();',
        );
      }
    } catch (_) {}
  }

  @override
  Future<void> enableJavaScript() async {}

  @override
  Future<Object?> runJavaScript(String script) async {
    try {
      final c = await _controllerCompleter.future;
      await c.evaluateJavascript(source: script);
      return null;
    } catch (e) {
      debugPrint('[WindowsWebViewController] JS execution error: $e');
      rethrow;
    }
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    try {
      final c = await _controllerCompleter.future;
      final result = await c.evaluateJavascript(source: script);
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
    _channels[name] = onMessage;
    _addHandler(name, onMessage);
    return null;
  }

  @override
  Future<Object?> removeJavaScriptChannel(String name) async {
    _channels.remove(name);
    try {
      _controller?.removeJavaScriptHandler(handlerName: name);
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    debugPrint('[WindowsWebViewController] Disposing...');
    for (final name in _channels.keys.toList()) {
      try {
        _controller?.removeJavaScriptHandler(handlerName: name);
      } catch (_) {}
    }
    _channels.clear();
  }
}
