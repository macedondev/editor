import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_monaco/src/assets/html_builder.dart';
import 'package:flutter_monaco/src/assets/monaco_assets.dart';
import 'package:flutter_monaco/src/common/monaco_page_config.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';
import 'package:flutter_monaco/src/platform/web_asset_resolver.dart';
import 'package:web/web.dart' as web;
import 'dart:ui_web' as ui_web;

/// Resolves the bundled Monaco `vs/` directory URL on Flutter Web.
///
/// Monaco's files are ordinary Flutter assets, so the URL comes from Flutter's
/// own resolver (`ui_web.assetManager`) - the single source of truth that
/// already honors `<base href>`, a CDN `assetBase`, a custom `assetsDir`, and
/// URL-encoding. The resolver may return a `<base href>`-relative URL, so it is
/// absolutized against `web.document.baseURI`.
String _monacoVsAssetUrl() {
  final assetUrl = ui_web.assetManager.getAssetUrl(
    '$monacoAssetBaseDir/min/vs',
  );
  return resolveWebAssetUrl(web.document.baseURI, assetUrl);
}

/// Resolves the bundled bridge JavaScript directory URL on Flutter Web.
String _monacoBridgeAssetUrl() {
  final assetUrl = ui_web.assetManager.getAssetUrl(
    '$monacoAssetBaseDir/bridge',
  );
  return resolveWebAssetUrl(web.document.baseURI, assetUrl);
}

/// WebView implementation for Flutter Web using `flutter_inappwebview`.
///
/// Previously used a raw `HTMLIFrameElement` + `platformViewRegistry`.
/// Now uses `InAppWebView` (flutter_inappwebview) which on web still renders
/// an iframe but provides a unified controller API (`evaluateJavascript`,
/// `loadData`, `addJavaScriptHandler`) consistent with the native
/// `flutter_inappwebview` implementations.
///
/// Communication still uses `window.parent.postMessage` from the iframe
/// (defined in the generated HTML) and is captured via `window.addEventListener('message')`
/// on the parent, with per-instance token validation (`_messageToken`) to
/// avoid cross-editor spoofing. `flutter_inappwebview` JavaScript handlers
/// are also registered for forward compatibility.
///
/// HTML is loaded via `InAppWebViewController.loadData` (no blob URL needed);
/// the controller waits for the widget to be mounted/painted before considering
/// boot ready, preserving the `MonacoController.create` web mount constraint.
class WebViewController implements PlatformWebViewController {
  static int _instanceCounter = 0;

  final Map<String, void Function(String)> _channels = {};
  bool _disposed = false;
  bool _interactionEnabled = true;

  Completer<void> _readyCompleter = Completer<void>();
  bool _isReady = false;

  InAppWebViewController? _inAppController;
  final Completer<InAppWebViewController> _controllerCompleter =
      Completer<InAppWebViewController>();
  JSFunction? _messageHandler;
  String? _viewId;
  late final String _messageToken;

  final GlobalKey _widgetKey = GlobalKey();
  Widget? _cachedWidget;
  final ValueNotifier<bool> _interactionNotifier = ValueNotifier<bool>(true);

