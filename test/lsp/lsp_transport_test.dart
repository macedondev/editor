import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LspWebSocketTransport', () {
    test('produces a stable bridge payload', () {
      final transport = LspWebSocketTransport(
        url: Uri.parse('ws://127.0.0.1:3000/python'),
      );

      expect(transport.kind, LspTransportKind.webSocket);
      expect(transport.toBridgePayload(), {
        'kind': 'webSocket',
        'url': 'ws://127.0.0.1:3000/python',
      });
    });

    test('accepts wss URLs', () {
      final transport = LspWebSocketTransport(
        url: Uri.parse('wss://lsp.example.com'),
      );
      expect(transport.toBridgePayload()['url'], 'wss://lsp.example.com');
    });

    test('rejects non-WebSocket schemes', () {
      expect(
        () => LspWebSocketTransport(url: Uri.parse('http://example.com')),
        throwsArgumentError,
      );
      expect(
        () => LspWebSocketTransport(url: Uri.parse('file:///tmp/socket')),
        throwsArgumentError,
      );
    });
  });

  group('LspCustomTransport', () {
    test('produces a stable bridge payload with config', () {
      final transport = LspCustomTransport(
        factoryName: 'myWorker',
        config: {'workerUrl': 'worker.js'},
      );

      expect(transport.kind, LspTransportKind.custom);
      expect(transport.toBridgePayload(), {
        'kind': 'custom',
        'factoryName': 'myWorker',
        'config': {'workerUrl': 'worker.js'},
      });
    });

    test('defaults to an empty config', () {
      final transport = LspCustomTransport(factoryName: 'echo');
      expect(transport.toBridgePayload()['config'], isEmpty);
    });

    test('rejects empty factory names', () {
      expect(() => LspCustomTransport(factoryName: ''), throwsArgumentError);
      expect(() => LspCustomTransport(factoryName: '   '), throwsArgumentError);
    });
  });

  group('LspBridgedTransport', () {
    test('produces a minimal bridge payload', () {
      final transport = LspBridgedTransport(
        fromServer: const Stream.empty(),
        toServer: (_) {},
      );

      expect(transport.kind, LspTransportKind.bridged);
      expect(transport.toBridgePayload(), {'kind': 'bridged'});
    });
  });
}
