import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('generateIndexHtml LSP bridge', () {
    test(
      'bundled Monaco version is 0.55.1 (first version with monaco.lsp)',
      () {
        expect(MonacoAssets.monacoVersion, '0.55.1');
        expect(MonacoAssets.htmlGenerationVersion, greaterThanOrEqualTo(4));
      },
    );

    test('installs the flutterMonaco.lsp namespace', () {
      final html = MonacoAssets.generateIndexHtml('min/vs');

      expect(html, contains('window.flutterMonaco.lsp'));
      expect(html, contains('deliverServerMessage'));
      expect(html, contains('disconnectAll'));
      expect(html, contains('monaco.lsp.MonacoLspClient'));
      expect(html, contains('monaco.lsp.WebSocketTransport.connectTo'));
    });

    test('acknowledges optional server refresh requests', () {
      final html = MonacoAssets.generateIndexHtml('min/vs');

      // Monaco 0.55.1 answers these with method-not-found, which kills
      // servers like pyright via an unhandled rejection; the bridge must
      // register benign handlers instead.
      expect(html, contains('workspace/diagnostic/refresh'));
      expect(html, contains('workspace/semanticTokens/refresh'));
      expect(html, contains('workspace/codeLens/refresh'));
      expect(html, contains('registerBenignRefreshHandlers'));
    });

    test('installs the async invocation envelope', () {
      final html = MonacoAssets.generateIndexHtml('min/vs');

      expect(html, contains('window.flutterMonacoInvokeAsync'));
      expect(html, contains("event: 'invokeResult'"));
    });

    test('prefers monaco.json with a legacy namespace fallback', () {
      final html = MonacoAssets.generateIndexHtml('min/vs');

      expect(html, contains("typeof monaco.json !== 'undefined'"));
      expect(html, contains('monaco.languages && monaco.languages.json'));
    });

    test('default CSP stays locked down', () {
      final html = MonacoAssets.generateIndexHtml('min/vs');

      expect(html, contains("connect-src 'self' blob:;"));
      expect(html, isNot(contains('ws://')));
    });

    test('allowedConnectSources extends connect-src only', () {
      final html = MonacoAssets.generateIndexHtml(
        'min/vs',
        allowedConnectSources: ['ws://127.0.0.1:3000', 'wss://lsp.example.com'],
      );

      expect(
        html,
        contains(
          "connect-src 'self' blob: ws://127.0.0.1:3000 wss://lsp.example.com;",
        ),
      );
      // The other directives must not gain the new sources.
      expect(html, isNot(contains("script-src 'self' file: ws://")));
    });

    test('rejects CSP source expressions that could inject directives', () {
      for (final malicious in [
        "ws://x; script-src 'unsafe-eval'",
        'ws://x"',
        "ws://x'",
        'ws://a b',
        'ws://x<script>',
      ]) {
        expect(
          () => MonacoAssets.generateIndexHtml(
            'min/vs',
            allowedConnectSources: [malicious],
          ),
          throwsArgumentError,
          reason: 'should reject: $malicious',
        );
      }
    });

    test('ignores blank entries in allowedConnectSources', () {
      final html = MonacoAssets.generateIndexHtml(
        'min/vs',
        allowedConnectSources: ['', '  '],
      );
      expect(html, contains("connect-src 'self' blob:;"));
    });
  });
}
