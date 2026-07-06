import 'package:flutter_monaco/src/core/monaco_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Source-level tests for the edge scroll handoff JS module inside the
/// generated Monaco host page. These assert the contract Dart depends on:
/// the toggle entry point, listener registration flags, input guards, and
/// the bridge event shape.
void main() {
  final html = MonacoAssets.generateIndexHtml('min/vs');
  final webHtml = MonacoAssets.generateIndexHtml(
    'http://localhost/assets/monaco/min/vs',
    isWeb: true,
    messageToken: 'token-1',
  );

  group('generated scroll handoff module', () {
    test('defines the flutterMonaco.setScrollHandoff toggle exactly once', () {
      expect('setScrollHandoff'.allMatches(html).length, greaterThan(0));
      expect(
        'window.flutterMonaco.setScrollHandoff'.allMatches(html).length,
        1,
      );
      // Present on every platform variant, including web.
      expect(
        'window.flutterMonaco.setScrollHandoff'.allMatches(webHtml).length,
        1,
      );
    });

    test('wheel listener is capture-phase and non-passive', () {
      expect(html, contains('{ capture: true, passive: false }'));
      expect(html, contains("addEventListener('wheel'"));
      expect(html, contains("removeEventListener('wheel'"));
    });

    test('touch listeners are observation-only (passive)', () {
      final start = html.indexOf('const gestureTouch');
      final end = html.indexOf('window.flutterMonaco.setScrollHandoff');
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final touchRegion = html.substring(start, end);
      expect(touchRegion, contains('passive: true'));
      expect(touchRegion, isNot(contains('preventDefault')));
      expect(touchRegion, isNot(contains('stopPropagation')));
      expect(touchRegion, isNot(contains('.focus(')));
    });

    test('ctrl and meta wheel input is never handed off', () {
      expect(html, contains('event.ctrlKey || event.metaKey'));
    });

    test('normalizes wheel deltaMode for line and page units', () {
      expect(html, contains('event.deltaMode'));
      expect(html, contains('lineHeight'));
    });

    test('respects a disabled Monaco mouse wheel', () {
      expect(html, contains('handleMouseWheel'));
    });

    test('only the main editor scroll region may hand off', () {
      expect(html, contains('editor-scrollable'));
      expect(html, contains('.monaco-scrollable-element'));
      expect(html, contains('.suggest-widget'));
      expect(html, contains('.monaco-hover'));
      expect(html, contains('.context-view'));
      expect(html, contains('.peekview-widget'));
    });

    test('posts the scrollHandoff event through the shared post helper', () {
      expect(html, contains("post('scrollHandoff'"));
      expect(html, contains('atTop'));
      expect(html, contains('atBottom'));
    });

    test('touch forwarding yields to text selection', () {
      final start = html.indexOf('const gestureTouch');
      final end = html.indexOf('window.flutterMonaco.setScrollHandoff');
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final touchRegion = html.substring(start, end);
      expect(touchRegion, contains('onDidChangeCursorSelection'));
      expect(touchRegion, contains('gesture.cancelled = true'));
    });

    test('htmlGenerationVersion accounts for the bridge change', () {
      expect(
        MonacoAssets.htmlGenerationVersion,
        greaterThanOrEqualTo(4),
        reason:
            'generateIndexHtml output changed for scroll handoff; cached '
            'HTML from older package versions must be regenerated',
      );
    });
  });
}
