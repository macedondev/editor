import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String webControllerSource() =>
      File('lib/src/platform/webview_web.dart').readAsStringSync();

  test('web focus handler only amplifies Monaco focus on desktop', () {
    final source = webControllerSource();
    final focusBlockStart = source.indexOf(
      '// When Monaco reports focus, unfocus Flutter widgets.',
    );
    final focusBlockEnd = source.indexOf('// Forward to all channels');

    expect(focusBlockStart, isNonNegative);
    expect(focusBlockEnd, greaterThan(focusBlockStart));

    final focusBlock = source.substring(focusBlockStart, focusBlockEnd);
    // Focus now rides the protocol v3 focusChanged event envelope.
    expect(focusBlock, contains("json['kind'] == 'event'"));
    expect(focusBlock, contains("json['name'] == 'focusChanged'"));
    expect(focusBlock, contains("focusData['focused'] == true"));
    expect(
      focusBlock,
      contains('FocusManager.instance.primaryFocus?.unfocus();'),
    );
    expect(focusBlock, contains('if (!_isMobileInputPlatform())'));
    expect(focusBlock, contains('forceFocus()'));
    expect(source, contains('bool _isMobileInputPlatform()'));
    expect(source, contains('TargetPlatform.android'));
    expect(source, contains('TargetPlatform.iOS'));
  });

  test('web load waits for iframe attachment before assigning blob URL', () {
    final source = webControllerSource();

    expect(source, contains('await _waitForIframeAttachment();'));
    expect(source, contains('Future<void> _waitForIframeAttachment() async'));
    expect(source, contains('iframe.isConnected'));
  });

  test('web load retries transient Monaco iframe load failures', () {
    final source = webControllerSource();

    expect(source, contains('const maxLoadAttempts = 2'));
    expect(source, contains('_readyCompleter = Completer<void>();'));
    expect(source, contains("_iframe?.src = 'about:blank';"));
    expect(source, contains(r'Monaco load attempt $attempt failed, retrying'));
  });

  test('web error messages fail the current load attempt', () {
    final source = webControllerSource();

    // Load-readiness rides the protocol v3 'pageReady' lifecycle envelope
    // (editor readiness is MonacoProtocol's concern, not the web view's).
    expect(source, contains("json['kind'] == 'lifecycle'"));
    expect(source, contains("lifecycleName == 'pageReady'"));
    // Failures before pageReady must fail the in-flight load attempt:
    // lifecycle fatals, plus the legacy {event:'error'} shape still posted
    // by the inline loader-failure handler in the HTML head (it runs before
    // core.js exists).
    expect(source, contains('!_isReady'));
    expect(source, contains("lifecycleName == 'fatal'"));
    expect(source, contains("json?['event'] == 'error'"));
    expect(source, contains('_readyCompleter.completeError'));
    expect(source, contains('Unknown Monaco load error'));
  });

  test('web Monaco vs path resolves via the Flutter asset manager, not '
      'Uri.base', () {
    final source = webControllerSource();

    expect(source, contains('String _monacoVsAssetUrl()'));
    expect(source, contains('final vsPath = _monacoVsAssetUrl();'));
    // Delegate to Flutter's own asset resolver (the single source of truth)
    // and absolutize against the document base href, not the SPA route.
    expect(source, contains('ui_web.assetManager.getAssetUrl('));
    expect(source, contains('resolveWebAssetUrl(web.document.baseURI'));
    // The route-bearing Uri.base must never drive asset resolution (#14).
    expect(source, isNot(contains('Uri.base')));
  });

  test('web iframe declares scroll containment at the frame boundary', () {
    final source = webControllerSource();

    expect(source, contains("..style.display = 'block'"));
    expect(source, contains("..style.touchAction = 'none'"));
    expect(source, contains("..style.overscrollBehavior = 'none'"));
  });

  test('dispose detaches parent-side viewport bindings before removing the '
      'iframe', () {
    final source = webControllerSource();

    // iframe.remove() fires no pagehide, so without the eager detach every
    // disposed mobile-web editor leaves its viewport listeners on the host
    // page, rooting the dead document and its Monaco instance.
    expect(source, contains('__flutterMonacoDetachParentBindings'));

    final disposeStart = source.indexOf('void dispose() {');
    expect(disposeStart, isNonNegative);
    final detachCall = source.indexOf('_detachParentBindings();', disposeStart);
    final removeCall = source.indexOf('_iframe?.remove();', disposeStart);
    expect(detachCall, isNonNegative);
    expect(removeCall, greaterThan(detachCall));
  });

  test('disabling interaction returns the keyboard to Flutter, not just '
      'the pointer', () {
    final source = webControllerSource();

    // setInteractionEnabled(false) must run the full two-sided handoff.
    final disableStart = source.indexOf(
      'Future<void> setInteractionEnabled(bool enabled) async {',
    );
    final disableEnd = source.indexOf(
      'Future<NativeFocusResult> requestNativeFocus()',
    );
    expect(disableStart, isNonNegative);
    expect(disableEnd, greaterThan(disableStart));
    final disableBlock = source.substring(disableStart, disableEnd);
    expect(disableBlock, contains('await releaseNativeFocus();'));

    // releaseNativeFocus is the web layer-2 handoff: blur INSIDE the iframe
    // AND move the parent document's focus onto the Flutter view host.
    // Regressing it to a no-op silently kills Escape/Tab on dialogs shown
    // over the editor (they only recover after a first click).
    final releaseStart = source.indexOf(
      'Future<void> releaseNativeFocus() async {',
    );
    expect(releaseStart, isNonNegative);
    expect(source, contains('_blurInsideIframe();'));
    expect(source, contains('if (_iframeHoldsDocumentFocus)'));
    expect(source, contains('_focusFlutterHost();'));

    // Parent-document focus checks compare by element id: JS-interop
    // reference equality is compiler-dependent (dart2js vs dart2wasm).
    expect(source, contains('bool get _iframeHoldsDocumentFocus'));
    expect(
      source,
      contains("active.tagName == 'IFRAME' && active.id == viewId"),
    );

    // The host focus must be multi-view safe (the editor's OWN view),
    // programmatically focusable, and must not scroll the page.
    expect(source, contains("iframe.closest('flutter-view')"));
    expect(source, contains('hostElement.tabIndex = -1;'));
    expect(source, contains('web.FocusOptions(preventScroll: true)'));
  });

  test('web view ids stay unique when editors initialize in the same '
      'millisecond', () {
    final source = webControllerSource();

    // Multiple editors created in one frame land in the same millisecond,
    // so a purely clock-derived id collides: the platform view registry
    // rejects the duplicate factory, every HtmlElementView resolves to the
    // FIRST iframe, and the other editors never become ready. The id must
    // include a per-instance counter, and the message token must build on
    // that unique id so bridge messages cannot cross editors.
    expect(source, contains('static int _instanceCounter'));
    expect(source, contains('++_instanceCounter'));
    expect(
      source,
      isNot(
        contains(
          "_viewId = 'monaco-iframe-\${DateTime.now().millisecondsSinceEpoch}';",
        ),
      ),
    );
    final tokenIndex = source.indexOf('_messageToken = ');
    expect(tokenIndex, isNonNegative);
    final tokenLine = source.substring(
      tokenIndex,
      source.indexOf(';', tokenIndex),
    );
    expect(tokenLine, contains(r'$_viewId'));
  });

  test('a ready timeout on a detached iframe fails fast with the mount '
      'requirement instead of retrying', () {
    final source = webControllerSource();

    // A detached iframe never loads its src, so a ready timeout while the
    // iframe is outside the DOM is not transient: retrying burns another
    // silent 20s and the caller ends up with a bare TimeoutException and no
    // idea the widget was simply never mounted (the deployed
    // context_collector web regression). The load loop must recognize the
    // detached case at timeout and throw the actionable usage error.
    expect(source, contains('e is TimeoutException'));
    expect(source, contains('_iframe?.isConnected ?? false'));
    expect(source, contains('webViewWidget is mounted and painted'));

    // The diagnosis must escape the retry loop (fail fast): it is thrown
    // before the lastError/retry handling in the same catch block.
    final loadStart = source.indexOf('Future<void> load(');
    expect(loadStart, isNonNegative);
    final catchStart = source.indexOf('} catch (e) {', loadStart);
    expect(catchStart, isNonNegative);
    final diagnosis = source.indexOf('not attached to the DOM', catchStart);
    final retryPath = source.indexOf('lastError = e;', catchStart);
    expect(diagnosis, isNonNegative);
    expect(retryPath, greaterThan(diagnosis));
  });

  test('the Monaco blob URL lives exactly as long as the iframe', () {
    final source = webControllerSource();

    // The Flutter web engine can detach and re-insert the iframe's DOM node
    // at any time after creation (platform-view re-composition around tab
    // and route churn). Re-inserting an iframe reloads its `src` from
    // scratch, so the blob URL must stay resolvable for the controller's
    // whole lifetime: a revoked blob reloads as Chromium's
    // ERR_FILE_NOT_FOUND page ("It may have been moved, edited, or
    // deleted.") inside the editor pane.
    expect(source, contains('String? _activeBlobUrl'));
    expect(source, contains('void _replaceActiveBlobUrl(String? next)'));

    // Exactly one revoke site: replacement (which dispose() drives with
    // null). Nothing may revoke at ready, on load success, or on a failed
    // attempt while the iframe still points at the blob.
    expect('web.URL.revokeObjectURL'.allMatches(source), hasLength(1));
    expect(
      source,
      isNot(
        matches(RegExp(r'await _ensureReady\(\);\s*web\.URL\.revokeObjectURL')),
      ),
    );

    // dispose() releases the last blob URL through the same single site.
    final disposeStart = source.indexOf('void dispose()');
    expect(disposeStart, isNonNegative);
    final disposeBlock = source.substring(
      disposeStart,
      source.indexOf('\n  }', disposeStart),
    );
    expect(disposeBlock, contains('_replaceActiveBlobUrl(null)'));
  });
}
