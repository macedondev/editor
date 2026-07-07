import 'dart:async';

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

Map<String, Object?> _completionRequestData({
  required String providerId,
  String requestId = 'req-1',
  String language = 'dart',
  int line = 1,
  int column = 2,
}) {
  return {
    'providerId': providerId,
    'requestId': requestId,
    'language': language,
    'position': {'lineNumber': line, 'column': column},
    'defaultRange': {
      'startLineNumber': line,
      'startColumn': 1,
      'endLineNumber': line,
      'endColumn': column,
    },
    'lineText': 'test line',
  };
}

/// Raw dispatch scripts that answer a completion request. The Dart response
/// rides the v3 wire as method `completions.resolve` with params
/// `{requestId, payload}`.
List<String> _resolveScripts(FakePlatformWebViewController webview) {
  return webview.scriptsContaining('"method": "completions.resolve"');
}

void main() {
  group('MonacoController completions', () {
    group('registration validation', () {
      test('empty languages list throws ArgumentError', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        expect(
          () => controller.registerCompletionSource(
            id: 'p1',
            languages: const [],
            provider: (_) async => const CompletionList(suggestions: []),
          ),
          throwsArgumentError,
        );
      });

      test('duplicate provider id throws ArgumentError', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async => const CompletionList(suggestions: []),
        );

        expect(
          () => controller.registerCompletionSource(
            id: 'p1',
            languages: const ['dart'],
            provider: (_) async => const CompletionList(suggestions: []),
          ),
          throwsArgumentError,
        );
      });

      test('null id generates unique id', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        final id1 = await controller.registerCompletionSource(
          languages: const ['dart'],
          provider: (_) async => const CompletionList(suggestions: []),
        );

        final id2 = await controller.registerCompletionSource(
          languages: const ['dart'],
          provider: (_) async => const CompletionList(suggestions: []),
        );

        expect(id1, isNot(equals(id2)));
        expect(id1, startsWith('flutter_'));
        expect(id2, startsWith('flutter_'));
      });
    });

    group('JS bridge calls', () {
      test('register dispatches completions.register with payload', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'myProvider',
          languages: const ['dart', 'typescript'],
          triggerCharacters: const ['.', '@'],
          provider: (_) async => const CompletionList(suggestions: []),
        );

        final call = webview.dispatched.singleWhere(
          (d) => d['method'] == 'completions.register',
        );
        final params = call['params']! as Map<String, Object?>;
        expect(params['id'], 'myProvider');
        expect(params['languages'], ['dart', 'typescript']);
        expect(params['triggerCharacters'], ['.', '@']);
      });

      test('unregister dispatches completions.unregister', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        final id = await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async => const CompletionList(suggestions: []),
        );

        await controller.unregisterCompletionSource(id);

        final calls = webview.dispatched
            .where((d) => d['method'] == 'completions.unregister')
            .toList();
        expect(calls, hasLength(1));
        final params = calls.single['params']! as Map<String, Object?>;
        expect(params['id'], 'p1');
      });
    });

    group('completion request handling', () {
      test('invokes provider and responds with suggestions', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        final requestCompleter = Completer<CompletionRequest>();

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (request) async {
            requestCompleter.complete(request);
            return const CompletionList(
              suggestions: [
                CompletionItem(
                  label: 'print',
                  kind: CompletionItemKind.functionType,
                  detail: 'Print to console',
                ),
                CompletionItem(
                  label: 'println',
                  kind: CompletionItemKind.functionType,
                ),
              ],
            );
          },
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();

        final request = await requestCompleter.future;
        expect(request.providerId, 'p1');
        expect(request.requestId, 'req-1');
        expect(request.language, 'dart');
        expect(request.position.line, 1);
        expect(request.position.column, 2);

        final completeCall = _resolveScripts(webview).first;
        expect(completeCall, contains('"req-1"'));
        expect(completeCall, contains('"print"'));
        expect(completeCall, contains('"println"'));
        expect(completeCall, contains('"Function"'));
      });

      test('receives trigger context', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        CompletionRequest? receivedRequest;

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          triggerCharacters: const ['.'],
          provider: (request) async {
            receivedRequest = request;
            return const CompletionList(suggestions: []);
          },
        );

        webview.emitEvent('completionRequest', {
          'providerId': 'p1',
          'requestId': 'req-2',
          'language': 'dart',
          'position': {'lineNumber': 5, 'column': 10},
          'defaultRange': {
            'startLineNumber': 5,
            'startColumn': 1,
            'endLineNumber': 5,
            'endColumn': 10,
          },
          'lineText': 'object.',
          'triggerKind': 2,
          'triggerCharacter': '.',
        });
        await pumpEventQueue();

        expect(receivedRequest, isNotNull);
        expect(receivedRequest!.lineText, 'object.');
        expect(receivedRequest!.triggerKind, 2);
        expect(receivedRequest!.triggerCharacter, '.');
      });

      test('unknown provider returns empty suggestions', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        // Register a provider but request from a different one
        await controller.registerCompletionSource(
          id: 'registered',
          languages: const ['dart'],
          provider: (_) async => const CompletionList(
            suggestions: [CompletionItem(label: 'should not appear')],
          ),
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'unknown'),
        );
        await pumpEventQueue();

        final completeCall = _resolveScripts(webview).first;
        expect(completeCall, contains('"suggestions":[]'));
        expect(completeCall, isNot(contains('"should not appear"')));
      });

      test('provider exception returns empty suggestions', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async {
            throw StateError('Provider error');
          },
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();

        final completeCall = _resolveScripts(webview).first;
        expect(completeCall, contains('"suggestions":[]'));
      });

      test('provider async timeout still sends response', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return const CompletionList(
              suggestions: [CompletionItem(label: 'delayed')],
            );
          },
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );

        // Wait for async completion
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await pumpEventQueue();

        webview.assertExecuted('"method": "completions.resolve"');
      });
    });

    group('completion item serialization', () {
      test('all CompletionItem fields serialized', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async => const CompletionList(
            suggestions: [
              CompletionItem(
                label: 'testItem',
                insertText: 'testItem()',
                kind: CompletionItemKind.method,
                detail: 'A test method',
                documentation: 'Detailed documentation',
                sortText: '00001',
                filterText: 'test',
                range: Range(
                  startLine: 1,
                  startColumn: 1,
                  endLine: 1,
                  endColumn: 5,
                ),
                commitCharacters: ['(', '.'],
                insertTextRules: {InsertTextRule.insertAsSnippet},
              ),
            ],
            isIncomplete: true,
          ),
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();

        final call = _resolveScripts(webview).first;
        expect(call, contains('"testItem"'));
        expect(call, contains('"testItem()"'));
        expect(call, contains('"Method"'));
        expect(call, contains('"A test method"'));
        expect(call, contains('"Detailed documentation"'));
        expect(call, contains('"00001"'));
        expect(call, contains('"test"'));
        expect(call, contains('"("'));
        expect(call, contains('"."'));
        expect(call, contains('"InsertAsSnippet"'));
        expect(call, contains('"isIncomplete":true'));
      });

      test('all CompletionItemKind values serialized correctly', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        final allKinds = CompletionItemKind.values;
        final suggestions = allKinds
            .map((k) => CompletionItem(label: k.name, kind: k))
            .toList();

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async => CompletionList(suggestions: suggestions),
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();

        final call = _resolveScripts(webview).first;
        for (final kind in allKinds) {
          expect(call, contains('"${kind.jsonValue}"'));
        }
      });
    });

    group('static completions', () {
      test('registerStaticCompletions returns items', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerStaticCompletions(
          id: 'static1',
          languages: const ['dart'],
          items: const [
            CompletionItem(label: 'static1'),
            CompletionItem(label: 'static2'),
          ],
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'static1'),
        );
        await pumpEventQueue();

        final call = _resolveScripts(webview).first;
        expect(call, contains('"static1"'));
        expect(call, contains('"static2"'));
      });

      test('registerStaticCompletions with isIncomplete', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerStaticCompletions(
          id: 'static1',
          languages: const ['dart'],
          items: const [CompletionItem(label: 'item')],
          isIncomplete: true,
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'static1'),
        );
        await pumpEventQueue();

        final call = _resolveScripts(webview).first;
        expect(call, contains('"isIncomplete":true'));
      });
    });

    group('multiple providers', () {
      test('multiple providers for same language', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        final calls = <String>[];

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async {
            calls.add('p1');
            return const CompletionList(
              suggestions: [CompletionItem(label: 'from_p1')],
            );
          },
        );

        await controller.registerCompletionSource(
          id: 'p2',
          languages: const ['dart'],
          provider: (_) async {
            calls.add('p2');
            return const CompletionList(
              suggestions: [CompletionItem(label: 'from_p2')],
            );
          },
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();
        expect(calls, ['p1']);

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p2', requestId: 'req-2'),
        );
        await pumpEventQueue();
        expect(calls, ['p1', 'p2']);
      });

      test('unregistered provider stops receiving requests', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        var callCount = 0;

        final id = await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async {
            callCount++;
            return const CompletionList(suggestions: []);
          },
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();
        expect(callCount, 1);

        await controller.unregisterCompletionSource(id);

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1', requestId: 'req-2'),
        );
        await pumpEventQueue();
        expect(callCount, 1); // Not incremented
      });
    });

    group('edge cases', () {
      test('handles concurrent requests', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);
        var completedCount = 0;

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            completedCount++;
            return CompletionList(
              suggestions: [CompletionItem(label: 'result_$completedCount')],
            );
          },
        );

        // Fire multiple requests quickly
        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1', requestId: 'req-2'),
        );
        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1', requestId: 'req-3'),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        await pumpEventQueue();

        expect(completedCount, 3);
        expect(_resolveScripts(webview), hasLength(3));
      });

      test('empty suggestions list handled', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async => const CompletionList(suggestions: []),
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();

        final call = _resolveScripts(webview).first;
        expect(call, contains('"suggestions":[]'));
      });

      test('completion item with null optional fields', () async {
        final webview = FakePlatformWebViewController();
        final controller = await _createController(webview);

        await controller.registerCompletionSource(
          id: 'p1',
          languages: const ['dart'],
          provider: (_) async => const CompletionList(
            suggestions: [CompletionItem(label: 'minimal')],
          ),
        );

        webview.emitEvent(
          'completionRequest',
          _completionRequestData(providerId: 'p1'),
        );
        await pumpEventQueue();

        final call = _resolveScripts(webview).first;
        expect(call, contains('"minimal"'));
        // Should not contain null fields
        expect(call, isNot(contains('null')));
      });
    });
  });
}
