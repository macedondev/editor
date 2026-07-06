import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

class _Bundle {
  _Bundle(this.controller, this.webview);

  final MonacoController controller;
  final FakePlatformWebViewController webview;
}

Future<_Bundle> _createBundle() async {
  final webview = FakePlatformWebViewController(widget: const SizedBox());
  final controller = await MonacoController.createForTesting(
    webViewController: webview,
  );
  return _Bundle(controller, webview);
}

String _payload({
  Object? source = 'wheel',
  Object? deltaX = 0,
  Object? deltaY = 24,
  bool atTop = false,
  bool atBottom = true,
}) {
  return jsonEncode({
    'event': 'scrollHandoff',
    'source': ?source,
    'deltaX': ?deltaX,
    'deltaY': ?deltaY,
    'atTop': atTop,
    'atBottom': atBottom,
    'atLeft': true,
    'atRight': true,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MonacoController.onScrollHandoff', () {
    test('emits parsed details for a valid wheel payload', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      final events = <MonacoScrollHandoffDetails>[];
      final sub = bundle.controller.onScrollHandoff.listen(events.add);
      addTearDown(sub.cancel);

      bundle.webview.emitToChannel('flutterChannel', _payload(deltaY: 44.5));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.source, MonacoScrollHandoffSource.wheel);
      expect(events.single.deltaY, 44.5);
      expect(events.single.atBottom, isTrue);
    });

    test('emits parsed details for a valid touch payload', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      final events = <MonacoScrollHandoffDetails>[];
      final sub = bundle.controller.onScrollHandoff.listen(events.add);
      addTearDown(sub.cancel);

      bundle.webview.emitToChannel(
        'flutterChannel',
        _payload(source: 'touch', deltaY: -8),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.source, MonacoScrollHandoffSource.touch);
      expect(events.single.deltaY, -8.0);
    });

    test('drops malformed payloads silently', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      final events = <MonacoScrollHandoffDetails>[];
      final sub = bundle.controller.onScrollHandoff.listen(events.add);
      addTearDown(sub.cancel);

      bundle.webview.emitToChannel(
        'flutterChannel',
        _payload(source: 'gamepad'),
      );
      bundle.webview.emitToChannel('flutterChannel', _payload(source: null));
      bundle.webview.emitToChannel('flutterChannel', _payload(deltaY: null));
      bundle.webview.emitToChannel('flutterChannel', _payload(deltaY: 'ten'));
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('streams are independent between controllers', () async {
      final first = await _createBundle();
      final second = await _createBundle();
      addTearDown(first.controller.dispose);
      addTearDown(second.controller.dispose);

      final firstEvents = <MonacoScrollHandoffDetails>[];
      final secondEvents = <MonacoScrollHandoffDetails>[];
      final firstSub = first.controller.onScrollHandoff.listen(firstEvents.add);
      final secondSub = second.controller.onScrollHandoff.listen(
        secondEvents.add,
      );
      addTearDown(firstSub.cancel);
      addTearDown(secondSub.cancel);

      first.webview.emitToChannel('flutterChannel', _payload());
      await Future<void>.delayed(Duration.zero);

      expect(firstEvents, hasLength(1));
      expect(secondEvents, isEmpty);
    });

    test('closes on dispose', () async {
      final bundle = await _createBundle();

      final done = expectLater(bundle.controller.onScrollHandoff, emitsDone);
      bundle.controller.dispose();
      await done;
    });
  });

  group('MonacoController.setScrollHandoffSources', () {
    test('invokes the JS toggle with the requested sources', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      await bundle.controller.setScrollHandoffSources(wheel: true);

      final scripts = bundle.webview.scriptsContaining('"setScrollHandoff"');
      expect(scripts, hasLength(1));
      expect(scripts.single, contains('"wheel":true'));
      expect(scripts.single, contains('"touch":false'));
    });

    test('defaults to disabling both sources', () async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      await bundle.controller.setScrollHandoffSources();

      final scripts = bundle.webview.scriptsContaining('"setScrollHandoff"');
      expect(scripts, hasLength(1));
      expect(scripts.single, contains('"wheel":false'));
      expect(scripts.single, contains('"touch":false'));
    });
  });
}
