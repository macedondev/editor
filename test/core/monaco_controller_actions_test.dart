import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

Future<MonacoController> _createController(
  FakePlatformWebViewController webview,
) async {
  return MonacoController.createForTesting(
    webViewController: webview,
    markReady: true,
  );
}

const _saveDescriptor = MonacoActionDescriptor(
  id: MonacoAction('demo.save'),
  label: 'Save File',
  keybindings: [MonacoKeybinding(key: MonacoKey.keyS, ctrlCmd: true)],
);

void main() {
  group('MonacoController custom actions', () {
    group('registration', () {
      test('addAction dispatches actions.register with the full '
          'descriptor wire form', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        final registration = await controller.addAction(
          const MonacoActionDescriptor(
            id: MonacoAction('demo.save'),
            label: 'Save File',
            keybindings: [
              MonacoKeybinding(key: MonacoKey.keyS, ctrlCmd: true),
              MonacoKeybinding(
                key: MonacoKey.f5,
                shift: true,
                alt: true,
                winCtrl: true,
              ),
            ],
            contextMenuGroupId: 'navigation',
            contextMenuOrder: 1.5,
            precondition: 'editorTextFocus',
          ),
          () async {},
        );

        expect(registration.id, const MonacoAction('demo.save'));
        final call = webview.dispatched.singleWhere(
          (d) => d['method'] == 'actions.register',
        );
        // Keybinding serialization golden: symbolic parts only, composed
        // into monaco.KeyMod/KeyCode bitmasks on the JS side.
        expect(call['params'], {
          'id': 'demo.save',
          'label': 'Save File',
          'keybindings': [
            {
              'key': 'KeyS',
              'ctrlCmd': true,
              'shift': false,
              'alt': false,
              'winCtrl': false,
            },
            {
              'key': 'F5',
              'ctrlCmd': false,
              'shift': true,
              'alt': true,
              'winCtrl': true,
            },
          ],
          'contextMenuGroupId': 'navigation',
          'contextMenuOrder': 1.5,
          'precondition': 'editorTextFocus',
        });
      });

      test(
        'descriptor without optional fields omits them from the wire',
        () async {
          final webview = FakePlatformWebViewController();
          final controller = await _createController(webview);

          await controller.addAction(
            const MonacoActionDescriptor(
              id: MonacoAction('demo.plain'),
              label: 'Plain',
            ),
            () async {},
          );

          final call = webview.dispatched.singleWhere(
            (d) => d['method'] == 'actions.register',
          );
          expect(call['params'], {
            'id': 'demo.plain',
            'label': 'Plain',
            'keybindings': <Object?>[],
          });
        },
      );

      test('duplicate action id throws ArgumentError', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.addAction(_saveDescriptor, () async {});

        expect(
          () => controller.addAction(_saveDescriptor, () async {}),
          throwsArgumentError,
        );
      });

      test('failed bridge registration rolls the action back', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        webview.injectCommandFailure('actions.register', message: 'no editor');
        await expectLater(
          controller.addAction(_saveDescriptor, () async {}),
          throwsA(isA<MonacoJavaScriptError>()),
        );

        // The id is free again.
        final registration = await controller.addAction(
          _saveDescriptor,
          () async {},
        );
        expect(registration.id, const MonacoAction('demo.save'));
      });
    });

    group('invocation over the request channel', () {
      test('action request runs the callback and responds with {}', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        var runs = 0;

        await controller.addAction(_saveDescriptor, () async {
          runs++;
        });

        webview.emitRequest('q1', 'action', {'actionId': 'demo.save'});
        await pumpEventQueue();

        expect(runs, 1);
        final respond = webview.responded.single;
        expect(respond['id'], 'q1');
        expect(respond['ok'], isTrue);
        expect(respond['value'], isEmpty);
      });

      test('callback error responds ok:false with the message', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.addAction(_saveDescriptor, () async {
          throw StateError('disk full');
        });

        webview.emitRequest('q1', 'action', {'actionId': 'demo.save'});
        await pumpEventQueue();

        final respond = webview.responded.single;
        expect(respond['ok'], isFalse);
        final error = respond['error']! as Map<String, Object?>;
        expect(error['message'], contains('disk full'));
      });

      test('async callback completes before the response is sent', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        var finished = false;

        await controller.addAction(_saveDescriptor, () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          finished = true;
        });

        webview.emitRequest('q1', 'action', {'actionId': 'demo.save'});
        await pumpEventQueue();
        expect(webview.responded, isEmpty);

        await Future<void>.delayed(const Duration(milliseconds: 40));
        await pumpEventQueue();

        expect(finished, isTrue);
        expect(webview.responded.single['ok'], isTrue);
      });

      test('unknown action id responds ok:false', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.addAction(_saveDescriptor, () async {});

        webview.emitRequest('q1', 'action', {'actionId': 'not.registered'});
        await pumpEventQueue();

        final respond = webview.responded.single;
        expect(respond['ok'], isFalse);
      });

      test('missing actionId responds ok:false', () async {
        final webview = FakePlatformWebViewController();
        await _createController(webview);

        webview.emitRequest('q1', 'action', {});
        await pumpEventQueue();

        expect(webview.responded.single['ok'], isFalse);
      });
    });

    group('disposal', () {
      test('registration.dispose dispatches actions.unregister and stops '
          'the callback', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        var runs = 0;

        final registration = await controller.addAction(
          _saveDescriptor,
          () async {
            runs++;
          },
        );

        await registration.dispose();
        expect(registration.isDisposed, isTrue);

        final calls = webview.dispatched
            .where((d) => d['method'] == 'actions.unregister')
            .toList();
        expect(calls, hasLength(1));
        expect(
          (calls.single['params']! as Map<String, Object?>)['id'],
          'demo.save',
        );

        // A late invocation no longer reaches the callback.
        webview.emitRequest('q1', 'action', {'actionId': 'demo.save'});
        await pumpEventQueue();
        expect(runs, 0);
        expect(webview.responded.single['ok'], isFalse);
      });

      test('double dispose is a no-op', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        final registration = await controller.addAction(
          _saveDescriptor,
          () async {},
        );

        await registration.dispose();
        await registration.dispose();

        final calls = webview.dispatched
            .where((d) => d['method'] == 'actions.unregister')
            .toList();
        expect(calls, hasLength(1));
      });

      test('the id can be reused after dispose', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        final registration = await controller.addAction(
          _saveDescriptor,
          () async {},
        );
        await registration.dispose();

        final again = await controller.addAction(_saveDescriptor, () async {});
        expect(again.id, const MonacoAction('demo.save'));
      });

      test(
        'registration.dispose after controller.dispose is a no-op',
        () async {
          final webview = FakePlatformWebViewController();
          final controller = await _createController(webview);

          final registration = await controller.addAction(
            _saveDescriptor,
            () async {},
          );

          controller.dispose();
          await registration.dispose();

          expect(
            webview.dispatched.where(
              (d) => d['method'] == 'actions.unregister',
            ),
            isEmpty,
          );
        },
      );
    });
  });
}
