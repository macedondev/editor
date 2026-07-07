import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';

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

/// Owns the multi-layer focus handoff between Flutter, the native platform
/// view, and Monaco's DOM (D20).
///
/// The decision logic is ported verbatim from the 2.3.0
/// `MonacoController.focus`/`ensureEditorFocus`; only the plumbing changed
/// (the controller delegates here).
final class MonacoFocusCoordinator {
  /// Creates a coordinator bound to one controller's plumbing.
  MonacoFocusCoordinator({
    required this._webView,
    required this._ensureReady,
    required this._invoke,
    required this._isInteractionEnabled,
  });

  final PlatformWebViewController _webView;
  final Future<void> Function() _ensureReady;
  final Future<Object?> Function(String method, Map<String, Object?> params)
  _invoke;
  final bool Function() _isInteractionEnabled;

  /// Whether a Flutter text input (TextField, CupertinoTextField,
  /// SelectableText, ...) currently owns Flutter's primary focus.
  ///
  /// Focus nudges must never steal the keyboard from one: on Windows,
  /// [PlatformWebViewController.requestNativeFocus] moves real Win32
  /// keyboard focus to the WebView, which would make typing land in the
  /// editor instead of, say, a dialog's TextField.
  static bool flutterTextInputHasFocus() {
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
    if (flutterTextInputHasFocus()) {
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
      await _invoke('focus.force', {'replayInputFocus': replayInputFocus});
    } catch (_) {}
  }

  /// Requests editor focus, retrying to ride out layout transitions.
  ///
  /// Behavior ported verbatim from the 2.3.0 `ensureEditorFocus`. By
  /// default this is cooperative background maintenance: attempts made
  /// while a Flutter text input owns the primary focus are skipped, so
  /// refocus nudges after content updates, route pops, or app resume
  /// cannot steal the keyboard from a focused TextField.
  ///
  /// Pass [MonacoFocusIntent.user] only from direct user interaction with
  /// the editor, such as a primary pointer down inside the Monaco view. On
  /// desktop that intent first releases Flutter's text-input channel so a
  /// stale TextField/dialog client cannot keep swallowing native input,
  /// then hands native keyboard focus to the WebView (Win32 focus on
  /// Windows, NSWindow first responder on macOS). When the macOS handoff
  /// is unavailable (no native plugin registered) or fails, the first
  /// in-page focus attempt replays the full focus path as a fallback,
  /// because WKWebView native input readiness can become stale while
  /// Monaco still reports DOM focus.
  ///
  /// On Android and iOS the OS soft keyboard may only appear after a user
  /// tap inside the editor, and only one attempt is made (multiple async
  /// focus calls interrupt the IME lifecycle).
  Future<void> requestFocus({
    MonacoFocusIntent intent = MonacoFocusIntent.maintenance,
    int attempts = 3,
    Duration interval = const Duration(milliseconds: 24),
  }) async {
    if (!_isInteractionEnabled()) return;
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
          !flutterTextInputHasFocus()) {
        if (!nativeFocusRequested) {
          // Hand native keyboard focus to the WebView first; the JS focus
          // below cannot take effect without it (Win32 focus on Windows,
          // first responder on macOS).
          final nativeFocus = await _webView.requestNativeFocus();
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
  /// This is the real desktop input-readiness signal: `onFocusChanged`
  /// only reports Monaco's DOM focus, which can stay `true` while the
  /// native layer stopped routing keys to the WebView (for example after
  /// an app switch, dialog, or tab change). Apps that model input
  /// readiness can use this to verify staleness instead of assuming it.
  Future<bool?> hasNativeInputFocus() {
    return _webView.hasNativeInputFocus();
  }

  /// Hands native keyboard focus back to the Flutter view if the editor's
  /// WebView currently holds it.
  ///
  /// Use this for an explicit programmatic handoff out of the editor (for
  /// example before moving focus to a Flutter text field without a user
  /// click). macOS makes the Flutter view first responder; Windows asks
  /// WebView2 to release focus. No-op on other platforms or when the
  /// editor does not own native focus.
  Future<void> releaseNativeFocus() {
    return _webView.releaseNativeFocus();
  }
}
