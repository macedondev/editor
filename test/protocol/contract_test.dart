import 'dart:convert';

import 'package:flutter_monaco/src/protocol/envelope.dart';
import 'package:flutter_monaco/src/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';
import '../helpers/bridge_sources.dart';

/// One wire-contract fixture: the exact dispatch payload Dart emits for a
/// command and a representative response the page may answer with.
class ContractCase {
  const ContractCase(
    this.method,
    this.params, {
    this.responseValue,
    this.responseUndefined = false,
  });

  final String method;
  final Map<String, Object?> params;
  final Object? responseValue;
  final bool responseUndefined;
}

/// The protocol v3 command registry (upcoming/v3.md table 6.3, Phase 2
/// subset). Every command registered by the bridge JS must have a fixture
/// here; the gap test below enforces it in both directions.
const List<ContractCase> contractCases = [
  ContractCase('page.eval', {'expression': '1 + 1'}, responseValue: 2),
  ContractCase('page.setBackground', {
    'color': 'rgba(30, 30, 30, 1.0)',
  }, responseUndefined: true),
  ContractCase('page.setScrollHandoff', {
    'wheel': true,
    'touch': false,
  }, responseValue: true),
  ContractCase('focus.force', {'replayInputFocus': false}, responseValue: true),
  ContractCase('document.getText', {'uri': null}, responseValue: 'text'),
  ContractCase('document.setText', {
    'uri': null,
    'text': 'hello',
  }, responseUndefined: true),
  ContractCase('document.lineCount', {'uri': null}, responseValue: 12),
  ContractCase(
    'document.getLines',
    {'uri': null, 'startLine': 1, 'endLine': 2},
    responseValue: ['a', 'b'],
  ),
  ContractCase('document.setLanguage', {
    'language': 'dart',
  }, responseUndefined: true),
  ContractCase('document.getLanguage', {'uri': null}, responseValue: 'dart'),
  ContractCase('document.applyEdits', {
    'uri': null,
    'edits': [
      {
        'range': {
          'startLineNumber': 1,
          'startColumn': 1,
          'endLineNumber': 1,
          'endColumn': 1,
        },
        'text': 'x',
      },
    ],
  }, responseUndefined: true),
  ContractCase(
    'document.findMatches',
    {
      'uri': null,
      'query': 'foo',
      'isRegex': false,
      'matchCase': false,
      'wholeWord': false,
      'limit': 1000,
    },
    responseValue: [
      {
        'range': {
          'startLineNumber': 1,
          'startColumn': 1,
          'endLineNumber': 1,
          'endColumn': 4,
        },
        'match': 'foo',
      },
    ],
  ),
  ContractCase('document.replaceMatches', {
    'uri': null,
    'query': 'foo',
    'replacement': 'bar',
    'isRegex': false,
    'matchCase': false,
    'wholeWord': false,
  }, responseValue: 3),
  ContractCase('document.getWordAt', {
    'uri': null,
    'position': {'lineNumber': 1, 'column': 2},
  }, responseValue: 'word'),
  ContractCase('document.isDirty', {'uri': null}, responseValue: false),
  ContractCase('document.markSaved', {'uri': null}, responseUndefined: true),
  ContractCase('document.setMarkers', {
    'uri': null,
    'owner': 'flutter',
    'markers': <Object?>[],
  }, responseUndefined: true),
  ContractCase('docs.open', {
    'text': 'x',
    'language': 'dart',
    'uri': 'file:///a.dart',
  }, responseValue: 'file:///a.dart'),
  ContractCase('docs.close', {
    'uri': 'file:///a.dart',
  }, responseUndefined: true),
  ContractCase('docs.list', {}, responseValue: ['file:///a.dart']),
  ContractCase('docs.activate', {
    'uri': 'file:///a.dart',
  }, responseUndefined: true),
  ContractCase('docs.activeUri', {}, responseValue: 'file:///a.dart'),
  ContractCase('editor.updateOptions', {
    'options': {'fontSize': 14},
  }, responseUndefined: true),
  ContractCase('editor.setTheme', {
    'theme': 'vs-dark',
  }, responseUndefined: true),
  ContractCase('editor.getTheme', {}, responseValue: 'vs-dark'),
  ContractCase('editor.defineTheme', {
    'id': 'my-theme',
    'data': {'base': 'vs-dark', 'inherit': true, 'rules': <Object?>[]},
  }, responseUndefined: true),
  ContractCase(
    'editor.getSelection',
    {},
    responseValue: {
      'startLineNumber': 1,
      'startColumn': 1,
      'endLineNumber': 2,
      'endColumn': 5,
    },
  ),
  ContractCase('editor.setSelection', {
    'range': {
      'startLineNumber': 1,
      'startColumn': 1,
      'endLineNumber': 2,
      'endColumn': 5,
    },
  }, responseUndefined: true),
  ContractCase(
    'editor.getCursor',
    {},
    responseValue: {'lineNumber': 3, 'column': 7},
  ),
  ContractCase('editor.setCursor', {
    'position': {'lineNumber': 3, 'column': 7},
  }, responseUndefined: true),
  ContractCase('editor.reveal', {
    'range': {
      'startLineNumber': 5,
      'startColumn': 1,
      'endLineNumber': 5,
      'endColumn': 1,
    },
    'center': true,
  }, responseValue: true),
  ContractCase('editor.scrollToEdge', {'edge': 'top'}, responseValue: true),
  ContractCase('editor.executeAction', {
    'actionId': 'editor.action.formatDocument',
    'args': null,
  }, responseUndefined: true),
  ContractCase(
    'editor.captureViewState',
    {},
    responseValue: {'cursorState': <Object?>[]},
  ),
  ContractCase('editor.restoreViewState', {
    'state': {'cursorState': <Object?>[]},
  }, responseUndefined: true),
  ContractCase('editor.layout', {}, responseUndefined: true),
  ContractCase(
    'decorations.delta',
    {'previousIds': <Object?>[], 'decorations': <Object?>[]},
    responseValue: ['dec-1'],
  ),
  ContractCase('completions.register', {
    'id': 'flutter_1',
    'languages': ['dart'],
    'triggerCharacters': ['.'],
  }, responseUndefined: true),
  ContractCase('completions.unregister', {
    'id': 'flutter_1',
  }, responseUndefined: true),
  ContractCase('completions.resolve', {
    'requestId': 'req-1',
    'payload': {'suggestions': <Object?>[]},
  }, responseUndefined: true),
  ContractCase('json.configureDiagnostics', {
    'options': {'validate': true},
  }, responseUndefined: true),
  ContractCase('lsp.connect', {
    'id': 'pyright',
    'transport': {'kind': 'websocket', 'url': 'ws://127.0.0.1:3000'},
  }, responseValue: true),
  ContractCase('lsp.disconnect', {'id': 'pyright'}, responseValue: true),
  ContractCase('lsp.disconnectAll', {}, responseValue: true),
  ContractCase('lsp.deliverServerMessage', {
    'id': 'pyright',
    'message': {'jsonrpc': '2.0', 'id': 1, 'result': null},
  }, responseValue: true),
  ContractCase(
    'lsp.sendRequest',
    {'id': 'pyright', 'method': 'workspace/symbol', 'params': null},
    responseValue: {'ok': true},
  ),
  ContractCase('lsp.sendNotification', {
    'id': 'pyright',
    'method': 'window/progress',
    'params': null,
  }, responseValue: true),
  ContractCase('lsp.listConnections', {}, responseValue: ['pyright']),
];

