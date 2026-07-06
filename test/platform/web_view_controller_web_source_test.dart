import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String webControllerSource() =>
      File('lib/src/platform/web_view_controller/web.dart').readAsStringSync();

  test('web focus handler only amplifies Monaco focus on desktop', () {
    final source = webControllerSource();
    final focusBlockStart = source.indexOf(
      '// When Monaco reports focus, unfocus Flutter widgets.',
    );
    final focusBlockEnd = source.indexOf('// Forward to all channels');

    expect(focusBlockStart, isNonNegative);
    expect(focusBlockEnd, greaterThan(focusBlockStart));

    final focusBlock = source.substring(focusBlockStart, focusBlockEnd);
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

    expect(source, contains("eventName == 'error' && !_isReady"));
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
}
