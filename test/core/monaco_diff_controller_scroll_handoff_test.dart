import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

class _Bundle {
  _Bundle(this.controller, this.webview);

  final MonacoDiffController controller;
  final FakePlatformWebViewController webview;
}

Future<_Bundle> _createBundle() async {
  final webview = FakePlatformWebViewController(widget: const SizedBox());
  final controller = await MonacoDiffController.createForTesting(
    webViewController: webview,
  );
  return _Bundle(controller, webview);
}

Map<String, Object?> _payload({
  Object? source = 'wheel',
  Object? deltaX = 0,
  Object? deltaY = 24,
  bool atTop = false,
  bool atBottom = true,
}) {
  return {
    'source': ?source,
    'deltaX': ?deltaX,
    'deltaY': ?deltaY,
    'atTop': atTop,
    'atBottom': atBottom,
    'atLeft': true,
    'atRight': true,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MonacoDiffController.onScrollHandoff', () {
    test('emits parsed details for a valid wheel payload', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      final events = <MonacoScrollHandoffDetails>[];
      final sub = bundle.controller.onScrollHandoff.listen(events.add);
      addTearDown(sub.cancel);

      bundle.webview.emitEvent('scrollHandoff', _payload(deltaY: 44.5));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.source, MonacoScrollHandoffSource.wheel);
      expect(events.single.deltaY, 44.5);
      expect(events.single.atBottom, isTrue);
    });

    test('drops malformed payloads silently', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      final events = <MonacoScrollHandoffDetails>[];
      final sub = bundle.controller.onScrollHandoff.listen(events.add);
      addTearDown(sub.cancel);

      bundle.webview.emitEvent('scrollHandoff', _payload(source: 'gamepad'));
      bundle.webview.emitEvent('scrollHandoff', _payload(source: null));
      bundle.webview.emitEvent('scrollHandoff', _payload(deltaY: null));
      bundle.webview.emitEvent('scrollHandoff', _payload(deltaY: 'ten'));
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('ignores unrelated events', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      final events = <MonacoScrollHandoffDetails>[];
      final sub = bundle.controller.onScrollHandoff.listen(events.add);
      addTearDown(sub.cancel);

      bundle.webview.emitEvent('stats', {'lineCount': 3, 'charCount': 9});
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('closes on dispose', () async {
      final bundle = await _createBundle();

      final done = expectLater(bundle.controller.onScrollHandoff, emitsDone);
      bundle.controller.dispose();
      await done;
    });
  });

  group('MonacoDiffController.setScrollHandoffSources', () {
    test('invokes the JS toggle with the requested sources', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      await bundle.controller.setScrollHandoffSources(wheel: true);

      final calls = bundle.webview.dispatched
          .where((d) => d['method'] == 'page.setScrollHandoff')
          .toList();
      expect(calls, hasLength(1));
      final params = calls.single['params']! as Map<String, Object?>;
      expect(params['wheel'], isTrue);
      expect(params['touch'], isFalse);
    });

    test('defaults to disabling both sources', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      await bundle.controller.setScrollHandoffSources();

      final calls = bundle.webview.dispatched
          .where((d) => d['method'] == 'page.setScrollHandoff')
          .toList();
      expect(calls, hasLength(1));
      final params = calls.single['params']! as Map<String, Object?>;
      expect(params['wheel'], isFalse);
      expect(params['touch'], isFalse);
    });

    test('sends the boundary policy, newGestureOnly by default', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      await bundle.controller.setScrollHandoffSources(wheel: true);
      await bundle.controller.setScrollHandoffSources(
        wheel: true,
        policy: MonacoScrollBoundaryPolicy.continuous,
      );

      final calls = bundle.webview.dispatched
          .where((d) => d['method'] == 'page.setScrollHandoff')
          .toList();
      expect(calls, hasLength(2));
      final first = calls.first['params']! as Map<String, Object?>;
      final second = calls.last['params']! as Map<String, Object?>;
      expect(first['policy'], 'newGestureOnly');
      expect(second['policy'], 'continuous');
    });
  });
}