  @override
  Widget get widget {
    if (_cachedWidget != null) return _cachedWidget!;
    // Lazily built; `initialize()` must have set _viewId/_messageToken.
    if (_viewId == null) {
      throw StateError(
        'WebViewController.widget accessed before initialize(). '
        'Call initialize() first.',
      );
    }

    final inAppWebView = InAppWebView(
      key: _widgetKey,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: true,
        isInspectable: kDebugMode,
        allowFileAccess: true,
        allowContentAccess: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        // iframe attrs
        iframeAllow: 'clipboard-read; clipboard-write',
        // keep original iframe styling on web via CSS in HTML; InAppWebView's
        // web implementation still respects host page touch-action.
      ),
      initialData: InAppWebViewInitialData(
        data: '<!DOCTYPE html><html><head></head><body></body></html>',
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri(web.document.baseURI),
      ),
      onWebViewCreated: (controller) {
        _inAppController = controller;
        if (!_controllerCompleter.isCompleted) {
          _controllerCompleter.complete(controller);
        }
        // Register any channels that were added before controller was ready.
        for (final entry in _channels.entries) {
          _registerHandler(entry.key, entry.value);
        }
        debugPrint('[WebViewController] InAppWebView created: $_viewId');
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint(
          '[Monaco Console] ${consoleMessage.messageLevel.name}: ${consoleMessage.message}',
        );
      },
      onLoadStop: (controller, url) {
        debugPrint('[WebViewController] InAppWebView load stop: $url');
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
          '[WebViewController] InAppWebView error: ${error.description} on ${request.url}',
        );
      },
    );

    // Interaction is driven via IgnorePointer wrapper + notifier so toggling
    // doesn't require rebuilding the InAppWebView (which would reload).
    _cachedWidget = ValueListenableBuilder<bool>(
      valueListenable: _interactionNotifier,
      builder: (context, enabled, child) {
        if (enabled) return child!;
        // pointer-events: none equivalent - absorb all pointer events.
        return IgnorePointer(child: child);
      },
      child: inAppWebView,
    );
    return _cachedWidget!;
  }

  void _registerHandler(String name, void Function(String) onMessage) {
    final controller = _inAppController;
    if (controller == null) return;
    // flutter_inappwebview handler: window.flutter_inappwebview.callHandler(name, msg)
    // The generated HTML still uses window.flutterChannel.postMessage -> window.parent.postMessage,
    // but we also support the handler path for forward compat (injected shim below).
    try {
      controller.removeJavaScriptHandler(handlerName: name);
    } catch (_) {}
    controller.addJavaScriptHandler(
      handlerName: name,
      callback: (args) {
        final msg = args.isNotEmpty ? args.first.toString() : '';
        // Token is already stamped on handler path via envelope._flutterToken;
        // validate similarly to postMessage path.
        if (msg.startsWith('{')) {
          try {
            final decoded = jsonDecode(msg);
            if (decoded is Map<String, dynamic>) {
              final token = decoded['_flutterToken'];
              if (token != null && token != _messageToken) return;
            }
          } catch (_) {}
        } else if (msg != 'ready') {
          return;
        }
        _dispatchToChannels(msg);
        // Also run the legacy focus/ready logic for handler path.
        _handleChannelMessage(msg);
      },
    );
  }

  void _dispatchToChannels(String message) {
    for (final handler in _channels.values) {
      handler(message);
    }
  }

  void _handleChannelMessage(String message) {
    // Shared logic for both postMessage and handler paths - similar to legacy
    // _handleIframeMessage but without source check (InAppWebView iframe source
    // is opaque). Token already validated.
    if (_disposed) return;

    Map<String, dynamic>? json;
    if (message.startsWith('{')) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
    }

    // Only log non-stats
    final isStatsMessage = json?['kind'] == 'event' && json?['name'] == 'stats';
    if (!isStatsMessage) {
      debugPrint('[WebViewController] Received message: $message');
    }

    final lifecycleName = (json != null && json['kind'] == 'lifecycle')
        ? json['name']
        : null;
    if (message == 'ready' || lifecycleName == 'pageReady') {
      _isReady = true;
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      debugPrint('[WebViewController] Monaco page shell ready!');
    } else if (!_isReady &&
        (lifecycleName == 'fatal' || json?['event'] == 'error')) {
      final errorMessage =
          ((json?['error'] as Map<String, dynamic>?)?['message'] ??
                  json?['message'] ??
                  'Unknown Monaco load error')
              .toString();
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.completeError(StateError(errorMessage));
      }
    }

    // Focus handling
    final focusData =
        (json != null &&
            json['kind'] == 'event' &&
            json['name'] == 'focusChanged')
        ? json['data']
        : null;
    if (_interactionEnabled &&
        focusData is Map &&
        focusData['focused'] == true) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (!_isMobileInputPlatform()) {
        // Best-effort force focus via JS
        _inAppController?.evaluateJavascript(
          source: 'window.flutterMonaco && window.flutterMonaco.forceFocus()',
        );
      }
    }
  }

  @override
  Future<void> initialize() async {
    final instanceId = ++_instanceCounter;
    _viewId =
        'monaco-iframe-$instanceId-${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[WebViewController] Initializing InAppWebView approach');
    _messageToken = 'monaco-${DateTime.now().microsecondsSinceEpoch}-$_viewId';

    // Listen for postMessage from the iframe (legacy path). On web, the iframe
    // created by InAppWebView still posts to window.parent, which arrives here.
    final handler = _handleWindowMessage.toJS;
    _messageHandler = handler;
    web.window.addEventListener('message', handler);

    _interactionNotifier.value = _interactionEnabled;
    debugPrint('[WebViewController] Initialized with ID: $_viewId');
  }

  void _handleWindowMessage(web.MessageEvent event) {
    // For InAppWebView web, event.source is the iframe's contentWindow; we don't
    // have a direct reference to validate, so rely on token only.
    final data = event.data;
    String message;
    Map<String, dynamic>? json;

    try {
      message = (data as JSString).toDart;
    } catch (_) {
      try {
        message = jsonEncode((data as JSObject).dartify());
      } catch (_) {
        message = data.toString();
      }
    }

    if (message.startsWith('{')) {
      try {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
    }

    if (json != null) {
      final token = json['_flutterToken'];
      if (token != _messageToken) return;
    } else if (message != 'ready') {
      return;
    }

    // De-duplicate: if this message was already handled via handler path,
    // it will have been dispatched; but postMessage path is primary on web,
    // so dispatch once here.
    _handleChannelMessage(message);
    _dispatchToChannels(message);
  }

  Future<void> _ensureReady() async {
    if (!_isReady) {
      await _readyCompleter.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException('Monaco editor failed to initialize');
        },
      );
    }
  }

  bool _isMobileInputPlatform() {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final css = 'rgba($r, $g, $b, ${color.a})';
    // Apply to host via InAppWebView CSS, and also to iframe content if loaded.
    try {
      await _inAppController?.evaluateJavascript(
        source:
            "document.documentElement.style.backgroundColor='$css';document.body.style.backgroundColor='$css';",
      );
    } catch (_) {}
  }

  void _applyInteractionEnabled() {
    _interactionNotifier.value = _interactionEnabled;
  }

  @override
  Future<void> setInteractionEnabled(bool enabled) async {
    if (_disposed) return;
    _interactionEnabled = enabled;
    _applyInteractionEnabled();

    if (!enabled) {
      await releaseNativeFocus();
    }
  }

  @override
  Future<NativeFocusResult> requestNativeFocus() async {
    return NativeFocusResult.unsupported;
  }

  @override
  Future<bool?> hasNativeInputFocus() async => null;

  @override
  Future<void> releaseNativeFocus() async {
    // Web "native focus" is document focus. With InAppWebView, the iframe is
    // inside Flutter's host; blur inside iframe + focus Flutter host.
    _blurInsideIframe();
    // Best-effort focus host element.
    try {
      final host =
          web.document.querySelector('flutter-view') as web.HTMLElement?;
      if (host != null) {
        if (!host.hasAttribute('tabindex')) host.tabIndex = -1;
        host.focus(web.FocusOptions(preventScroll: true));
      }
    } catch (_) {}
  }

  void _blurInsideIframe() {
    try {
      _inAppController?.evaluateJavascript(
        source: '''
          (function() {
            try {
              var ta = document.querySelector('textarea.inputarea');
              if (ta && ta.blur) ta.blur();
              var ae = document.activeElement;
              if (ae && ae.blur) ae.blur();
            } catch (e) {}
          })();
        ''',
      );
    } catch (_) {}
  }

  @override
  Future<void> enableJavaScript() async {
    // InAppWebView has JS enabled via settings.
  }

  @override
  Future<Object?> runJavaScript(String script) async {
    if (_disposed) return null;
    try {
      final controller = await _controllerCompleter.future;
      await controller.evaluateJavascript(source: script);
      return null;
    } catch (e) {
      debugPrint('[WebViewController] JS execution error: $e');
      rethrow;
    }
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    if (_disposed) return null;
    try {
      final controller = await _controllerCompleter.future;
      final result = await controller.evaluateJavascript(source: script);
      return result;
    } catch (e) {
      debugPrint('[WebViewController] JS result error: $e');
      rethrow;
    }
  }

  @override
  Future<Object?> addJavaScriptChannel(
    String name,
    void Function(String) onMessage,
  ) async {
    debugPrint('[WebViewController] Adding JS channel: $name');
    _channels[name] = onMessage;
    // If controller already created, register handler now for handler-path.
    if (_inAppController != null) {
      _registerHandler(name, onMessage);
    }
    return null;
  }

  @override
  Future<Object?> removeJavaScriptChannel(String name) async {
    _channels.remove(name);
    try {
      _inAppController?.removeJavaScriptHandler(handlerName: name);
    } catch (_) {}
    return null;
  }

  @override
  Future<void> load({MonacoPageConfig page = const MonacoPageConfig()}) async {
    debugPrint('[WebViewController] Loading Monaco via InAppWebView');
    // Wait for the InAppWebView widget to be mounted and controller available.
    // The widget must be in the tree (see MonacoController docs); we poll
    // briefly similarly to _waitForIframeAttachment.
    await _waitForControllerAttachment();

    final vsPath = _monacoVsAssetUrl();
    final bridgeBase = _monacoBridgeAssetUrl();

    Object? lastError;
    const maxLoadAttempts = 2;
    for (var attempt = 1; attempt <= maxLoadAttempts; attempt++) {
      _isReady = false;
      _readyCompleter = Completer<void>();

      final html = buildMonacoIndexHtml(
        vsPath: vsPath,
        bridgeBase: bridgeBase,
        monacoVersion: MonacoAssets.monacoVersion,
        isWeb: true,
        messageToken: _messageToken,
        customCss: page.customCss,
        allowCdnFonts: page.allowCdnFonts,
        allowedConnectSources: page.allowedConnectSources,
      );

      // Inject shim so window.flutterChannel also works via handler path
      // (covers case where handler is preferred). Injected before first script.
      final shim = '''
<script>
  (function(){
    var _origPost = null;
    if (window.flutterChannel && window.flutterChannel.postMessage) _origPost = window.flutterChannel.postMessage;
    window.flutterChannel = {
      postMessage: function(msg) {
        try {
          if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            var s = typeof msg === 'string' ? msg : JSON.stringify(msg);
            window.flutter_inappwebview.callHandler('flutterChannel', s);
            return;
          }
        } catch(e) {}
        if (_origPost) { try { _origPost.call(window.flutterChannel, msg); return; } catch(e){} }
        try { window.parent.postMessage(msg, '*'); } catch(e) {}
      }
    };
  })();
</script>
''';
      final patchedHtml = html.replaceFirst('<script>', '$shim\n<script>');

      try {
        final controller = await _controllerCompleter.future;
        await controller.loadData(
          data: patchedHtml,
          mimeType: 'text/html',
          encoding: 'utf8',
          baseUrl: WebUri(web.document.baseURI),
          historyUrl: WebUri(web.document.baseURI),
        );
        await _ensureReady();
        return;
      } catch (e) {
        // If widget not attached, this is a usage error - fail fast like iframe version.
        final isDetached =
            _cachedWidget == null ||
            _widgetKey.currentContext == null ||
            !(_widgetKey.currentContext!.findRenderObject()?.attached ?? false);
        if (e is TimeoutException && isDetached) {
          throw StateError(
            'Monaco InAppWebView is not attached to the DOM, so the editor page '
            'can never load. On web, whenReady only completes while the '
            "controller's webViewWidget is mounted and painted: keep the "
            'widget in the tree underneath your loading UI (an opaque Stack '
            'overlay, as the MonacoEditor widget does) instead of inserting '
            'it after readiness, and do not hide it with Offstage or '
            'Visibility(visible: false).',
          );
        }
        lastError = e;
        if (attempt == maxLoadAttempts) rethrow;
        debugPrint(
          '[WebViewController] Monaco load attempt $attempt failed, retrying: $e',
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    throw StateError('Monaco InAppWebView failed to load: $lastError');
  }

  Future<void> _waitForControllerAttachment() async {
    // Wait for onWebViewCreated
    if (_controllerCompleter.isCompleted) {
      // Also wait a few frames for the widget to be attached/painted.
      const maxFrames = 120;
      for (var i = 0; i < maxFrames; i++) {
        final ctx = _widgetKey.currentContext;
        final attached = ctx?.findRenderObject()?.attached ?? false;
        if (attached) return;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      return;
    }
    // Controller not yet created - widget not yet built. Wait briefly for first frame.
    const maxFrames = 120;
    for (var i = 0; i < maxFrames; i++) {
      if (_controllerCompleter.isCompleted) {
        // Now wait for attachment as above
        for (var j = 0; j < 20; j++) {
          final ctx = _widgetKey.currentContext;
          final attached = ctx?.findRenderObject()?.attached ?? false;
          if (attached) return;
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    debugPrint('[WebViewController] Disposing InAppWebView...');
    if (_messageHandler != null) {
      web.window.removeEventListener('message', _messageHandler!);
      _messageHandler = null;
    }
    for (final name in _channels.keys.toList()) {
      try {
        _inAppController?.removeJavaScriptHandler(handlerName: name);
      } catch (_) {}
    }
    _channels.clear();
    _cachedWidget = null;
    _detachParentBindings();
    // InAppWebView controller will be disposed by framework.
  }

  void _detachParentBindings() {
    try {
      final c = _inAppController;
      if (c != null) {
        c.evaluateJavascript(
          source:
              'window.__flutterMonacoDetachParentBindings && window.__flutterMonacoDetachParentBindings();',
        );
      }
    } catch (_) {}
  }
}
