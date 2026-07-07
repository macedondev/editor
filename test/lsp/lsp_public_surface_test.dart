import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Blueprint Phase 8 gate: the public LSP surface ships UNCHANGED from
/// 2.3.0. These goldens are hand-kept from the 2.3.0 sources; any diff here
/// is an accidental break of the "LSP kept as-is by design" promise
/// (upcoming/v3.md) and must be reverted, not accepted into the golden.
void main() {
  group('LSP public surface (2.3.0 golden)', () {
    test('barrel exports exactly the 2.3.0 LSP symbols', () {
      final barrel = File('lib/flutter_monaco.dart').readAsStringSync();
      final statements =
          RegExp(r"export 'src/lsp/[^']+'[^;]*;")
              .allMatches(barrel)
              .map((m) => m.group(0)!.replaceAll(RegExp(r'\s+'), ' '))
              .toList()
            ..sort();

      expect(statements, const [
        "export 'src/lsp/lsp_connection.dart' show LanguageServerConnection;",
        "export 'src/lsp/lsp_server_process.dart' show LspServerProcess;",
        "export 'src/lsp/lsp_stdio_framing.dart' "
            'show LspStdioMessageDecoder, LspStdioMessageEncoder;',
        "export 'src/lsp/lsp_transport.dart' show LspBridgedTransport, "
            'LspCustomTransport, LspTransport, LspTransportKind, '
            'LspWebSocketTransport;',
        "export 'src/lsp/lsp_types.dart' show LspConnectionState, "
            'LspConnectionStatus, LspReconnectPolicy;',
      ]);
    });

    test('top-level public declarations per file match 2.3.0', () {
      const golden = <String, List<String>>{
        // MonacoLspManager is public-in-file but NOT exported (the
        // controller imports it via src path); it was the same in 2.3.0.
        'lsp_connection.dart': ['LanguageServerConnection', 'MonacoLspManager'],
        'lsp_server_process.dart': [],
        'lsp_server_process_io.dart': ['LspServerProcess'],
        'lsp_server_process_stub.dart': ['LspServerProcess'],
        'lsp_stdio_framing.dart': [
          'LspStdioMessageEncoder',
          'LspStdioMessageDecoder',
        ],
        'lsp_transport.dart': [
          'LspTransportKind',
          'LspTransport',
          'LspWebSocketTransport',
          'LspBridgedTransport',
          'LspCustomTransport',
        ],
        'lsp_types.dart': [
          'LspConnectionStatus',
          'LspConnectionState',
          'LspReconnectPolicy',
        ],
      };

      final files = Directory('lib/src/lsp')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final declPattern = RegExp(
        r'^(?:abstract\s+|final\s+|sealed\s+|base\s+)*'
        r'(?:class|enum|mixin|typedef|extension)\s+([A-Za-z]\w*)',
        multiLine: true,
      );

      final actual = <String, List<String>>{
        for (final file in files)
          file.uri.pathSegments.last: declPattern
              .allMatches(file.readAsStringSync())
              .map((m) => m.group(1)!)
              .where((name) => !name.startsWith('_'))
              .toList(),
      };

      expect(actual, golden);
    });

    test('LanguageServerConnection keeps its 2.3.0 member surface', () {
      final source = File('lib/src/lsp/lsp_connection.dart').readAsStringSync();
      final classBody = RegExp(
        r'class LanguageServerConnection[^{]*\{(.*?)^\}',
        dotAll: true,
        multiLine: true,
      ).firstMatch(source)!.group(1)!;

      final memberPattern = RegExp(
        r'^  (?:static\s+|final\s+|const\s+|late\s+)*'
        r'(?:[A-Za-z_][\w<>,?\s()]*?\s)?'
        r'(?:get\s+|set\s+)?([a-zA-Z]\w*)\s*[({=;]',
      );
      const nonDeclarations = {
        'return', 'throw', 'if', 'for', 'while', 'switch', 'assert',
        'await', 'case', 'unawaited', // statement keywords/calls, not members
      };

      final members = <String>{};
      for (final line in classBody.split('\n')) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') ||
            trimmed.startsWith('*') ||
            trimmed.startsWith('/*')) {
          continue;
        }
        final match = memberPattern.firstMatch(line);
        final name = match?.group(1);
        if (name != null && !nonDeclarations.contains(name)) {
          members.add(name);
        }
      }

      // Hand-kept from 2.3.0 (scraped from the 2.3.0 source with this exact
      // pattern and verified identical on 2026-07-07).
      expect(members, {
        'id',
        'transport',
        'reconnectPolicy',
        'state',
        'stateChanges',
        'whenClosed',
        'isOpen',
        'sendRequest',
        'sendNotification',
        'disconnect',
        'toString',
      });
    });
  });
}
