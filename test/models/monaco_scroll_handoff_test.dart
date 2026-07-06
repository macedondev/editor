import 'package:flutter/widgets.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonacoScrollHandoffDetails.tryParse', () {
    test('parses a full wheel payload', () {
      final details = MonacoScrollHandoffDetails.tryParse({
        'event': 'scrollHandoff',
        'source': 'wheel',
        'deltaX': 0,
        'deltaY': 44.5,
        'atTop': false,
        'atBottom': true,
        'atLeft': true,
        'atRight': true,
      });

      expect(details, isNotNull);
      expect(details!.source, MonacoScrollHandoffSource.wheel);
      expect(details.deltaX, 0.0);
      expect(details.deltaY, 44.5);
      expect(details.atTop, isFalse);
      expect(details.atBottom, isTrue);
      expect(details.atLeft, isTrue);
      expect(details.atRight, isTrue);
    });

    test('parses a touch payload', () {
      final details = MonacoScrollHandoffDetails.tryParse({
        'source': 'touch',
        'deltaX': 0,
        'deltaY': -12,
        'atTop': true,
        'atBottom': false,
        'atLeft': true,
        'atRight': true,
      });

      expect(details, isNotNull);
      expect(details!.source, MonacoScrollHandoffSource.touch);
      expect(details.deltaY, -12.0);
    });

    test('drops payloads with a missing or unknown source', () {
      expect(
        MonacoScrollHandoffDetails.tryParse({'deltaX': 0, 'deltaY': 1}),
        isNull,
      );
      expect(
        MonacoScrollHandoffDetails.tryParse({
          'source': 'gamepad',
          'deltaX': 0,
          'deltaY': 1,
        }),
        isNull,
      );
      expect(
        MonacoScrollHandoffDetails.tryParse({
          'source': 7,
          'deltaX': 0,
          'deltaY': 1,
        }),
        isNull,
      );
    });

    test('drops payloads with missing or non-numeric deltas', () {
      expect(
        MonacoScrollHandoffDetails.tryParse({'source': 'wheel', 'deltaY': 4}),
        isNull,
      );
      expect(
        MonacoScrollHandoffDetails.tryParse({'source': 'wheel', 'deltaX': 4}),
        isNull,
      );
      expect(
        MonacoScrollHandoffDetails.tryParse({
          'source': 'wheel',
          'deltaX': 'zero',
          'deltaY': 4,
        }),
        isNull,
      );
    });

    test('drops payloads with non-finite deltas', () {
      expect(
        MonacoScrollHandoffDetails.tryParse({
          'source': 'wheel',
          'deltaX': 0,
          'deltaY': double.nan,
        }),
        isNull,
      );
      expect(
        MonacoScrollHandoffDetails.tryParse({
          'source': 'wheel',
          'deltaX': double.infinity,
          'deltaY': 0,
        }),
        isNull,
      );
    });

    test('edge flags default to false when absent or non-boolean', () {
      final details = MonacoScrollHandoffDetails.tryParse({
        'source': 'wheel',
        'deltaX': 0,
        'deltaY': 4,
        'atBottom': 'yes',
      });

      expect(details, isNotNull);
      expect(details!.atTop, isFalse);
      expect(details.atBottom, isFalse);
      expect(details.atLeft, isFalse);
      expect(details.atRight, isFalse);
    });

    test('supports value equality', () {
      const a = MonacoScrollHandoffDetails(
        source: MonacoScrollHandoffSource.wheel,
        deltaX: 0,
        deltaY: 10,
        atTop: false,
        atBottom: true,
        atLeft: true,
        atRight: true,
      );
      const b = MonacoScrollHandoffDetails(
        source: MonacoScrollHandoffSource.wheel,
        deltaX: 0,
        deltaY: 10,
        atTop: false,
        atBottom: true,
        atLeft: true,
        atRight: true,
      );
      const c = MonacoScrollHandoffDetails(
        source: MonacoScrollHandoffSource.touch,
        deltaX: 0,
        deltaY: 10,
        atTop: false,
        atBottom: true,
        atLeft: true,
        atRight: true,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('wheel'));
    });
  });

  group('MonacoScrollHandoff', () {
    test('disabled config enables nothing', () {
      const config = MonacoScrollHandoff.disabled();
      expect(config.mode, MonacoScrollHandoffMode.disabled);
      expect(config.isEnabled, isFalse);
      expect(config.wheelSourceEnabled, isFalse);
      expect(config.touchSourceEnabled, isFalse);
      expect(config.controller, isNull);
      expect(config.onHandoff, isNull);
    });

    test('edge config defaults to wheel only', () {
      const config = MonacoScrollHandoff.edge();
      expect(config.mode, MonacoScrollHandoffMode.edge);
      expect(config.isEnabled, isTrue);
      expect(config.useNearestScrollable, isTrue);
      expect(config.wheelSourceEnabled, isTrue);
      expect(config.touchSourceEnabled, isFalse);
    });

    test('edge config honors source flags', () {
      const config = MonacoScrollHandoff.edge(
        desktopWheel: false,
        mobileTouch: true,
      );
      expect(config.wheelSourceEnabled, isFalse);
      expect(config.touchSourceEnabled, isTrue);
    });

    test('edge config keeps the provided controller and callback', () {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      bool handler(MonacoScrollHandoffDetails details) => true;

      final config = MonacoScrollHandoff.edge(
        controller: controller,
        useNearestScrollable: false,
        onHandoff: handler,
      );

      expect(config.controller, same(controller));
      expect(config.useNearestScrollable, isFalse);
      expect(config.onHandoff, same(handler));
    });
  });
}
