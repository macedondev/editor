import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';

import 'package:flutter_monaco/src/core/monaco_js_error.dart';
import 'package:flutter_monaco/src/protocol/envelope.dart';
import 'package:flutter_monaco/src/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

void main() {
  group('EnvelopeMessage.decode', () {
    test('decodes lifecycle pageReady with handshake fields', () {
      final envelope = EnvelopeMessage.decode(
        jsonEncode({
          'v': 3,
          'kind': 'lifecycle',
          'name': 'pageReady',
          'protocolVersion': 3,
          'monacoVersion': '0.55.1',
          'capabilities': ['lsp'],
        }),
      );
      expect(envelope, isA<LifecycleEnvelope>());
      final handshake = MonacoHandshake.fromEnvelope(
        (envelope! as LifecycleEnvelope).json,
      );
      expect(handshake.protocolVersion, 3);
      expect(handshake.monacoVersion, '0.55.1');
      expect(handshake.capabilities, {'lsp'});
    });

    test('decodes success and failure responses', () {
      final ok =
          EnvelopeMessage.decode(
                '{"v":3,"kind":"response","id":"r1","ok":true,"undefined":false,'
                '"value":42}',
              )!
              as ResponseEnvelope;
      expect(ok.ok, true);
      expect(ok.value, 42);
      expect(ok.isUndefined, false);

      final fail =
          EnvelopeMessage.decode(
                '{"v":3,"kind":"response","id":"r2","ok":false,'
                '"error":{"name":"TypeError","message":"boom","stack":null}}',
              )!
              as ResponseEnvelope;
      expect(fail.ok, false);
      expect(fail.error?['message'], 'boom');
    });

    test('decodes events with seq and data', () {
      final envelope =
          EnvelopeMessage.decode(
                '{"v":3,"kind":"event","seq":7,"name":"contentChanged",'
                '"data":{"isFlush":true}}',
              )!
              as EventEnvelope;
      expect(envelope.event.name, 'contentChanged');
      expect(envelope.event.seq, 7);
      expect(envelope.event.data['isFlush'], true);
    });

    test('decodes requests', () {
      final envelope =
          EnvelopeMessage.decode(
                '{"v":3,"kind":"request","id":"q1","name":"completion",'
                '"data":{"requestId":"q1"}}',
              )!
              as RequestEnvelope;
      expect(envelope.request.name, 'completion');
      expect(envelope.request.id, 'q1');
    });

    test('returns null for non-envelope payloads', () {
      expect(EnvelopeMessage.decode('ready'), isNull);
      expect(EnvelopeMessage.decode('not json {'), isNull);
      expect(EnvelopeMessage.decode('{"event":"onEditorReady"}'), isNull);
      expect(EnvelopeMessage.decode('[]'), isNull);
    });

    test('unknown kinds surface as UnknownEnvelope', () {
      expect(
        EnvelopeMessage.decode('{"v":3,"kind":"telemetry"}'),
        isA<UnknownEnvelope>(),
      );
    });
  });

  group('MonacoProtocol', () {
    late FakePlatformWebViewController webview;
    late MonacoProtocol protocol;

    setUp(() async {
      webview = FakePlatformWebViewController();
      protocol = MonacoProtocol(webView: webview);
      await webview.addJavaScriptChannel(
        'flutterChannel',
        protocol.handleChannelMessage,
      );
    });

    tearDown(() {
      if (!protocol.isDisposed) protocol.dispose();
    });

    test('invoke resolves with the response value', () async {
      webview.injectCommandSuccess('document.getText', value: 'hello');
      final result = await protocol.invoke('document.getText', {'uri': null});
      expect(result, 'hello');
    });

    test('invoke resolves undefined results to the sentinel', () async {
      final result = await protocol.invoke('document.setText', {
        'uri': null,
        'text': 'x',
      });
      expect(identical(result, monacoJsUndefined), true);
    });

    test('invoke throws MonacoJavaScriptException on error response', () async {
      webview.injectCommandFailure(
        'editor.setTheme',
        name: 'TypeError',
        message: 'no such theme',
      );
      await expectLater(
        protocol.invoke('editor.setTheme', {'theme': 'nope'}),
        throwsA(
          isA<MonacoJavaScriptException>()
              .having((e) => e.operation, 'operation', 'editor.setTheme')
              .having((e) => e.message, 'message', 'no such theme')
              .having((e) => e.name, 'name', 'TypeError'),
        ),
      );
    });

    test('invoke times out when no response arrives', () async {
      final silent = FakePlatformWebViewController()..autoRespond = false;
      final silentProtocol = MonacoProtocol(webView: silent);
      await expectLater(
        silentProtocol.invoke(
          'document.getText',
          {},
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
      silentProtocol.dispose();
    });

    test('correlates out-of-order responses by id', () async {
      // Take manual control: no auto-response, answer r2 before r1.
      final manual = FakePlatformWebViewController();
      final manualProtocol = MonacoProtocol(webView: manual);
      await manual.addJavaScriptChannel(
        'flutterChannel',
        manualProtocol.handleChannelMessage,
      );
      manual.autoRespond = false;

      final futures = <Future<Object?>>[
        manualProtocol.invoke('a.first', {}),
        manualProtocol.invoke('b.second', {}),
      ];
      expect(manual.dispatched, hasLength(2));
      final firstId = manual.dispatched[0]['id']! as String;
      final secondId = manual.dispatched[1]['id']! as String;

      manual.emitToChannel(
        'flutterChannel',
        jsonEncode({
          'v': 3,
          'kind': 'response',
          'id': secondId,
          'ok': true,
          'undefined': false,
          'value': 'second',
        }),
      );
      manual.emitToChannel(
        'flutterChannel',
        jsonEncode({
          'v': 3,
          'kind': 'response',
          'id': firstId,
          'ok': true,
          'undefined': false,
          'value': 'first',
        }),
      );

      expect(await futures[0], 'first');
      expect(await futures[1], 'second');
      manualProtocol.dispose();
    });

    test('pageReady completes with handshake; version skew errors', () async {
      protocol.handleChannelMessage(
        jsonEncode({
          'v': 3,
          'kind': 'lifecycle',
          'name': 'pageReady',
          'protocolVersion': 3,
          'monacoVersion': '0.55.1',
          'capabilities': ['lsp'],
        }),
      );
      final handshake = await protocol.pageReady;
      expect(handshake.monacoVersion, '0.55.1');

      final skewed = MonacoProtocol(webView: webview);
      skewed.handleChannelMessage(
        jsonEncode({
          'v': 3,
          'kind': 'lifecycle',
          'name': 'pageReady',
          'protocolVersion': 2,
        }),
      );
      await expectLater(
        skewed.pageReady,
        throwsA(isA<MonacoJavaScriptException>()),
      );
      skewed.dispose();
    });

    test('lifecycle fatal fails editorReady', () async {
      protocol.handleChannelMessage(
        jsonEncode({
          'v': 3,
          'kind': 'lifecycle',
          'name': 'fatal',
          'error': {'name': 'RequireError', 'message': 'no editor.main'},
        }),
      );
      await expectLater(
        protocol.editorReady,
        throwsA(
          isA<MonacoJavaScriptException>().having(
            (e) => e.message,
            'message',
            'no editor.main',
          ),
        ),
      );
    });

    test('events stream decodes payloads in order', () async {
      final events = <ProtocolEvent>[];
      protocol.events.listen(events.add);
      webview.emitEvent('stats', {'lineCount': 3});
      webview.emitEvent('focusChanged', {'focused': true});
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
      expect(events[0].name, 'stats');
      expect(events[0].data['lineCount'], 3);
      expect(events[1].name, 'focusChanged');
    });

    test('dispose fails pending invokes with StateError', () async {
      final silent = FakePlatformWebViewController();
      final silentProtocol = MonacoProtocol(webView: silent);
      silent.autoRespond = false;
      final future = silentProtocol.invoke('document.getText', {});
      final expectation = expectLater(future, throwsA(isA<StateError>()));
      silentProtocol.dispose();
      await expectation;
    });

    test('sync dispatch failure settles the response future immediately', () {
      fakeAsync((async) {
        final broken = FakePlatformWebViewController()
          ..throwOnContains('FlutterMonaco.dispatch');
        final brokenProtocol = MonacoProtocol(webView: broken);
        Object? caught;
        brokenProtocol.invoke('document.getText', {}).catchError((Object e) {
          caught = e;
          return null;
        });
        async.flushMicrotasks();
        expect(caught, isA<MonacoJavaScriptException>());
        // No stray timeout timer may remain armed.
        expect(async.pendingTimers, isEmpty);
        brokenProtocol.dispose();
      });
    });

    test('invoke after dispose throws StateError', () async {
      protocol.dispose();
      expect(
        () => protocol.invoke('document.getText', {}),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'U+2028/U+2029 in params are escaped in the dispatch script',
      () async {
        webview.injectCommandSuccess('document.setText', value: true);
        await protocol.invoke('document.setText', {
          'uri': null,
          'text': 'line\u2028sep\u2029end',
        });
        final script = webview.executed.lastWhere(
          (s) => s.contains('document.setText'),
        );
        expect(script.contains('\u2028'), false);
        expect(script.contains('\u2029'), false);
        expect(script, contains(r'\u2028'));
        expect(script, contains(r'\u2029'));
      },
    );
  });
}
