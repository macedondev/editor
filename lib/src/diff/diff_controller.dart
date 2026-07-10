import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';
import 'package:flutter_monaco/src/protocol/envelope.dart';
import 'package:flutter_monaco/src/protocol/protocol.dart';

/// Drives a Monaco diff editor (original vs modified) in a WebView.
///
/// The page boots in diff mode (`page.boot` with `mode: 'diff'`): two
/// models inside `monaco.editor.createDiffEditor`, driven by the `diff.*`
/// command registry. The single-editor surface ([MonacoController]) does
/// not exist on a diff page - only the operations below.
///
/// ### Usage
///
/// ```dart
/// final diff = await MonacoDiffController.create(
///   original: oldSource,
///   modified: newSource,
///   language: MonacoLanguage.dart,
/// );
/// await diff.whenReady;
/// ```
///
/// Prefer the `MonacoDiffEditor` widget, which renders loading/error chrome
/// and manages this controller's lifecycle.
class MonacoDiffController {
  MonacoDiffController._(this._protocol, this._webViewController);

  final MonacoProtocol _protocol;
  final PlatformWebViewController _webViewController;
  final Completer<void> _onReady = Completer<void>();
  bool _readyCompletedOk = false;
  bool _disposed = false;

  /// Completes when the diff editor is fully initialized and ready to
  /// accept commands. Completes with the boot error if initialization
  /// fails.
  Future<void> get whenReady => _onReady.future;

  /// Returns `true` if the diff editor finished initializing successfully.
  bool get isReady => _onReady.isCompleted && _readyCompletedOk;

  /// The platform-specific WebView widget hosting the diff editor.
  Widget get webViewWidget => _webViewController.widget;

  /// Creates a diff controller and starts the (non-blocking) boot.
  ///
  /// Returns before the editor is ready (asset preparation and WebView
  /// setup are still awaited here); await [whenReady] for
  /// readiness. [options] configures the inner editors (fonts, minimap,
  /// ...), [diff] the diff-specific behavior (side-by-side vs inline,
  /// ...). [original]/[modified]/[language] seed the two models so the
  /// first painted frame already shows the requested diff.
  ///
  /// [readyTimeout] bounds the whole boot; it defaults to
  /// [MonacoDefaults.readyTimeout] (20s on native, 90s on web where the
  /// cold-cache first load must download the editor bundle over the
  /// network).
  static Future<MonacoDiffController> create({
    EditorOptions? options,
    MonacoDiffOptions diff = const MonacoDiffOptions(),
    String original = '',
    String modified = '',
    MonacoLanguage language = MonacoLanguage.plaintext,
    MonacoPageConfig page = const MonacoPageConfig(),
    Duration readyTimeout = MonacoDefaults.readyTimeout,
  }) async {
    await MonacoAssets.ensureReady();

    final webViewController = PlatformWebViewFactory.createController();
    final protocol = MonacoProtocol(webView: webViewController);
    MonacoDiffController? controller;

    try {
      await webViewController.initialize();
      await webViewController.enableJavaScript();
      await webViewController.addJavaScriptChannel(
        'flutterChannel',
        protocol.handleChannelMessage,
      );

      controller = MonacoDiffController._(protocol, webViewController);
      controller._startBoot(
        options: options,
        diff: diff,
        original: original,
        modified: modified,
        language: language,
        page: page,
        readyTimeout: readyTimeout,
      );
      return controller;
    } catch (_) {
      if (controller != null) {
        controller.dispose();
      } else {
        protocol.dispose();
        webViewController.dispose();
      }
      rethrow;
    }
  }

