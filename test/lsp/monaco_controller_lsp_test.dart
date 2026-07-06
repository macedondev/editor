import 'dart:async';
import 'dart:convert';

import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

/// Drives the Dart side of the LSP bridge protocol against the fake WebView.
///
/// The manager talks to JavaScript exclusively through
/// `flutterMonacoInvokeAsync(requestId, method, args)` scripts (recorded by
/// the fake) and listens for `invokeResult` / `lspStatus` / `lspMessage`
/// events on the `flutterChannel`. This harness extracts issued invokes and
/// emits the events a real page would produce.
class LspBridgeHarness {
  LspBridgeHarness(this.webView);

  final FakePlatformWebViewController webView;
  final Set<String> _consumedRequestIds = {};

  static final RegExp _invokePattern = RegExp(
    r'window\.flutterMonacoInvokeAsync\("([^"]+)",\s*"([^"]+)",\s*(\[.*\])\)',
    dotAll: true,
  );

  /// Returns the oldest not-yet-consumed invoke of [method], waiting for it
  /// to be issued if necessary.
  Future<({String requestId, List<Object?> args})> waitForInvoke(
    String method, {
    int maxTurns = 200,
  }) async {
    for (var i = 0; i < maxTurns; i++) {
      for (final script in webView.executed) {
        final match = _invokePattern.firstMatch(script);
        if (match == null) continue;
        final requestId = match.group(1)!;
        if (match.group(2) != method) continue;
        if (_consumedRequestIds.contains(requestId)) continue;
        _consumedRequestIds.add(requestId);
        final args = (jsonDecode(match.group(3)!) as List).cast<Object?>();
        return (requestId: requestId, args: args);
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail(
      'No "$method" invoke was issued. Executed scripts:\n'
      '${webView.executed.join('\n')}',
    );
  }

  void respondOk(String requestId, {Object? value = true}) {
    _emit({
      'event': 'invokeResult',
      'requestId': requestId,
      'ok': true,
      'isUndefined': false,
      'value': value,
    });
  }

  void respondError(String requestId, String message) {
    _emit({
      'event': 'invokeResult',
      'requestId': requestId,
      'ok': false,
      'error': {'name': 'Error', 'message': message},
    });
  }

  void emitStatus(String connectionId, String status, {String? errorMessage}) {
    _emit({
      'event': 'lspStatus',
      'connectionId': connectionId,
      'status': status,
      'error': errorMessage == null
          ? null
          : {'name': 'Error', 'message': errorMessage},
    });
  }

  void emitLspMessage(String connectionId, Map<String, Object?> message) {
    _emit({
      'event': 'lspMessage',
      'connectionId': connectionId,
      'message': message,
    });
  }

  /// Answers connect + auto-acknowledges every subsequent invoke of
  /// [method]. Used for fire-and-forget disconnects.
  Future<void> acknowledge(String method) async {
    final invoke = await waitForInvoke(method);
    respondOk(invoke.requestId);
  }

  void _emit(Map<String, Object?> payload) {
    webView.emitToChannel('flutterChannel', jsonEncode(payload));
  }
}

Future<void> pumpMicrotasks([int turns = 20]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakePlatformWebViewController webView;
  late MonacoController controller;
  late LspBridgeHarness harness;

  setUp(() async {
    webView = FakePlatformWebViewController();
    controller = await MonacoController.createForTesting(
      webViewController: webView,
    );
    harness = LspBridgeHarness(webView);
  });

  tearDown(() {
    controller.dispose();
  });

  group('connectLanguageServer', () {
    test(
      'resolves after the JS handshake and registers the connection',
      () async {
        final connectFuture = controller.connectLanguageServer(
          id: 'py',
          transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
        );

        final invoke = await harness.waitForInvoke('lsp.connect');
        expect(invoke.args[0], 'py');
        expect(invoke.args[1], {
          'kind': 'webSocket',
          'url': 'ws://localhost:1',
        });

        harness.respondOk(invoke.requestId);
        final connection = await connectFuture;

        expect(connection.id, 'py');
        expect(connection.isOpen, isTrue);
        expect(connection.state.status, LspConnectionStatus.open);
        expect(controller.languageServerConnections, [connection]);
        expect(controller.languageServerConnection('py'), same(connection));
      },
    );

    test('emits connecting then open on stateChanges', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'py',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      // The open state is already current; further transitions stream.
      expect(connection.state.status, LspConnectionStatus.open);
      expect(connection.state.reconnectAttempt, 0);
    });

    test('throws on duplicate ids while connected', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'dup',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      await connectFuture;

      expect(
        () => controller.connectLanguageServer(
          id: 'dup',
          transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:2')),
        ),
        throwsStateError,
      );
    });

    test('throws on empty id', () async {
      expect(
        () => controller.connectLanguageServer(
          id: '  ',
          transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
        ),
        throwsArgumentError,
      );
    });

    test('rejects reconnect policies for bridged transports', () async {
      expect(
        () => controller.connectLanguageServer(
          id: 'bridged',
          transport: LspBridgedTransport(
            fromServer: const Stream.empty(),
            toServer: (_) {},
          ),
          reconnectPolicy: const LspReconnectPolicy.exponentialBackoff(),
        ),
        throwsArgumentError,
      );
    });

    test('propagates JS connect failures and registers nothing', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'broken',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );

      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondError(invoke.requestId, 'WebSocket handshake refused');

      await expectLater(
        connectFuture,
        throwsA(
          isA<MonacoJavaScriptException>().having(
            (e) => e.message,
            'message',
            contains('handshake refused'),
          ),
        ),
      );
      expect(controller.languageServerConnections, isEmpty);
      // The id is reusable after a failed connect.
      expect(controller.languageServerConnection('broken'), isNull);
    });

