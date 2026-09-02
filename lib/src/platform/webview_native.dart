// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/assets/html_builder.dart';
import 'package:flutter_monaco/src/assets/monaco_assets.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';
import 'package:path/path.dart' as p;

part 'webview_windows.dart';

/// Base class for native platform WebView implementations using flutter_inappwebview.
///
/// Replaces `webview_flutter` / `webview_flutter_windows` with a single
/// `flutter_inappwebview` backend that works on Android, iOS, macOS, Windows
/// and Linux. The public factory still returns a platform-specific subclass so
/// existing code can `is WindowsWebViewController` checks.
abstract class WebViewController implements PlatformWebViewController {
  factory WebViewController() {
    if (Platform.isWindows) {
      return WindowsWebViewController();
    } else {
      return FlutterWebViewController();
    }
  }

  const WebViewController._();

  @override
  Future<NativeFocusResult> requestNativeFocus() async {
    return NativeFocusResult.unsupported;
  }

  @override
  Future<bool?> hasNativeInputFocus() async => null;

  @override
  Future<void> releaseNativeFocus() async {}

  Future<String> _ensureHtmlFile(MonacoPageConfig page) async {
    final htmlFilePath = await monacoIndexHtmlPath(
      cacheKey: page.stableCacheKey(),
    );

    final htmlFile = File(htmlFilePath);

    String htmlContent;

    if (Platform.isWindows) {
      final targetDir = p.dirname(htmlFilePath);
      final vsPath = p.join(targetDir, 'min', 'vs');
      final absoluteVsPath = Uri.file(vsPath).toString();
      final bridgeBase = Uri.file(p.join(targetDir, 'bridge')).toString();
      htmlContent = buildMonacoIndexHtml(
        vsPath: absoluteVsPath,
        bridgeBase: bridgeBase,
        monacoVersion: MonacoAssets.monacoVersion,
        isWindows: true,
        customCss: page.customCss,
        allowCdnFonts: page.allowCdnFonts,
        allowedConnectSources: page.allowedConnectSources,
      );
    } else {
      htmlContent = buildMonacoIndexHtml(
        vsPath: p.join('min', 'vs'),
        bridgeBase: 'bridge',
        monacoVersion: MonacoAssets.monacoVersion,
        isIosOrMacOS: Platform.isIOS || Platform.isMacOS,
        customCss: page.customCss,
        allowCdnFonts: page.allowCdnFonts,
        allowedConnectSources: page.allowedConnectSources,
      );
    }

    await htmlFile.writeAsString(htmlContent);
    debugPrint('[MonacoAssets] HTML file created at: ${htmlFile.path}');
    return htmlFilePath;
  }
}

/// WebView implementation for Android, iOS and macOS using `flutter_inappwebview`.
class FlutterWebViewController extends WebViewController {
  FlutterWebViewController() : super._();