  /// Runs the two-phase boot in diff mode. Failures land in [whenReady].
  void _startBoot({
    required EditorOptions? options,
    required MonacoDiffOptions diff,
    required String original,
    required String modified,
    required MonacoLanguage language,
    required MonacoPageConfig page,
    required Duration readyTimeout,
  }) {
    final bootOptions = MonacoDefaults.editorOptions.merge(options);
    final bootTheme = bootOptions.theme ?? MonacoDefaults.darkTheme;
    _onReady.future.ignore();
    unawaited(() async {
      try {
        await () async {
          await _webViewController.load(page: page);
          await _protocol.pageReady;
          await _protocol.invoke('page.boot', {
            'mode': 'diff',
            'options': bootOptions.toMonacoOptions(),
            'diffOptions': diff.toMonacoOptions(),
            'original': original,
            'modified': modified,
            'language': language.id,
            'theme': bootTheme.id,
          }, timeout: null);
          await _protocol.editorReady;
        }().timeout(
          readyTimeout,
          onTimeout: () => throw MonacoTimeoutError(
            message:
                'Monaco diff editor did not report ready in '
                '${readyTimeout.inSeconds} seconds.'
                '${kIsWeb ? ' On web the first load downloads the editor '
                          'bundle; a slow connection can exceed this deadline. '
                          'Retrying resumes from the browser cache.' : ''}',
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

  /// Create a diff controller for tests without touching assets or
  /// platform views.
  @visibleForTesting
  static Future<MonacoDiffController> createForTesting({
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

    final controller = MonacoDiffController._(protocol, webViewController);
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
        'capabilities': <String>[],
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

  /// Manually fail the ready signal for tests (mirrors a boot failure).
  @visibleForTesting
  void failReadyForTesting(Object error, [StackTrace? stackTrace]) {
    _onReady.future.ignore();
    if (!_onReady.isCompleted) {
      _onReady.completeError(error, stackTrace ?? StackTrace.current);
    }
  }

  /// Awaits the readiness future unconditionally: a completer that failed is
  /// still `isCompleted`, so an isCompleted fast path would let commands skip
  /// the boot error and enter the protocol of a dead page. Every command
  /// after a failed boot must keep rethrowing the ORIGINAL boot error.
  Future<void> _ensureReady() {
    if (_disposed) {
      return Future.error(
        const MonacoDisposedError(
          message: 'MonacoDiffController has been disposed.',
        ),
      );
    }
    return _onReady.future;
  }

  Future<Object?> _invoke(String method, Map<String, Object?> params) async {
    await _ensureReady();
    final result = await _protocol.invoke(method, params);
    return identical(result, monacoJsUndefined) ? null : result;
  }

  /// Replaces both sides of the diff (and optionally the shared language).
  Future<void> setTexts({
    required String original,
    required String modified,
    MonacoLanguage? language,
  }) async {
    await _invoke('diff.setTexts', {
      'original': original,
      'modified': modified,
      if (language != null) 'language': language.id,
    });
  }

  /// Returns the current text of the modified (right/editable) side.
  Future<String> getModifiedText() async {
    final state = await _invoke('diff.getState', {});
    if (state is Map && state['modifiedText'] is String) {
      return state['modifiedText'] as String;
    }
    throw const MonacoProtocolError(
      message: 'diff.getState returned no modifiedText',
      operation: 'diff.getState',
    );
  }

  /// The number of changed line blocks Monaco currently reports.
  ///
  /// `0` always means a genuinely computed "no changes" result. When Monaco
  /// has not finished computing the diff within the bridge's grace window
  /// (throttled or offscreen views), this throws a [MonacoTimeoutError]
  /// instead of silently reporting zero; retry once the view is visible.
  Future<int> getLineChangeCount() async {
    final state = await _invoke('diff.getState', {});
    if (state is! Map) {
      throw MonacoProtocolError(
        message:
            'diff.getState returned no state map, got ${state.runtimeType}',
        operation: 'diff.getState',
      );
    }
    final count = state['lineChangeCount'];
    if (count is num) return count.toInt();
    throw const MonacoTimeoutError(
      message:
          'Monaco has not finished computing the diff; 0 would be '
          'indistinguishable from a real "no changes" result. Retry once '
          'the diff view is visible.',
      timeout: Duration(seconds: 3),
      operation: 'diff.getState',
    );
  }

  /// Applies sparse editor options (fonts, minimap, ...) to the diff pair.
  Future<void> updateOptions(EditorOptions options) async {
    await _invoke('diff.updateOptions', {'options': options.toMonacoOptions()});
  }

  /// Applies sparse diff-specific options (side-by-side vs inline, ...).
  Future<void> updateDiffOptions(MonacoDiffOptions options) async {
    await _invoke('diff.updateOptions', {'options': options.toMonacoOptions()});
  }

  /// Switches the (global) editor theme.
  Future<void> setTheme(MonacoTheme theme) async {
    await _invoke('diff.updateOptions', {
      'options': {'theme': theme.id},
    });
  }

  /// Scrolls to and highlights the next change.
  Future<void> revealNextChange() async {
    await _invoke('diff.revealNextChange', {});
  }

  /// Scrolls to and highlights the previous change.
  Future<void> revealPreviousChange() async {
    await _invoke('diff.revealPreviousChange', {});
  }

  /// Unconsumed scroll intents reported by the diff page (edge scroll
  /// handoff). Emits only while a source is enabled through
  /// [setScrollHandoffSources]; malformed payloads are dropped silently.
  ///
  /// The vertical scroll master is the modified editor (both panes are
  /// height-aligned), and the wheel region covers both panes. See
  /// [MonacoScrollHandoffDetails] for the delta conventions.
  Stream<MonacoScrollHandoffDetails> get onScrollHandoff => _protocol.events
      .where((event) => event.name == 'scrollHandoff')
      .map(
        (event) => MonacoScrollHandoffDetails.tryParse(
          Map<String, dynamic>.from(event.data),
        ),
      )
      .where((details) => details != null)
      .cast<MonacoScrollHandoffDetails>();

  /// Enables or disables edge scroll handoff sources inside the diff page.
  ///
  /// Identical contract to `MonacoController.setScrollHandoffSources`: an
  /// enabled source installs the matching DOM listeners and posts
  /// `scrollHandoff` events (surfaced through [onScrollHandoff]) for scroll
  /// gestures the diff editor cannot consume, arbitrated by [policy] (the
  /// momentum-absorbing [MonacoScrollBoundaryPolicy.newGestureOnly] by
  /// default); disabling removes the listeners again. `MonacoDiffEditor`
  /// calls this automatically from its `scrollHandoff` configuration.
  Future<void> setScrollHandoffSources({
    bool wheel = false,
    bool touch = false,
    MonacoScrollBoundaryPolicy policy =
        MonacoScrollBoundaryPolicy.newGestureOnly,
  }) async {
    await _invoke('page.setScrollHandoff', {
      'wheel': wheel,
      'touch': touch,
      'policy': policy.name,
    });
  }

  /// Releases the WebView and fails all in-flight commands.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _protocol.dispose();
    _webViewController.dispose();
  }
}