void main() {
  group('protocol v3 wire contract', () {
    test('dispatch payload golden per command', () async {
      for (final c in contractCases) {
        final webview = FakePlatformWebViewController();
        final protocol = MonacoProtocol(webView: webview);
        await webview.addJavaScriptChannel(
          'flutterChannel',
          protocol.handleChannelMessage,
        );
        webview.autoRespond = false;
        final future = protocol.invoke(c.method, c.params, timeout: null);
        future.ignore();

        expect(webview.dispatched, hasLength(1), reason: c.method);
        final goldenScript =
            'window.FlutterMonaco && window.FlutterMonaco.dispatch({ '
            '"id": "r1", '
            '"method": ${jsonEncode(c.method)}, '
            '"params": ${jsonEncode(c.params)} })';
        expect(webview.executed.single, goldenScript, reason: c.method);
        protocol.dispose();
      }
    });

    test('response envelope decodes to the expected value', () async {
      for (final c in contractCases) {
        final webview = FakePlatformWebViewController();
        final protocol = MonacoProtocol(webView: webview);
        await webview.addJavaScriptChannel(
          'flutterChannel',
          protocol.handleChannelMessage,
        );
        if (c.responseUndefined) {
          // Default fake behavior answers undefined-success.
        } else {
          webview.injectCommandSuccess(c.method, value: c.responseValue);
        }
        final result = await protocol.invoke(c.method, c.params);
        if (c.responseUndefined) {
          expect(identical(result, monacoJsUndefined), true, reason: c.method);
        } else {
          expect(result, c.responseValue, reason: c.method);
        }
        protocol.dispose();
      }
    });

    test('bridge JS registrations and contract cases cover each other', () {
      final registered = <String>{};
      final registerPattern = RegExp(
        r"""(?:FM|window\.FlutterMonaco)\.register\(\s*'([^']+)'""",
      );
      for (final name in bridgeFileNames) {
        for (final match in registerPattern.allMatches(bridgeSource(name))) {
          registered.add(match.group(1)!);
        }
      }
      final contract = contractCases.map((c) => c.method).toSet();

      expect(
        contract.length,
        contractCases.length,
        reason: 'duplicate contract fixtures',
      );
      expect(
        registered.difference(contract),
        isEmpty,
        reason: 'bridge registers commands without a contract fixture',
      );
      expect(
        contract.difference(registered),
        isEmpty,
        reason: 'contract fixture without a bridge registration',
      );
    });

    test('core.js protocol version matches the Dart constant', () {
      final core = bridgeSource('core.js');
      expect(core, contains('var PROTOCOL_VERSION = $kMonacoProtocolVersion;'));
    });
  });
}
