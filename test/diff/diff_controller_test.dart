import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

Future<MonacoDiffController> _createController(
  FakePlatformWebViewController webview, {
  bool markReady = true,
}) {
  return MonacoDiffController.createForTesting(
    webViewController: webview,
    markReady: markReady,
  );
}

void main() {
  group('MonacoDiffController', () {
    test('whenReady completes and isReady flips', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.whenReady;
      expect(controller.isReady, isTrue);
    });

    test('setTexts dispatches diff.setTexts with language', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.setTexts(
        original: 'old',
        modified: 'new',
        language: MonacoLanguage.dart,
      );

      final call = webview.dispatched.singleWhere(
        (d) => d['method'] == 'diff.setTexts',
      );
      expect(call['params'], {
        'original': 'old',
        'modified': 'new',
        'language': 'dart',
      });
    });

    test('setTexts omits language when not given', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.setTexts(original: 'old', modified: 'new');

      final call = webview.dispatched.singleWhere(
        (d) => d['method'] == 'diff.setTexts',
      );
      expect(call['params'], {'original': 'old', 'modified': 'new'});
    });

    test('getModifiedText parses diff.getState', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      webview.injectCommandSuccess(
        'diff.getState',
        value: {
          'originalText': 'old',
          'modifiedText': 'new text',
          'lineChangeCount': 2,
          'language': 'dart',
        },
      );

      expect(await controller.getModifiedText(), 'new text');
    });

    test('getModifiedText throws MonacoProtocolError on bad shape', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      webview.injectCommandSuccess('diff.getState', value: {'nope': true});

      await expectLater(
        controller.getModifiedText(),
        throwsA(isA<MonacoProtocolError>()),
      );
    });

    test('getLineChangeCount parses diff.getState', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      webview.injectCommandSuccess(
        'diff.getState',
        value: {'modifiedText': 'x', 'lineChangeCount': 3},
      );

      expect(await controller.getLineChangeCount(), 3);
    });

    test(
      'getLineChangeCount treats an uncomputed diff as a timeout, not 0',
      () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        // The bridge reports lineChangeCount null when Monaco has not
        // computed the diff within the grace window; 0 is a real result.
        webview.injectCommandSuccess(
          'diff.getState',
          value: {'modifiedText': 'x', 'lineChangeCount': null},
        );

        await expectLater(
          controller.getLineChangeCount(),
          throwsA(isA<MonacoTimeoutError>()),
        );
      },
    );

    test(
      'getLineChangeCount throws MonacoProtocolError on bad shape',
      () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        webview.injectCommandSuccess('diff.getState', value: 'garbage');

        await expectLater(
          controller.getLineChangeCount(),
          throwsA(isA<MonacoProtocolError>()),
        );
      },
    );

    test('updateOptions sends sparse editor options', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.updateOptions(const EditorOptions(fontSize: 18));

      final call = webview.dispatched.singleWhere(
        (d) => d['method'] == 'diff.updateOptions',
      );
      expect(call['params'], {
        'options': {'fontSize': 18},
      });
    });

    test('updateDiffOptions sends sparse diff options', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.updateDiffOptions(
        const MonacoDiffOptions(
          renderSideBySide: false,
          ignoreTrimWhitespace: true,
        ),
      );

      final call = webview.dispatched.singleWhere(
        (d) => d['method'] == 'diff.updateOptions',
      );
      expect(call['params'], {
        'options': {'renderSideBySide': false, 'ignoreTrimWhitespace': true},
      });
    });

    test('MonacoDiffOptions.extra wins over typed fields', () {
      const options = MonacoDiffOptions(
        renderSideBySide: true,
        extra: {'renderSideBySide': false, 'custom': 1},
      );
      expect(options.toMonacoOptions(), {
        'renderSideBySide': false,
        'custom': 1,
      });
    });

    test('setTheme routes through diff.updateOptions', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.setTheme(MonacoTheme.hcBlack);

      final call = webview.dispatched.singleWhere(
        (d) => d['method'] == 'diff.updateOptions',
      );
      expect(call['params'], {
        'options': {'theme': 'hc-black'},
      });
    });

    test('reveal commands dispatch', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      await controller.revealNextChange();
      await controller.revealPreviousChange();

      expect(
        webview.dispatched.map((d) => d['method']),
        containsAll(['diff.revealNextChange', 'diff.revealPreviousChange']),
      );
    });

    test('commands queue until ready then flush in order', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview, markReady: false);

      final pending = controller.setTexts(original: 'a', modified: 'b');
      expect(
        webview.dispatched.where((d) => d['method'] == 'diff.setTexts'),
        isEmpty,
      );

      controller.completeReadyForTesting();
      await pending;

      expect(
        webview.dispatched.where((d) => d['method'] == 'diff.setTexts'),
        hasLength(1),
      );
    });

    test('dispose fails in-flight commands and releases the webview', () async {
      final webview = FakePlatformWebViewController();
      final controller = await _createController(webview);

      controller.dispose();
      controller.dispose(); // idempotent

      expect(webview.disposed, isTrue);
      await expectLater(
        controller.setTexts(original: 'a', modified: 'b'),
        throwsA(isA<MonacoException>()),
      );
    });

    group('failed boot gating', () {
      test(
        'a command issued after a failed boot rethrows the boot error',
        () async {
          final webview = FakePlatformWebViewController();
          final controller = await _createController(webview, markReady: false);
          final bootError = const MonacoTimeoutError(
            message: 'boot timed out',
            timeout: Duration(seconds: 1),
            operation: 'boot',
          );
          controller.failReadyForTesting(bootError);

          await expectLater(controller.whenReady, throwsA(same(bootError)));
          await expectLater(
            controller.setTexts(original: 'a', modified: 'b'),
            throwsA(same(bootError)),
          );
          expect(webview.dispatched, isEmpty);
        },
      );

      test(
        'a command after dispose-during-boot throws MonacoDisposedError',
        () async {
          final webview = FakePlatformWebViewController();
          final controller = await _createController(webview, markReady: false);
          controller.dispose();

          await expectLater(
            controller
                .setTexts(original: 'a', modified: 'b')
                .timeout(const Duration(seconds: 1)),
            throwsA(isA<MonacoDisposedError>()),
          );
        },
      );
    });
  });
}