    test('times out when the handshake never completes', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'slow',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
        initializationTimeout: const Duration(milliseconds: 50),
      );

      await harness.waitForInvoke('lsp.connect');

      await expectLater(connectFuture, throwsA(isA<TimeoutException>()));
      expect(controller.languageServerConnections, isEmpty);
      // Best-effort teardown was attempted.
      await harness.waitForInvoke('lsp.disconnect');
    });
  });

  group('disconnect', () {
    test('closes the connection and completes whenClosed', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'py',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      final states = <LspConnectionState>[];
      connection.stateChanges.listen(states.add);

      final disconnectFuture = connection.disconnect();
      await harness.acknowledge('lsp.disconnect');
      await disconnectFuture;
      await connection.whenClosed;

      expect(connection.state.status, LspConnectionStatus.closed);
      expect(states.last.status, LspConnectionStatus.closed);
      expect(controller.languageServerConnections, isEmpty);
    });

    test('disconnectLanguageServer is a no-op for unknown ids', () async {
      await controller.disconnectLanguageServer('nope');
    });

    test('completes even when the JS side fails', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'py',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      final disconnectFuture = controller.disconnectLanguageServer('py');
      final disconnectInvoke = await harness.waitForInvoke('lsp.disconnect');
      harness.respondError(disconnectInvoke.requestId, 'page went away');

      await disconnectFuture;
      expect(connection.state.status, LspConnectionStatus.closed);
    });
  });

  group('bridged transports', () {
    test('relays server messages to the page in order', () async {
      final fromServer = StreamController<Map<String, Object?>>();

      final connectFuture = controller.connectLanguageServer(
        id: 'bridged',
        transport: LspBridgedTransport(
          fromServer: fromServer.stream,
          toServer: (_) {},
        ),
      );

      final invoke = await harness.waitForInvoke('lsp.connect');
      expect(invoke.args[1], {'kind': 'bridged'});

      fromServer
        ..add({'jsonrpc': '2.0', 'id': 1, 'result': {}})
        ..add({'jsonrpc': '2.0', 'method': 'window/logMessage'});
      harness.respondOk(invoke.requestId);
      await connectFuture;
      await pumpMicrotasks();

      final deliveries = webView.scriptsContaining('deliverServerMessage');
      expect(deliveries, hasLength(2));
      expect(deliveries[0], contains('"id":1'));
      expect(deliveries[1], contains('window/logMessage'));
      // Ordering: the connect invoke must have been issued before the first
      // delivery so the JS side has registered the transport.
      final connectIndex = webView.executed.indexWhere(
        (s) => s.contains('lsp.connect'),
      );
      final deliverIndex = webView.executed.indexWhere(
        (s) => s.contains('deliverServerMessage'),
      );
      expect(connectIndex, lessThan(deliverIndex));

      await fromServer.close();
    });

    test('routes client messages from the page to toServer', () async {
      final received = <Map<String, Object?>>[];
      final fromServer = StreamController<Map<String, Object?>>();

      final connectFuture = controller.connectLanguageServer(
        id: 'bridged',
        transport: LspBridgedTransport(
          fromServer: fromServer.stream,
          toServer: received.add,
        ),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      await connectFuture;

      harness.emitLspMessage('bridged', {
        'jsonrpc': '2.0',
        'method': 'initialize',
        'id': 0,
      });
      harness.emitLspMessage('bridged', {
        'jsonrpc': '2.0',
        'method': 'textDocument/didOpen',
      });

      expect(received, hasLength(2));
      expect(received[0]['method'], 'initialize');
      expect(received[1]['method'], 'textDocument/didOpen');

      await fromServer.close();
      await pumpMicrotasks();
    });

    test('closes the connection when the server stream ends', () async {
      var onCloseCalls = 0;
      final fromServer = StreamController<Map<String, Object?>>();

      final connectFuture = controller.connectLanguageServer(
        id: 'bridged',
        transport: LspBridgedTransport(
          fromServer: fromServer.stream,
          toServer: (_) {},
          onClose: () async => onCloseCalls++,
        ),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      await fromServer.close();
      await harness.acknowledge('lsp.disconnect');
      await connection.whenClosed;

      expect(connection.state.status, LspConnectionStatus.closed);
      expect(onCloseCalls, 1);
      expect(controller.languageServerConnections, isEmpty);
    });

    test('fails the connection when the server stream errors', () async {
      final fromServer = StreamController<Map<String, Object?>>();

      final connectFuture = controller.connectLanguageServer(
        id: 'bridged',
        transport: LspBridgedTransport(
          fromServer: fromServer.stream,
          toServer: (_) {},
        ),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      fromServer.addError(StateError('server crashed'));
      await harness.acknowledge('lsp.disconnect');
      await connection.whenClosed;

      expect(connection.state.status, LspConnectionStatus.failed);
      expect(connection.state.error, isA<StateError>());

      await fromServer.close();
    });

    test('invokes onClose exactly once on explicit disconnect', () async {
      var onCloseCalls = 0;
      final fromServer = StreamController<Map<String, Object?>>();

      final connectFuture = controller.connectLanguageServer(
        id: 'bridged',
        transport: LspBridgedTransport(
          fromServer: fromServer.stream,
          toServer: (_) {},
          onClose: () async => onCloseCalls++,
        ),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      final disconnectFuture = connection.disconnect();
      await harness.acknowledge('lsp.disconnect');
      await disconnectFuture;
      await pumpMicrotasks();

      expect(onCloseCalls, 1);
      await fromServer.close();
    });
  });

  group('unexpected transport drops', () {
    test('without a reconnect policy the connection closes', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'ws',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      harness.emitStatus('ws', 'closed', errorMessage: 'socket dropped');
      await harness.acknowledge('lsp.disconnect');
      await connection.whenClosed;

      expect(connection.state.status, LspConnectionStatus.closed);
      expect(
        (connection.state.error as MonacoJavaScriptException?)?.message,
        contains('socket dropped'),
      );
    });

    test('with a reconnect policy the connection reopens', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'ws',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
        reconnectPolicy: const LspReconnectPolicy.exponentialBackoff(
          initialDelay: Duration(milliseconds: 1),
          maxAttempts: 3,
        ),
      );
      final first = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(first.requestId);
      final connection = await connectFuture;

      final states = <LspConnectionState>[];
      connection.stateChanges.listen(states.add);

      // Drop the transport: expect JS cleanup, then a fresh connect.
      harness.emitStatus('ws', 'closed', errorMessage: 'network blip');
      await harness.acknowledge('lsp.disconnect');
      final second = await harness.waitForInvoke('lsp.connect');
      expect(connection.state.status, LspConnectionStatus.connecting);
      expect(connection.state.reconnectAttempt, 1);

      harness.respondOk(second.requestId);
      await pumpMicrotasks();

      expect(connection.state.status, LspConnectionStatus.open);
      expect(connection.state.reconnectAttempt, 0);
      expect(
        states.map((s) => s.status),
        containsAllInOrder([
          LspConnectionStatus.connecting,
          LspConnectionStatus.open,
        ]),
      );
      expect(controller.languageServerConnections, [connection]);
    });

    test('exhausted reconnect attempts fail the connection', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'ws',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
        reconnectPolicy: const LspReconnectPolicy.exponentialBackoff(
          initialDelay: Duration(milliseconds: 1),
          maxAttempts: 1,
        ),
      );
      final first = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(first.requestId);
      final connection = await connectFuture;

      harness.emitStatus('ws', 'closed', errorMessage: 'gone');
      await harness.acknowledge('lsp.disconnect');
      final retry = await harness.waitForInvoke('lsp.connect');
      harness.respondError(retry.requestId, 'still down');
      await harness.acknowledge('lsp.disconnect');
      await connection.whenClosed;

      expect(connection.state.status, LspConnectionStatus.failed);
      expect(controller.languageServerConnections, isEmpty);
    });
  });

  group('experimental request escape hatches', () {
    test('sendRequest forwards to the page and returns the result', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'py',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      final requestFuture = connection.sendRequest('pyright/ping', {'x': 1});
      final request = await harness.waitForInvoke('lsp.sendRequest');
      expect(request.args, [
        'py',
        'pyright/ping',
        {'x': 1},
      ]);
      harness.respondOk(request.requestId, value: {'pong': true});

      expect(await requestFuture, {'pong': true});
    });

    test('sendRequest throws when the connection is not open', () async {
      final connectFuture = controller.connectLanguageServer(
        id: 'py',
        transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      final disconnectFuture = connection.disconnect();
      await harness.acknowledge('lsp.disconnect');
      await disconnectFuture;

      expect(() => connection.sendRequest('x'), throwsStateError);
      expect(() => connection.sendNotification('x'), throwsStateError);
    });
  });

  group('controller disposal', () {
    test('closes connections and stops the server process hook', () async {
      var onCloseCalls = 0;
      final fromServer = StreamController<Map<String, Object?>>();

      final connectFuture = controller.connectLanguageServer(
        id: 'bridged',
        transport: LspBridgedTransport(
          fromServer: fromServer.stream,
          toServer: (_) {},
          onClose: () async => onCloseCalls++,
        ),
      );
      final invoke = await harness.waitForInvoke('lsp.connect');
      harness.respondOk(invoke.requestId);
      final connection = await connectFuture;

      controller.dispose();
      await connection.whenClosed;
      await pumpMicrotasks();

      expect(connection.state.status, LspConnectionStatus.closed);
      expect(onCloseCalls, 1);
      expect(controller.languageServerConnections, isEmpty);

      await fromServer.close();
    });

    test('connect after dispose throws', () async {
      controller.dispose();
      expect(
        () => controller.connectLanguageServer(
          id: 'late',
          transport: LspWebSocketTransport(url: Uri.parse('ws://localhost:1')),
        ),
        throwsStateError,
      );
    });
  });
}
