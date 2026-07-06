import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

class _Bundle {
  _Bundle(this.controller, this.webview);

  final MonacoController controller;
  final FakePlatformWebViewController webview;
}

Future<_Bundle> _createBundle() async {
  final webview = FakePlatformWebViewController(
    widget: const SizedBox(key: Key('webview')),
  );
  final controller = await MonacoController.createForTesting(
    webViewController: webview,
  );
  return _Bundle(controller, webview);
}

void _emitHandoff(
  FakePlatformWebViewController webview, {
  String source = 'wheel',
  double deltaY = 40,
  bool atTop = false,
  bool atBottom = true,
}) {
  webview.emitToChannel(
    'flutterChannel',
    jsonEncode({
      'event': 'scrollHandoff',
      'source': source,
      'deltaX': 0,
      'deltaY': deltaY,
      'atTop': atTop,
      'atBottom': atBottom,
      'atLeft': true,
      'atRight': true,
    }),
  );
}

/// Delivers pending broadcast-stream events, then runs the coalescing
/// frame callback.
Future<void> _settleHandoff(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Widget _editorInScrollView({
  required MonacoController controller,
  required ScrollController scrollController,
  MonacoScrollHandoff scrollHandoff = const MonacoScrollHandoff.disabled(),
  bool reverse = false,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        controller: scrollController,
        reverse: reverse,
        child: Column(
          children: [
            SizedBox(
              height: 300,
              child: MonacoEditor(
                controller: controller,
                scrollHandoff: scrollHandoff,
              ),
            ),
            const SizedBox(height: 3000, width: 100),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MonacoEditor scroll handoff', () {
    testWidgets('wheel handoff scrolls the enclosing scrollable', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);

      expect(scrollController.offset, 50);
    });

    testWidgets('scrolling clamps to the scrollable extents', (tester) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 999999);
      await _settleHandoff(tester);
      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );

      _emitHandoff(bundle.webview, deltaY: -999999, atTop: true);
      await _settleHandoff(tester);
      expect(scrollController.offset, 0);
    });

    testWidgets('disabled config ignores handoff events entirely', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);

      expect(scrollController.offset, 0);
      bundle.webview.assertNotExecuted('"setScrollHandoff"');
    });

    testWidgets('touch deltas are ignored unless mobileTouch is enabled', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, source: 'touch', deltaY: 50);
      await _settleHandoff(tester);
      expect(scrollController.offset, 0);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(
            desktopWheel: false,
            mobileTouch: true,
          ),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, source: 'touch', deltaY: 50);
      await _settleHandoff(tester);
      expect(scrollController.offset, 50);

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);
      expect(scrollController.offset, 50, reason: 'wheel source is off');
    });

    testWidgets('an explicit controller wins over the enclosing scrollable', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final enclosing = ScrollController();
      final explicit = ScrollController();
      addTearDown(enclosing.dispose);
      addTearDown(explicit.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: SingleChildScrollView(
                    controller: explicit,
                    child: const SizedBox(height: 2000, width: 100),
                  ),
                ),
                SizedBox(
                  height: 300,
                  child: SingleChildScrollView(
                    controller: enclosing,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 250,
                          child: MonacoEditor(
                            controller: bundle.controller,
                            scrollHandoff: MonacoScrollHandoff.edge(
                              controller: explicit,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2000, width: 100),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 60);
      await _settleHandoff(tester);

      expect(explicit.offset, 60);
      expect(enclosing.offset, 0);
    });

    testWidgets('onHandoff returning true consumes the delta', (tester) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final seen = <MonacoScrollHandoffDetails>[];

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: MonacoScrollHandoff.edge(
            onHandoff: (details) {
              seen.add(details);
              return true;
            },
          ),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);

      expect(seen, hasLength(1));
      expect(seen.single.deltaY, 50);
      expect(scrollController.offset, 0);
    });

    testWidgets('onHandoff returning false keeps the default scrolling', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: MonacoScrollHandoff.edge(onHandoff: (_) => false),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);

      expect(scrollController.offset, 50);
    });

    testWidgets('drops deltas silently when no target resolves', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: MonacoEditor(
                controller: bundle.controller,
                scrollHandoff: const MonacoScrollHandoff.edge(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('same-frame deltas coalesce into one scroll application', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      var scrollStarts = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollStartNotification>(
              onNotification: (_) {
                scrollStarts++;
                return false;
              },
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  children: [
                    SizedBox(
                      height: 300,
                      child: MonacoEditor(
                        controller: bundle.controller,
                        scrollHandoff: const MonacoScrollHandoff.edge(),
                      ),
                    ),
                    const SizedBox(height: 3000, width: 100),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      _emitHandoff(bundle.webview, deltaY: 20);
      _emitHandoff(bundle.webview, deltaY: 30);
      await _settleHandoff(tester);

      expect(scrollController.offset, 50);
      expect(scrollStarts, 1, reason: 'both deltas must apply in one frame');
    });

    testWidgets('reversed scrollables scroll in the correct direction', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(),
          reverse: true,
        ),
      );
      await tester.pump();

      // Scrolling up (negative wheel delta) moves a reversed scrollable
      // away from its zero offset.
      _emitHandoff(bundle.webview, deltaY: -50, atTop: true, atBottom: false);
      await _settleHandoff(tester);
      expect(scrollController.offset, 50);

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);
      expect(scrollController.offset, 0);
    });

    testWidgets('syncs JS sources on enable and on rebuild to disabled', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(),
        ),
      );
      await tester.pump();

      var scripts = bundle.webview.scriptsContaining('"setScrollHandoff"');
      expect(scripts, hasLength(1));
      expect(scripts.single, contains('"wheel":true'));
      expect(scripts.single, contains('"touch":false'));

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
        ),
      );
      await tester.pump();

      scripts = bundle.webview.scriptsContaining('"setScrollHandoff"');
      expect(scripts, hasLength(2));
      expect(scripts.last, contains('"wheel":false'));

      // Behavioral: after disabling, deltas no longer move the parent.
      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);
      expect(scrollController.offset, 0);
    });

    testWidgets('rebuilding from disabled to enabled installs the source', (
      tester,
    ) async {
      final bundle = await _createBundle();
      addTearDown(bundle.controller.dispose);
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
        ),
      );
      await tester.pump();
      bundle.webview.assertNotExecuted('"setScrollHandoff"');

      await tester.pumpWidget(
        _editorInScrollView(
          controller: bundle.controller,
          scrollController: scrollController,
          scrollHandoff: const MonacoScrollHandoff.edge(),
        ),
      );
      await tester.pump();

      final scripts = bundle.webview.scriptsContaining('"setScrollHandoff"');
      expect(scripts, hasLength(1));
      expect(scripts.single, contains('"wheel":true'));

      _emitHandoff(bundle.webview, deltaY: 50);
      await _settleHandoff(tester);
      expect(scrollController.offset, 50);
    });

    testWidgets(
      'removing the editor disables sources on an external controller',
      (tester) async {
        final bundle = await _createBundle();
        addTearDown(bundle.controller.dispose);
        final scrollController = ScrollController();
        addTearDown(scrollController.dispose);

        await tester.pumpWidget(
          _editorInScrollView(
            controller: bundle.controller,
            scrollController: scrollController,
            scrollHandoff: const MonacoScrollHandoff.edge(),
          ),
        );
        await tester.pump();
        expect(
          bundle.webview.scriptsContaining('"setScrollHandoff"'),
          hasLength(1),
        );

        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pump();

        final scripts = bundle.webview.scriptsContaining('"setScrollHandoff"');
        expect(scripts, hasLength(2));
        expect(scripts.last, contains('"wheel":false'));
        expect(scripts.last, contains('"touch":false'));
      },
    );
  });
}