  InAppWebViewController? _controller;
  final Completer<InAppWebViewController> _controllerCompleter =
      Completer<InAppWebViewController>();
  final Map<String, void Function(String)> _channels = {};
  bool _disposed = false;
  Widget? _cachedWidget;
  final GlobalKey _widgetKey = GlobalKey();
  final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    mediaPlaybackRequiresUserGesture: false,
    transparentBackground: true,
    isInspectable: kDebugMode,
    allowFileAccess: true,
    allowContentAccess: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    cacheEnabled: true,
    supportZoom: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableHorizontalScroll: false,
    disableVerticalScroll: false,
  );

  @visibleForTesting
  static const MethodChannel macosNativeFocusChannel = MethodChannel(
    'flutter_monaco/native_focus',
  );

  final GlobalKey _macosViewAnchorKey = GlobalKey(
    debugLabel: 'MonacoMacosWebViewAnchor',
  );

  Map<String, double>? _macosWebViewRectArgs() {
    final renderObject = _macosViewAnchorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return <String, double>{
      'x': topLeft.dx,
      'y': topLeft.dy,
      'width': renderObject.size.width,
      'height': renderObject.size.height,
    };
  }

  @override
  Widget get widget {
    if (_cachedWidget != null) return _cachedWidget!;
    final webView = InAppWebView(
      key: _widgetKey,
      initialSettings: _settings,
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
        // Register any channels added before controller creation.
        for (final entry in _channels.entries) {
          _addHandler(entry.key, entry.value);
        }
        debugPrint('[FlutterWebViewController] InAppWebView created');
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint(
          '[Monaco Console] ${consoleMessage.messageLevel.name}: ${consoleMessage.message}',
        );
      },
      onLoadStop: (controller, url) {
        debugPrint('[FlutterWebViewController] Page finished: $url');
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
          '[FlutterWebViewController] WebView error: ${error.description} on ${request.url}',
        );
      },
    );

    if (Platform.isMacOS) {
      _cachedWidget = KeyedSubtree(key: _macosViewAnchorKey, child: webView);
    } else {
      _cachedWidget = webView;
    }
    return _cachedWidget!;
  }

  InAppWebViewController? get flutterController => _controller;

  void _addHandler(String name, void Function(String) onMessage) {
    final c = _controller;
    if (c == null) return;
    try {
      c.removeJavaScriptHandler(handlerName: name);
    } catch (_) {}
    c.addJavaScriptHandler(
      handlerName: name,
      callback: (args) {
        final msg = args.isNotEmpty ? args.first.toString() : '';
        onMessage(msg);
      },
    );
  }

  @override
  Future<NativeFocusResult> requestNativeFocus() async {
    if (_disposed) return NativeFocusResult.failed;
    if (!Platform.isMacOS) {
      return NativeFocusResult.unsupported;
    }
    try {
      final status = await macosNativeFocusChannel.invokeMethod<String>(
        'focusWebView',
        _macosWebViewRectArgs(),
      );
      return switch (status) {
        'granted' => NativeFocusResult.granted,
        'already-owned' => NativeFocusResult.alreadyOwned,
        _ => NativeFocusResult.failed,
      };
    } on MissingPluginException {
      return NativeFocusResult.unsupported;
    } catch (e) {
      debugPrint('[FlutterWebViewController] macOS focus handoff failed: $e');
      return NativeFocusResult.failed;
    }
  }

  @override
  Future<bool?> hasNativeInputFocus() async {
    if (_disposed || !Platform.isMacOS) return null;
    try {
      return await macosNativeFocusChannel.invokeMethod<bool>(
        'hasNativeFocus',
        _macosWebViewRectArgs(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> releaseNativeFocus() async {
    if (_disposed || !Platform.isMacOS) return;
    try {
      await macosNativeFocusChannel.invokeMethod<void>('releaseWebViewFocus');
    } catch (_) {}
  }

  @override
  Future<void> initialize() async {
    // Settings are applied via InAppWebView widget; nothing to do here.
    debugPrint('[FlutterWebViewController] initialize (InAppWebView)');
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    // InAppWebView background via settings + JS fallback.
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
  Future<void> setInteractionEnabled(bool enabled) async {
    // No-op on native - overlays work by Flutter compositor.
  }

  Future<Object?> loadFlutterAsset(String asset) async {
    final c = await _controllerCompleter.future;
    await c.loadFile(assetFilePath: asset);
    return null;
  }

  @override
  Future<void> enableJavaScript() async {}

  @override
  Future<Object?> runJavaScript(String script) async {
    try {
      final c = await _controllerCompleter.future;
      await c.evaluateJavascript(source: script);
    } catch (e) {
      debugPrint('[FlutterWebViewController] JS execution error: $e');
      rethrow;
    }
    return null;
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    try {
      final c = await _controllerCompleter.future;
      final result = await c.evaluateJavascript(source: script);
      return result;
    } catch (e) {
      debugPrint('[FlutterWebViewController] JS result error: $e');
      rethrow;
    }
  }

  @override
  Future<Object?> addJavaScriptChannel(
    String name,
    void Function(String) onMessage,
  ) async {
    _channels[name] = onMessage;
    _addHandler(name, onMessage);
    return null;
  }

  @override
  Future<void> load({MonacoPageConfig page = const MonacoPageConfig()}) async {
    final htmlFilePath = await _ensureHtmlFile(page);
    final c = await _controllerCompleter.future;
    // Load file via file:// URL - allowFileAccess required.
    final fileUri = Uri.file(htmlFilePath);
    await c.loadUrl(urlRequest: URLRequest(url: WebUri.uri(fileUri)));
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
    for (final name in _channels.keys.toList()) {
      try {
        _controller?.removeJavaScriptHandler(handlerName: name);
      } catch (_) {}
    }
    _channels.clear();
  }
}
