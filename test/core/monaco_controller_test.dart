import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutter_monaco/src/platform/platform_webview.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_platform_webview_controller.dart';

class _TestBundle {
  _TestBundle(this.controller, this.webview);

  final MonacoController controller;
  final FakePlatformWebViewController webview;
}

Future<_TestBundle> _createBundle({bool ready = true}) async {
  final webview = FakePlatformWebViewController();
  final controller = await MonacoController.createForTesting(
    webViewController: webview,
    markReady: ready,
  );
  return _TestBundle(controller, webview);
}

/// All dispatched protocol calls whose dotted method equals [method].
List<Map<String, Object?>> _dispatchesOf(
  FakePlatformWebViewController webview,
  String method,
) {
  return webview.dispatched.where((d) => d['method'] == method).toList();
}

/// The params map of a parsed dispatch call.
Map<String, Object?> _paramsOf(Map<String, Object?> call) {
  return (call['params']! as Map).cast<String, Object?>();
}

void main() {
  group('MonacoController', () {
    group('initialization', () {
      test('createForTesting wires channel and marks ready', () async {
        final webview = FakePlatformWebViewController();
        final controller = await MonacoController.createForTesting(
          webViewController: webview,
          markReady: true,
        );
        expect(webview.hasChannel('flutterChannel'), true);
        expect(webview.initialized, true);
        expect(webview.jsEnabled, true);
        await expectLater(controller.whenReady, completes);
      });

      test('createForTesting with custom channel name', () async {
        final webview = FakePlatformWebViewController();
        await MonacoController.createForTesting(
          webViewController: webview,
          markReady: true,
          channelName: 'customChannel',
        );
        expect(webview.hasChannel('customChannel'), true);
      });

      test('completeReadyForTesting is idempotent', () async {
        final bundle = await _createBundle(ready: false);
        bundle.controller.completeReadyForTesting();
        bundle.controller.completeReadyForTesting(); // Should not throw
        await expectLater(bundle.controller.whenReady, completes);
      });

      test('isReady reflects ready state', () async {
        final bundle = await _createBundle(ready: false);
        expect(bundle.controller.isReady, false);

        bundle.controller.completeReadyForTesting();
        expect(bundle.controller.isReady, true);
      });
    });

    group('ready gating', () {
      test('ensureReady blocks operations until ready', () async {
        final bundle = await _createBundle(ready: false);
        final future = bundle.controller.updateOptions(
          const EditorOptions(fontSize: 18),
        );
        expect(bundle.webview.executed, isEmpty);
        bundle.controller.completeReadyForTesting();
        await future;
        expect(bundle.webview.executed.join('\n'), contains('updateOptions'));
      });

      test('execute helpers wait for ready on JS results', () async {
        final bundle = await _createBundle(ready: false);
        bundle.webview.injectCommandSuccess(
          'document.findMatches',
          value: <Map<String, dynamic>>[],
        );
        final future = bundle.controller.findMatches('x');
        expect(bundle.webview.executed, isEmpty);
        bundle.controller.completeReadyForTesting();
        await future;
        expect(
          _dispatchesOf(bundle.webview, 'document.findMatches'),
          isNotEmpty,
        );
      });

      test('multiple operations queue correctly', () async {
        final bundle = await _createBundle(ready: false);
        final futures = [
          bundle.controller.setTheme(MonacoTheme.vs),
          bundle.controller.setLanguage(MonacoLanguage.python),
          bundle.controller.focus(),
        ];

        expect(bundle.webview.executed, isEmpty);
        bundle.controller.completeReadyForTesting();
        await Future.wait(futures);

        final joined = bundle.webview.executed.join('\n');
        expect(joined.contains('setTheme'), true);
        expect(joined.contains('setLanguage'), true);
        expect(joined.contains('focus.force'), true);
      });

      test(
        'executeAction routes toolbar commands to monaco action ids',
        () async {
          final bundle = await _createBundle();

          const ids = [
            MonacoAction.foldAll,
            MonacoAction.unfoldAll,
            MonacoAction.commentLine,
            MonacoAction.indentLines,
            MonacoAction.outdentLines,
          ];
          for (final id in ids) {
            await bundle.controller.executeAction(id);
          }

          final joined = bundle.webview.executed.join('\n');
          for (final id in ids) {
            expect(joined.contains(id), true, reason: 'missing $id');
          }
        },
      );

      test(
        'command failure envelope throws MonacoJavaScriptException',
        () async {
          final bundle = await _createBundle();
          bundle.webview.injectCommandFailure(
            'executeAction',
            message: 'broken action',
          );

          await expectLater(
            () => bundle.controller.executeAction('whatever'),
            throwsA(
              isA<MonacoJavaScriptException>()
                  .having(
                    (e) => e.operation,
                    'operation',
                    'editor.executeAction',
                  )
                  .having((e) => e.message, 'message', 'broken action'),
            ),
          );
        },
      );
    });

    group('theme registration', () {
      test('defineTheme serializes MonacoThemeDefinition data', () async {
        final bundle = await _createBundle();
        const theme = MonacoThemeDefinition(
          id: 'app-dark',
          base: MonacoTheme.vsDark,
          rules: [MonacoThemeRule(token: 'comment', foreground: '6A9955')],
          colors: {'editor.background': '#101010'},
        );

        await bundle.controller.defineTheme(theme);

        final invocation = bundle.webview
            .scriptsContaining('editor.defineTheme')
            .single;
        expect(invocation, contains('"app-dark"'));
        expect(invocation, contains('"vs-dark"'));
        expect(invocation, contains('"6A9955"'));
        expect(invocation, contains('"editor.background"'));
      });

      test('defineThemeFromJson forwards raw data unchanged', () async {
        final bundle = await _createBundle();
        await bundle.controller.defineThemeFromJson('raw-id', const {
          'base': 'vs',
          'inherit': false,
          'rules': <Map<String, Object?>>[],
          'colors': {'editor.background': '#FFFFFF'},
        });

        final invocation = bundle.webview
            .scriptsContaining('editor.defineTheme')
            .single;
        expect(invocation, contains('"raw-id"'));
        expect(invocation, contains('"editor.background"'));
        expect(invocation, contains('"#FFFFFF"'));
      });

      test('setThemeById rejects empty ids', () async {
        final bundle = await _createBundle();
        expect(
          () => bundle.controller.setThemeById('   '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('defineThemeFromJson rejects empty ids', () async {
        final bundle = await _createBundle();
        expect(
          () => bundle.controller.defineThemeFromJson('', const {}),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('getThemeId returns value from bridge', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'editor.getTheme',
          value: 'company-dark',
        );
        expect(await bundle.controller.getThemeId(), 'company-dark');
      });

      test('getThemeId returns null when bridge call fails', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandFailure(
          'editor.getTheme',
          message: 'monaco.editor.getTheme is not a function',
        );
        expect(await bundle.controller.getThemeId(), isNull);
      });

      test(
        'getThemeId returns null when bridge reports empty string',
        () async {
          final bundle = await _createBundle();
          bundle.webview.injectCommandSuccess('editor.getTheme', value: '');
          expect(await bundle.controller.getThemeId(), isNull);
        },
      );

      test(
        'MonacoThemeDefinition JSON round-trip preserves rules and colors',
        () {
          const original = MonacoThemeDefinition(
            id: 'roundtrip',
            base: MonacoTheme.hcBlack,
            inherit: false,
            rules: [
              MonacoThemeRule(
                token: 'keyword',
                foreground: '569CD6',
                fontStyle: 'italic',
              ),
              MonacoThemeRule(token: 'string', foreground: 'CE9178'),
            ],
            colors: {
              'editor.background': '#1E1E1E',
              'editor.foreground': '#D4D4D4',
            },
          );

          final json = original.toJson();
          final restored = MonacoThemeDefinition.fromJson(json);

          expect(restored, equals(original));
        },
      );

      test(
        'MonacoThemeRule.fromJson accepts empty token as default selector',
        () {
          final rule = MonacoThemeRule.fromJson(const {
            'token': '',
            'foreground': 'D4D4D4',
          });
          expect(rule.token, isEmpty);
          expect(rule.foreground, 'D4D4D4');
        },
      );

      test('MonacoThemeDefinition.fromMonacoThemeData attaches the id', () {
        final restored = MonacoThemeDefinition.fromMonacoThemeData(
          'third-party-dark',
          const {
            'base': 'vs-dark',
            'inherit': true,
            'rules': [
              {'token': 'comment', 'foreground': '6A9955'},
            ],
            'colors': {'editor.background': '#1E1E1E'},
          },
        );

        expect(restored.id, 'third-party-dark');
        expect(restored.base, MonacoTheme.vsDark);
        expect(restored.rules.single.token, 'comment');
        expect(restored.colors['editor.background'], '#1E1E1E');
      });

      test('EditorOptions.effectiveThemeId prefers themeId override', () {
        const builtIn = EditorOptions(
          theme: MonacoTheme.vs,
          themeId: 'custom-dark',
        );
        expect(builtIn.effectiveThemeId, 'custom-dark');

        const fallback = EditorOptions(theme: MonacoTheme.hcLight);
        expect(fallback.effectiveThemeId, MonacoTheme.hcLight.id);
      });

      test('EditorOptions.fromJson routes custom theme ids to themeId', () {
        final custom = EditorOptions.fromJson(const {'theme': 'app-dark'});
        expect(custom.themeId, 'app-dark');
        // Built-in theme stays at its default since the custom id is not a
        // recognized MonacoTheme.
        expect(custom.theme, MonacoTheme.vsDark);

        final builtIn = EditorOptions.fromJson(const {'theme': 'vs'});
        expect(builtIn.themeId, isNull);
        expect(builtIn.theme, MonacoTheme.vs);
      });

      test(
        'EditorOptions.fromJson preserves built-in fallback with themeId',
        () {
          final options = EditorOptions.fromJson(const {
            'theme': 'hc-light',
            'themeId': 'app-dark',
          });

          expect(options.theme, MonacoTheme.hcLight);
          expect(options.themeId, 'app-dark');
          expect(options.effectiveThemeId, 'app-dark');
        },
      );
    });

    group('interaction', () {
      test('isInteractionEnabled defaults to true', () async {
        final bundle = await _createBundle(ready: false);
        expect(bundle.controller.isInteractionEnabled, true);
      });

      test(
        'setInteractionEnabled updates state and webview immediately',
        () async {
          final bundle = await _createBundle(ready: false);

          await bundle.controller.setInteractionEnabled(false);

          expect(bundle.controller.isInteractionEnabled, false);
          expect(bundle.webview.interactionEnabled, false);
          expect(
            bundle.webview.executed.any((s) => s == 'SET_INTERACTION:false'),
            true,
          );
        },
      );
    });

    group('pre-ready commands', () {
      test('setValue calls wait for readiness and apply in order', () async {
        final bundle = await _createBundle(ready: false);
        final first = bundle.controller.setValue('A');
        final second = bundle.controller.setValue('B');
        expect(_dispatchesOf(bundle.webview, 'document.setText'), isEmpty);

        bundle.controller.completeReadyForTesting();
        await Future.wait([first, second]);

        // FIFO after ready: both dispatch, the newest write wins.
        final invocations = _dispatchesOf(bundle.webview, 'document.setText');
        expect(invocations.length, 2);
        expect(_paramsOf(invocations.first)['text'], 'A');
        expect(_paramsOf(invocations.last)['text'], 'B');
      });

      test('setLanguage calls wait for readiness and apply in order', () async {
        final bundle = await _createBundle(ready: false);
        final first = bundle.controller.setLanguage(MonacoLanguage.dart);
        final second = bundle.controller.setLanguage(MonacoLanguage.python);
        expect(_dispatchesOf(bundle.webview, 'document.setLanguage'), isEmpty);

        bundle.controller.completeReadyForTesting();
        await Future.wait([first, second]);

        final invocations = _dispatchesOf(
          bundle.webview,
          'document.setLanguage',
        );
        expect(invocations.length, 2);
        expect(_paramsOf(invocations.first)['language'], 'dart');
        expect(_paramsOf(invocations.last)['language'], 'python');
      });

      test('setValue after ready executes immediately', () async {
        final bundle = await _createBundle();
        await bundle.controller.setValue('immediate');
        final invocation = _dispatchesOf(
          bundle.webview,
          'document.setText',
        ).single;
        expect(_paramsOf(invocation)['text'], 'immediate');
      });
    });

    group('getValue', () {
      test('does not JSON-decode content', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'document.getText',
          value: '{"a":1}',
        );
        final value = await bundle.controller.getValue();
        expect(value, '{"a":1}');
      });

      test('returns defaultValue on error', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandFailure(
          'document.getText',
          message: 'boom',
        );
        final value = await bundle.controller.getValue(
          defaultValue: 'fallback',
        );
        expect(value, 'fallback');
      });

      test('handles null result', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.getText', value: null);
        final value = await bundle.controller.getValue(defaultValue: 'default');
        expect(value, 'default');
      });

      test('handles unicode content', () async {
        final bundle = await _createBundle();
        const unicode = 'مرحبا 👋🏽 é 🇪🇬';
        bundle.webview.injectCommandSuccess('document.getText', value: unicode);
        final value = await bundle.controller.getValue();
        expect(value, unicode);
      });
    });

    group('selection operations', () {
      test('getSelection parses the response map', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'editor.getSelection',
          value: {
            'startLineNumber': 1,
            'startColumn': 2,
            'endLineNumber': 3,
            'endColumn': 4,
          },
        );
        final selection = await bundle.controller.getSelection();
        expect(selection, isNotNull);
        expect(selection!.startLine, 1);
        expect(selection.startColumn, 2);
        expect(selection.endLine, 3);
        expect(selection.endColumn, 4);
      });

      test('getSelection returns null on error', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOn((s) => s.contains('getSelection'));
        final selection = await bundle.controller.getSelection();
        expect(selection, isNull);
      });

      test('setSelection generates correct payload', () async {
        final bundle = await _createBundle();
        const range = Range(
          startLine: 1,
          startColumn: 1,
          endLine: 2,
          endColumn: 5,
        );
        await bundle.controller.setSelection(range);
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('setSelection'));
        expect(joined, contains('startLineNumber'));
      });
    });

    group('navigation', () {
      test(
        'revealLine dispatches a line range (clamping is JS-side)',
        () async {
          final bundle = await _createBundle();
          await bundle.controller.revealLine(5);

          final call = _dispatchesOf(bundle.webview, 'editor.reveal').single;
          final params = _paramsOf(call);
          expect(params['center'], false);
          final range = (params['range']! as Map).cast<String, Object?>();
          expect(range['startLineNumber'], 5);
          expect(range['endLineNumber'], 5);
        },
      );

      test('revealLine with center option', () async {
        final bundle = await _createBundle();
        await bundle.controller.revealLine(5, center: true);

        final call = _dispatchesOf(bundle.webview, 'editor.reveal').single;
        expect(_paramsOf(call)['center'], true);
      });

      test('revealRange generates correct payload', () async {
        final bundle = await _createBundle();
        const range = Range(
          startLine: 1,
          startColumn: 1,
          endLine: 5,
          endColumn: 10,
        );
        await bundle.controller.revealRange(range, center: true);

        final call = _dispatchesOf(bundle.webview, 'editor.reveal').single;
        final params = _paramsOf(call);
        expect(params['center'], true);
        final sent = (params['range']! as Map).cast<String, Object?>();
        expect(sent['startLineNumber'], 1);
        expect(sent['endLineNumber'], 5);
        expect(sent['endColumn'], 10);
      });

      test('revealLines creates range and dispatches editor.reveal', () async {
        final bundle = await _createBundle();
        await bundle.controller.revealLines(2, 5);

        final call = _dispatchesOf(bundle.webview, 'editor.reveal').single;
        final range = (_paramsOf(call)['range']! as Map)
            .cast<String, Object?>();
        expect(range['startLineNumber'], 2);
        expect(range['endLineNumber'], 5);
      });

      test('revealPosition creates collapsed range', () async {
        final bundle = await _createBundle();
        const pos = Position(line: 3, column: 7);
        await bundle.controller.revealPosition(pos);

        final call = _dispatchesOf(bundle.webview, 'editor.reveal').single;
        final range = (_paramsOf(call)['range']! as Map)
            .cast<String, Object?>();
        expect(range['startLineNumber'], 3);
        expect(range['startColumn'], 7);
        expect(range['endLineNumber'], 3);
        expect(range['endColumn'], 7);
      });
    });

    group('actions', () {
      test('executeAction forwards args to JS', () async {
        final bundle = await _createBundle();
        await bundle.controller.executeAction('myAction', {'foo': 'bar'});

        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('executeAction'));
        expect(joined, contains('"foo":"bar"'));
      });
    });

    group('line operations', () {
      test('getLineCount returns valid count', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.lineCount', value: 42);
        final count = await bundle.controller.getLineCount();
        expect(count, 42);
      });

      test('getLineCount returns default on error', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandFailure(
          'document.lineCount',
          message: 'boom',
        );
        final count = await bundle.controller.getLineCount(defaultValue: 0);
        expect(count, 0);
      });

      test('getLineContent validates bounds - below', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.lineCount', value: 3);
        final value = await bundle.controller.getLineContent(
          0,
          defaultValue: 'x',
        );
        expect(value, 'x');
        expect(_dispatchesOf(bundle.webview, 'document.getLines'), isEmpty);
      });

      test('getLineContent validates bounds - above', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.lineCount', value: 3);
        final value = await bundle.controller.getLineContent(
          10,
          defaultValue: 'y',
        );
        expect(value, 'y');
      });

      test('getLineContent returns content for valid line', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.lineCount', value: 5);
        bundle.webview.injectCommandSuccess(
          'document.getLines',
          value: ['line 3'],
        );
        final value = await bundle.controller.getLineContent(3);
        expect(value, 'line 3');
      });

      test('getLinesContent returns values per line', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.lineCount', value: 3);
        bundle.webview.injectCommandSuccess('document.getLines', value: ['a']);
        bundle.webview.injectCommandSuccess('document.getLines', value: ['b']);
        bundle.webview.injectCommandSuccess('document.getLines', value: ['c']);

        final lines = await bundle.controller.getLinesContent([1, 2, 3]);
        expect(lines, ['a', 'b', 'c']);
      });
    });

    group('edit operations', () {
      test('applyEdits skips empty list', () async {
        final bundle = await _createBundle();
        await bundle.controller.applyEdits([]);
        expect(
          bundle.webview.executed.any((s) => s.contains('applyEdits')),
          false,
        );
      });

      test('applyEdits generates expected payload', () async {
        final bundle = await _createBundle();
        final edits = [
          EditOperation.insert(
            position: const Position(line: 1, column: 1),
            text: 'hi',
            forceMoveMarkers: true,
          ),
          EditOperation.delete(
            range: const Range(
              startLine: 2,
              startColumn: 1,
              endLine: 2,
              endColumn: 5,
            ),
          ),
        ];
        await bundle.controller.applyEdits(edits);

        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('applyEdits'));
        expect(joined, contains('"text":"hi"'));
        expect(joined, contains('"forceMoveMarkers":true'));
      });

      test('insertText creates insert operation', () async {
        final bundle = await _createBundle();
        await bundle.controller.insertText(
          const Position(line: 1, column: 1),
          'inserted',
        );
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('applyEdits'));
        expect(joined, contains('"inserted"'));
      });

      test('deleteRange creates delete operation', () async {
        final bundle = await _createBundle();
        await bundle.controller.deleteRange(
          const Range(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5),
        );
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('applyEdits'));
        expect(joined, contains('"text":""'));
      });

      test('replaceRange creates replace operation', () async {
        final bundle = await _createBundle();
        await bundle.controller.replaceRange(
          const Range(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5),
          'replacement',
        );
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('applyEdits'));
        expect(joined, contains('"replacement"'));
      });

      test('deleteLine creates line range', () async {
        final bundle = await _createBundle();
        await bundle.controller.deleteLine(3);
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('applyEdits'));
        expect(joined, contains('"startLineNumber":3'));
      });
    });

    group('decorations', () {
      test('setDecorations tracks ids across calls', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'decorations.delta',
          value: ['a', 'b'],
        );
        bundle.webview.injectCommandSuccess('decorations.delta', value: ['c']);

        final first = await bundle.controller.setDecorations([
          DecorationOptions.inlineClass(
            range: const Range(
              startLine: 1,
              startColumn: 1,
              endLine: 1,
              endColumn: 2,
            ),
            className: 'x',
          ),
        ]);
        expect(first, ['a', 'b']);

        final second = await bundle.controller.setDecorations(const []);
        expect(second, ['c']);

        // Verify the old IDs were passed in the second call
        expect(bundle.webview.executed.join('\n'), contains('["a","b"]'));
      });

      test('setDecorations throws on malformed bridge result', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('decorations.delta', value: ['a']);
        bundle.webview.injectCommandSuccess(
          'decorations.delta',
          value: 'not-a-list',
        );
        bundle.webview.injectCommandSuccess('decorations.delta', value: ['b']);

        final first = await bundle.controller.setDecorations([
          DecorationOptions.inlineClass(
            range: const Range(
              startLine: 1,
              startColumn: 1,
              endLine: 1,
              endColumn: 2,
            ),
            className: 'x',
          ),
        ]);
        expect(first, ['a']);

        await expectLater(
          () => bundle.controller.setDecorations(const []),
          throwsA(
            isA<MonacoJavaScriptException>().having(
              (e) => e.operation,
              'operation',
              'decorations.delta',
            ),
          ),
        );

        await bundle.controller.setDecorations(const []);
        expect(bundle.webview.executed.join('\n'), contains('["a"]'));
      });

      test('addInlineDecorations creates correct options', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('decorations.delta', value: ['d1']);

        final ids = await bundle.controller.addInlineDecorations(
          [const Range(startLine: 1, startColumn: 1, endLine: 1, endColumn: 5)],
          'highlight',
          hoverMessage: 'hover text',
        );
        expect(ids, ['d1']);
        expect(bundle.webview.executed.join('\n'), contains('inlineClassName'));
      });

      test('addLineDecorations creates whole line decorations', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'decorations.delta',
          value: ['l1', 'l2'],
        );

        final ids = await bundle.controller.addLineDecorations([
          1,
          2,
        ], 'line-highlight');
        expect(ids, ['l1', 'l2']);
        expect(bundle.webview.executed.join('\n'), contains('isWholeLine'));
      });

      test('clearDecorations passes empty array', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'decorations.delta',
          value: <String>[],
        );

        await bundle.controller.clearDecorations();
        expect(
          bundle.webview.executed.join('\n'),
          contains('decorations.delta'),
        );
      });
    });

    group('markers', () {
      test('setMarkers uses owner and severity values', () async {
        final bundle = await _createBundle();
        await bundle.controller.setMarkers([
          MarkerData.error(
            range: const Range(
              startLine: 1,
              startColumn: 1,
              endLine: 1,
              endColumn: 10,
            ),
            message: 'Error message',
          ),
        ], owner: 'flutter-errors');

        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('document.setMarkers'));
        expect(joined, contains('flutter-errors'));
        expect(joined, contains('"severity":8')); // Error severity
      });

      test('setErrorMarkers uses error owner', () async {
        final bundle = await _createBundle();
        await bundle.controller.setErrorMarkers([
          MarkerData.error(
            range: const Range(
              startLine: 1,
              startColumn: 1,
              endLine: 1,
              endColumn: 5,
            ),
            message: 'err',
          ),
        ]);
        expect(bundle.webview.executed.join('\n'), contains('flutter-errors'));
      });

      test('setWarningMarkers uses warning owner', () async {
        final bundle = await _createBundle();
        await bundle.controller.setWarningMarkers([
          MarkerData.warning(
            range: const Range(
              startLine: 1,
              startColumn: 1,
              endLine: 1,
              endColumn: 5,
            ),
            message: 'warn',
          ),
        ]);
        expect(
          bundle.webview.executed.join('\n'),
          contains('flutter-warnings'),
        );
      });

      test('clearAllMarkers clears all known owners', () async {
        final bundle = await _createBundle();
        await bundle.controller.clearAllMarkers();

        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('"flutter"'));
        expect(joined, contains('"flutter-errors"'));
        expect(joined, contains('"flutter-warnings"'));
      });
    });

    group('find and replace', () {
      test('findMatches returns FindMatch list', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'document.findMatches',
          value: [
            {
              'match': 'abc',
              'range': {
                'startLineNumber': 1,
                'startColumn': 1,
                'endLineNumber': 1,
                'endColumn': 4,
              },
            },
            {
              'match': 'abc',
              'range': {
                'startLineNumber': 2,
                'startColumn': 5,
                'endLineNumber': 2,
                'endColumn': 8,
              },
            },
          ],
        );

        final matches = await bundle.controller.findMatches('abc');
        expect(matches.length, 2);
        expect(matches[0].match, 'abc');
        expect(matches[0].range.startLine, 1);
        expect(matches[1].range.startLine, 2);
      });

      test('findMatches with options', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'document.findMatches',
          value: <Map<String, dynamic>>[],
        );

        await bundle.controller.findMatches(
          'test',
          options: FindOptions.caseSensitive(wholeWord: true),
          limit: 50,
        );

        final call = _dispatchesOf(
          bundle.webview,
          'document.findMatches',
        ).single;
        final params = _paramsOf(call);
        expect(params['query'], 'test');
        expect(params['matchCase'], true);
        expect(params['wholeWord'], true);
        expect(params['limit'], 50);
      });

      test('findMatches returns empty list on error', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOn((s) => s.contains('findMatches'));
        final matches = await bundle.controller.findMatches('test');
        expect(matches, isEmpty);
      });

      test('replaceMatches returns count', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'document.replaceMatches',
          value: 5,
        );

        final count = await bundle.controller.replaceMatches('old', 'new');
        expect(count, 5);
      });

      test('replaceMatches returns default on error', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOn((s) => s.contains('replaceMatches'));
        final count = await bundle.controller.replaceMatches(
          'a',
          'b',
          defaultCount: 0,
        );
        expect(count, 0);
      });
    });

    group('view state', () {
      test('saveViewState returns state map', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'editor.captureViewState',
          value: {
            'cursorState': [
              {'inSelectionMode': false},
            ],
            'scrollTop': 100,
          },
        );

        final state = await bundle.controller.saveViewState();
        expect(state.isNotEmpty, true);
        expect(state['scrollTop'], 100);
      });

      test('saveViewState returns empty map on error', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOn((s) => s.contains('captureViewState'));
        final state = await bundle.controller.saveViewState();
        expect(state, isEmpty);
      });

      test('restoreViewState skips empty state', () async {
        final bundle = await _createBundle();
        final before = bundle.webview.executed.length;
        await bundle.controller.restoreViewState({});
        expect(bundle.webview.executed.length, before);
      });

      test('restoreViewState passes state to JS', () async {
        final bundle = await _createBundle();
        await bundle.controller.restoreViewState({'scrollTop': 50});
        expect(
          bundle.webview.executed.join('\n'),
          contains('restoreViewState'),
        );
      });
    });

    group('multi-model', () {
      test('createModel returns URI', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'docs.open',
          value: 'file:///model1',
        );

        final uri = await bundle.controller.createModel('content');
        expect(uri.toString(), 'file:///model1');
      });

      test('createModel uses defaultUri on undefined result', () async {
        final bundle = await _createBundle();
        // Default auto-response is an undefined-success envelope.

        final fallback = Uri.parse('file:///fallback');
        final uri = await bundle.controller.createModel(
          'content',
          defaultUri: fallback,
        );
        expect(uri, fallback);
      });

      test('setModel calls JS with URI', () async {
        final bundle = await _createBundle();
        await bundle.controller.setModel(Uri.parse('file:///test'));
        final call = _dispatchesOf(bundle.webview, 'docs.activate').single;
        expect(_paramsOf(call)['uri'], 'file:///test');
      });

      test('disposeModel calls JS with URI', () async {
        final bundle = await _createBundle();
        await bundle.controller.disposeModel(Uri.parse('file:///test'));
        final call = _dispatchesOf(bundle.webview, 'docs.close').single;
        expect(_paramsOf(call)['uri'], 'file:///test');
      });

      test('listModels returns URI list', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'docs.list',
          value: ['file:///m1', 'file:///m2', 'invalid'],
        );

        final list = await bundle.controller.listModels();
        expect(list.length, 3);
        expect(list[0].toString(), 'file:///m1');
      });
    });

    group('dirty tracking and cursor', () {
      test('hasUnsavedChanges returns boolean', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('document.isDirty', value: true);
        final dirty = await bundle.controller.hasUnsavedChanges();
        expect(dirty, true);
      });

      test('markSaved calls JS', () async {
        final bundle = await _createBundle();
        await bundle.controller.markSaved();
        expect(bundle.webview.executed.join('\n'), contains('markSaved'));
      });

      test('getCursorPosition parses the response map', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'editor.getCursor',
          value: {'lineNumber': 5, 'column': 10},
        );

        final pos = await bundle.controller.getCursorPosition();
        expect(pos, isNotNull);
        expect(pos!.line, 5);
        expect(pos.column, 10);
      });

      test('setCursorPosition calls JS with coordinates', () async {
        final bundle = await _createBundle();
        await bundle.controller.setCursorPosition(
          const Position(line: 3, column: 7),
        );
        final call = _dispatchesOf(bundle.webview, 'editor.setCursor').single;
        final position = (_paramsOf(call)['position']! as Map)
            .cast<String, Object?>();
        expect(position['lineNumber'], 3);
        expect(position['column'], 7);
      });

      test('setCursorPositionZeroBased converts to 1-based', () async {
        final bundle = await _createBundle();
        await bundle.controller.setCursorPositionZeroBased(0, 0);
        final call = _dispatchesOf(bundle.webview, 'editor.setCursor').single;
        final position = (_paramsOf(call)['position']! as Map)
            .cast<String, Object?>();
        expect(position['lineNumber'], 1);
        expect(position['column'], 1);
      });

      test('getWordAtPosition returns word', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess(
          'document.getWordAt',
          value: 'hello',
        );
        final word = await bundle.controller.getWordAtPosition(
          const Position(line: 1, column: 1),
        );
        expect(word, 'hello');
      });
    });

    group('action helpers', () {
      test('format calls formatDocument action', () async {
        final bundle = await _createBundle();
        await bundle.controller.format();
        expect(bundle.webview.executed.join('\n'), contains('formatDocument'));
      });

      test('find calls find action', () async {
        final bundle = await _createBundle();
        await bundle.controller.find();
        expect(bundle.webview.executed.join('\n'), contains('actions.find'));
      });

      test('replace calls startFindReplaceAction', () async {
        final bundle = await _createBundle();
        await bundle.controller.replace();
        expect(
          bundle.webview.executed.join('\n'),
          contains('startFindReplaceAction'),
        );
      });

      test('toggleWordWrap calls action', () async {
        final bundle = await _createBundle();
        await bundle.controller.toggleWordWrap();
        expect(bundle.webview.executed.join('\n'), contains('toggleWordWrap'));
      });

      test('undo/redo call correct actions', () async {
        final bundle = await _createBundle();
        await bundle.controller.undo();
        await bundle.controller.redo();
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('"undo"'));
        expect(joined, contains('"redo"'));
      });

      test('clipboard actions call correct IDs', () async {
        final bundle = await _createBundle();
        await bundle.controller.cut();
        await bundle.controller.copy();
        await bundle.controller.paste();
        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('clipboardCutAction'));
        expect(joined, contains('clipboardCopyAction'));
        expect(joined, contains('clipboardPasteAction'));
      });
    });

    group('focus and scroll', () {
      test('focus dispatches focus.force', () async {
        final bundle = await _createBundle();
        await bundle.controller.focus();
        expect(bundle.webview.executed.join('\n'), contains('focus.force'));
      });

      test('ensureEditorFocus retries multiple times on desktop', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final bundle = await _createBundle();
          await bundle.controller.ensureEditorFocus(
            attempts: 3,
            interval: Duration.zero,
          );
          expect(_dispatchesOf(bundle.webview, 'focus.force').length, 3);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      test('macOS user intent falls back to input-focus replay when the '
          'native handoff is unavailable', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final bundle = await _createBundle();
          // Fake default: NativeFocusResult.unsupported (no native plugin
          // registered, as in headless embeddings). The replay fallback
          // must kick in to recover stale WKWebView input readiness.
          await bundle.controller.ensureEditorFocus(
            attempts: 1,
            interval: Duration.zero,
            intent: MonacoFocusIntent.user,
          );
          final calls = _dispatchesOf(bundle.webview, 'focus.force');
          expect(calls, hasLength(1));
          expect(_paramsOf(calls.single)['replayInputFocus'], true);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      test(
        'macOS user intent skips the replay when the native handoff succeeds',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            for (final handoff in [
              NativeFocusResult.granted,
              NativeFocusResult.alreadyOwned,
            ]) {
              final bundle = await _createBundle();
              bundle.webview.nativeFocusResult = handoff;
              await bundle.controller.ensureEditorFocus(
                attempts: 1,
                interval: Duration.zero,
                intent: MonacoFocusIntent.user,
              );
              expect(bundle.webview.executed, contains('REQUEST_NATIVE_FOCUS'));
              final calls = _dispatchesOf(bundle.webview, 'focus.force');
              expect(calls, isNotEmpty);
              // First responder is real, so the caret-blinking blur/refocus
              // replay must not run for either handoff outcome.
              for (final call in calls) {
                expect(_paramsOf(call)['replayInputFocus'], false);
              }
            }
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      test(
        'macOS fallback replay runs at most once across retry attempts',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            final bundle = await _createBundle();
            bundle.webview.nativeFocusResult = NativeFocusResult.failed;
            await bundle.controller.ensureEditorFocus(
              attempts: 3,
              interval: Duration.zero,
              intent: MonacoFocusIntent.user,
            );
            final calls = _dispatchesOf(bundle.webview, 'focus.force');
            final replays = calls
                .where((c) => _paramsOf(c)['replayInputFocus'] == true)
                .length;
            final plainFocuses = calls
                .where((c) => _paramsOf(c)['replayInputFocus'] == false)
                .length;
            // One recovery replay, then idempotent settle retries: repeating
            // the blur/refocus cycle would multiply the caret blink.
            expect(replays, 1);
            expect(plainFocuses, 2);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      test('hasNativeInputFocus delegates to the platform layer', () async {
        final bundle = await _createBundle();
        bundle.webview.nativeInputFocus = true;
        expect(await bundle.controller.hasNativeInputFocus(), isTrue);
        bundle.webview.nativeInputFocus = null;
        expect(await bundle.controller.hasNativeInputFocus(), isNull);
        expect(bundle.webview.executed, contains('HAS_NATIVE_INPUT_FOCUS'));
      });

      test('releaseNativeInputFocus delegates to the platform layer', () async {
        final bundle = await _createBundle();
        await bundle.controller.releaseNativeInputFocus();
        expect(bundle.webview.executed, contains('RELEASE_NATIVE_FOCUS'));
      });

      test('maintenance focus intent keeps default idempotent focus', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final bundle = await _createBundle();
          await bundle.controller.ensureEditorFocus(
            attempts: 1,
            interval: Duration.zero,
          );
          final calls = _dispatchesOf(bundle.webview, 'focus.force');
          expect(calls, isNotEmpty);
          for (final call in calls) {
            expect(_paramsOf(call)['replayInputFocus'], false);
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      test('ensureEditorFocus uses one attempt on mobile', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final bundle = await _createBundle();
          await bundle.controller.ensureEditorFocus(
            attempts: 3,
            interval: Duration.zero,
          );
          expect(_dispatchesOf(bundle.webview, 'focus.force').length, 1);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      testWidgets(
        'focus and ensureEditorFocus do not steal the keyboard from a '
        'focused Flutter text input',
        (tester) async {
          final bundle = await _createBundle();
          final textInputCalls = <MethodCall>[];
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.textInput,
            (call) async {
              textInputCalls.add(call);
              return null;
            },
          );
          addTearDown(() {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.textInput,
              null,
            );
          });
          final focusNode = FocusNode();
          addTearDown(focusNode.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TextField(focusNode: focusNode, autofocus: true),
              ),
            ),
          );
          await tester.pump();
          expect(focusNode.hasPrimaryFocus, isTrue);
          textInputCalls.clear();

          // While the TextField owns the keyboard, both helpers must no-op:
          // on Windows requestNativeFocus would move real Win32 focus to the
          // WebView and typing would land in the editor instead of the field.
          await tester.runAsync(() => bundle.controller.focus());
          await tester.runAsync(
            () => bundle.controller.ensureEditorFocus(
              attempts: 2,
              interval: Duration.zero,
            ),
          );
          expect(
            bundle.webview.executed.where((s) => s.contains('focus.force')),
            isEmpty,
          );
          expect(
            bundle.webview.executed,
            isNot(contains('REQUEST_NATIVE_FOCUS')),
          );
          expect(
            textInputCalls.map((call) => call.method),
            isNot(contains('TextInput.hide')),
          );

          // Once the text input releases the keyboard, focusing works again.
          focusNode.unfocus();
          await tester.pump();
          await tester.runAsync(() => bundle.controller.focus());
          expect(bundle.webview.executed, contains('REQUEST_NATIVE_FOCUS'));
          expect(bundle.webview.executed.join('\n'), contains('focus.force'));
        },
      );

      testWidgets(
        'user focus intent releases Flutter text input before editor focus',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final textInputCalls = <MethodCall>[];
          FakePlatformWebViewController? activeWebview;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.textInput,
            (call) async {
              textInputCalls.add(call);
              activeWebview?.executed.add('TEXT_INPUT:${call.method}');
              return null;
            },
          );
          addTearDown(() {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.textInput,
              null,
            );
            debugDefaultTargetPlatformOverride = null;
          });

          try {
            final bundle = await _createBundle();
            activeWebview = bundle.webview;
            final focusNode = FocusNode();
            addTearDown(focusNode.dispose);

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: TextField(focusNode: focusNode, autofocus: true),
                ),
              ),
            );
            await tester.pump();
            expect(focusNode.hasPrimaryFocus, isTrue);

            bundle.webview.executed.clear();
            textInputCalls.clear();

            await tester.runAsync(
              () => bundle.controller.ensureEditorFocus(
                attempts: 1,
                interval: Duration.zero,
                intent: MonacoFocusIntent.user,
              ),
            );
            await tester.pump();

            expect(focusNode.hasPrimaryFocus, isFalse);
            expect(
              textInputCalls.map((call) => call.method),
              contains('TextInput.hide'),
            );

            final calls = bundle.webview.executed;
            expect(calls, contains('TEXT_INPUT:TextInput.hide'));
            expect(calls, contains('REQUEST_NATIVE_FOCUS'));
            expect(calls.join('\n'), contains('focus.force'));

            final textInputIndex = calls.indexOf('TEXT_INPUT:TextInput.hide');
            final nativeFocusIndex = calls.indexOf('REQUEST_NATIVE_FOCUS');
            final forceFocusIndex = calls.indexWhere(
              (call) => call.contains('focus.force'),
            );
            expect(textInputIndex, isNonNegative);
            expect(nativeFocusIndex, isNonNegative);
            expect(forceFocusIndex, isNonNegative);
            expect(textInputIndex, lessThan(nativeFocusIndex));
            expect(nativeFocusIndex, lessThan(forceFocusIndex));
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );

      test('layout calls layout', () async {
        final bundle = await _createBundle();
        await bundle.controller.layout();
        expect(bundle.webview.executed.join('\n'), contains('layout'));
      });

      test('scrollToTop scrolls to the top edge', () async {
        final bundle = await _createBundle();
        await bundle.controller.scrollToTop();
        final call = _dispatchesOf(
          bundle.webview,
          'editor.scrollToEdge',
        ).single;
        expect(_paramsOf(call)['edge'], 'top');
      });

      test('scrollToBottom scrolls to the bottom edge', () async {
        final bundle = await _createBundle();
        await bundle.controller.scrollToBottom();
        final call = _dispatchesOf(
          bundle.webview,
          'editor.scrollToEdge',
        ).single;
        expect(_paramsOf(call)['edge'], 'bottom');
      });
    });

    group('batch operations', () {
      test('executeBatch runs operations sequentially', () async {
        final bundle = await _createBundle();
        final order = <int>[];

        await bundle.controller.executeBatch([
          () async {
            order.add(1);
            await bundle.controller.focus();
          },
          () async {
            order.add(2);
            await bundle.controller.layout();
          },
        ]);

        expect(order, [1, 2]);
      });

      test('getEditorState aggregates state', () async {
        final bundle = await _createBundle();

        // Set up responses for the protocol-envelope reads.
        bundle.webview.injectCommandSuccess(
          'document.getText',
          value: 'content',
        );
        bundle.webview.injectCommandSuccess('document.lineCount', value: 5);
        bundle.webview.injectCommandSuccess(
          'editor.getSelection',
          value: {
            'startLineNumber': 1,
            'startColumn': 1,
            'endLineNumber': 1,
            'endColumn': 5,
          },
        );
        bundle.webview.injectCommandSuccess(
          'editor.getCursor',
          value: {'lineNumber': 1, 'column': 3},
        );
        bundle.webview.injectCommandSuccess('document.isDirty', value: false);

        final state = await bundle.controller.getEditorState();

        expect(state.content, 'content');
        expect(state.selection?.endColumn, 5);
        expect(state.cursorPosition?.column, 3);
        expect(state.lineCount, 5);
        expect(state.hasUnsavedChanges, false);
      });
    });

    group('event streams', () {
      test('onContentChanged delivers flush flag', () async {
        final bundle = await _createBundle();
        final events = <bool>[];
        final sub = bundle.controller.onContentChanged.listen(events.add);

        bundle.webview.emitEvent('contentChanged', {'isFlush': true});
        bundle.webview.emitEvent('contentChanged', {'isFlush': false});

        await pumpEventQueue();
        expect(events, [true, false]);
        await sub.cancel();
      });

      test('onSelectionChanged delivers Range', () async {
        final bundle = await _createBundle();
        final events = <Range?>[];
        final sub = bundle.controller.onSelectionChanged.listen(events.add);

        bundle.webview.emitEvent('selectionChanged', {
          'selection': {
            'startLineNumber': 1,
            'startColumn': 1,
            'endLineNumber': 2,
            'endColumn': 3,
          },
        });

        await pumpEventQueue();
        expect(events.length, 1);
        expect(events.first?.endLine, 2);
        await sub.cancel();
      });

      test('onFocus/onBlur deliver focusChanged events', () async {
        final bundle = await _createBundle();
        var focusCount = 0;
        var blurCount = 0;
        final subs = [
          bundle.controller.onFocus.listen((_) => focusCount++),
          bundle.controller.onBlur.listen((_) => blurCount++),
        ];

        bundle.webview.emitEvent('focusChanged', {'focused': true});
        bundle.webview.emitEvent('focusChanged', {'focused': false});

        await pumpEventQueue();
        expect(focusCount, 1);
        expect(blurCount, 1);

        for (final sub in subs) {
          await sub.cancel();
        }
      });
    });

    group('getStatistics', () {
      test('returns current liveStats value', () async {
        final bundle = await _createBundle();

        bundle.webview.emitEvent('stats', {'lineCount': 10, 'charCount': 50});
        await pumpEventQueue();

        final stats = bundle.controller.getStatistics();
        expect(stats.lineCount.value, 10);
        expect(stats.charCount.value, 50);
      });
    });

    group('setJsonDiagnostics', () {
      test('waits for ready before executing', () async {
        final bundle = await _createBundle(ready: false);
        final future = bundle.controller.setJsonDiagnostics(
          const JsonDiagnosticsOptions(validate: true),
        );
        expect(bundle.webview.executed, isEmpty);
        bundle.controller.completeReadyForTesting();
        await future;
        expect(bundle.webview.hasExecuted('json.configureDiagnostics'), true);
      });

      test('generates correct JS payload', () async {
        final bundle = await _createBundle();
        await bundle.controller.setJsonDiagnostics(
          JsonDiagnosticsOptions(
            validate: true,
            allowComments: true,
            schemaValidation: DiagnosticsSeverity.error,
            trailingCommas: DiagnosticsSeverity.warning,
            schemas: [
              JsonDiagnosticsSchema(
                uri: Uri.parse('https://example.com/schema.json'),
                fileMatch: ['*'],
              ),
            ],
          ),
        );

        final joined = bundle.webview.executed.join('\n');
        expect(joined, contains('json.configureDiagnostics'));
        expect(joined, contains('"validate":true'));
        expect(joined, contains('"allowComments":true'));
        expect(joined, contains('"schemaValidation":"error"'));
        expect(joined, contains('"trailingCommas":"warning"'));
        expect(joined, contains('"uri":"https://example.com/schema.json"'));
        expect(joined, contains('"fileMatch":["*"]'));
      });

      test('propagates JavaScript errors', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandFailure(
          'json.configureDiagnostics',
          message: 'json diagnostics failed',
        );

        await expectLater(
          () => bundle.controller.setJsonDiagnostics(
            const JsonDiagnosticsOptions(validate: true),
          ),
          throwsA(
            isA<MonacoJavaScriptException>()
                .having(
                  (e) => e.operation,
                  'operation',
                  'json.configureDiagnostics',
                )
                .having((e) => e.message, 'message', 'json diagnostics failed'),
          ),
        );
      });
    });

    group('runJavaScript', () {
      test('executes script after ready', () async {
        final bundle = await _createBundle();
        await bundle.controller.runJavaScript('console.log("hello")');
        expect(
          bundle.webview.executed.any((s) => s.contains('console.log')),
          true,
        );
      });

      test('waits for ready before executing', () async {
        final bundle = await _createBundle(ready: false);
        final future = bundle.controller.runJavaScript('myCustomSetup()');
        expect(bundle.webview.executed, isEmpty);
        bundle.controller.completeReadyForTesting();
        await future;
        expect(
          bundle.webview.executed.any((s) => s.contains('myCustomSetup')),
          true,
        );
      });

      test('propagates platform exceptions', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOnContains('throw new Error');

        await expectLater(
          bundle.controller.runJavaScript('throw new Error()'),
          throwsStateError,
        );
      });
    });

    group('evaluateJavaScript', () {
      test('sends the expression through page.eval', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: 42);

        await bundle.controller.evaluateJavaScript<int>(
          'monaco.editor.getEditors().length',
        );

        final call = _dispatchesOf(bundle.webview, 'page.eval').single;
        expect(
          _paramsOf(call)['expression'],
          'monaco.editor.getEditors().length',
        );
      });

      test('normalizes numeric result to int', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: 42);

        final result = await bundle.controller.evaluateJavaScript<int>(
          'myQuery()',
        );

        expect(result, 42);
        expect(result, isA<int>());
      });

      test('normalizes boolean result to bool', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: true);

        final result = await bundle.controller.evaluateJavaScript<bool>(
          'someFlag',
        );

        expect(result, true);
        expect(result, isA<bool>());
      });

      test('preserves string result', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: 'hello');

        final result = await bundle.controller.evaluateJavaScript<String>(
          '"hello"',
        );

        expect(result, 'hello');
      });

      test(
        'preserves numeric-looking string result when T is String',
        () async {
          final bundle = await _createBundle();
          bundle.webview.injectCommandSuccess('page.eval', value: '42');

          final result = await bundle.controller.evaluateJavaScript<String>(
            '"42"',
          );

          expect(result, '42');
          expect(result, isA<String>());
        },
      );

      test('returns maps', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: {'count': 2});

        final result = await bundle.controller
            .evaluateJavaScript<Map<String, dynamic>>('({ count: 2 })');

        expect(result, {'count': 2});
      });

      test('returns lists', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: [1, 2, 3]);

        final result = await bundle.controller
            .evaluateJavaScript<List<dynamic>>('[1, 2, 3]');

        expect(result, [1, 2, 3]);
      });

      test('returns defaultValue when JavaScript returns null', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval');

        final result = await bundle.controller.evaluateJavaScript<int>(
          'missingThing',
          defaultValue: -1,
        );

        expect(result, -1);
      });

      test('returns defaultValue when JavaScript returns undefined', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', isUndefined: true);

        final result = await bundle.controller.evaluateJavaScript<int>(
          'missingThing',
          defaultValue: -1,
        );

        expect(result, -1);
      });

      test('returns defaultValue when value cannot convert to T', () async {
        final bundle = await _createBundle();
        bundle.webview.injectCommandSuccess('page.eval', value: {'count': 2});

        final result = await bundle.controller.evaluateJavaScript<int>(
          '({ count: 2 })',
          defaultValue: -1,
        );

        expect(result, -1);
      });

      test('waits for ready before executing', () async {
        final bundle = await _createBundle(ready: false);
        bundle.webview.injectCommandSuccess('page.eval', value: 7);
        final future = bundle.controller.evaluateJavaScript<int>('myQuery()');
        expect(bundle.webview.executed, isEmpty);
        bundle.controller.completeReadyForTesting();
        final result = await future;
        expect(result, 7);
        expect(bundle.webview.executed.any((s) => s.contains('myQuery')), true);
      });

      test('propagates dispatch failures', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOnContains('badExpression');

        await expectLater(
          bundle.controller.evaluateJavaScript<int>('badExpression()'),
          throwsA(
            isA<MonacoJavaScriptException>().having(
              (e) => e.operation,
              'operation',
              'page.eval',
            ),
          ),
        );
      });
    });

    group('runJavaScriptReturningResultRaw', () {
      test('returns platform-native value unchanged', () async {
        final bundle = await _createBundle();
        bundle.webview.enqueueResult('myQuery()', '42');

        final result = await bundle.controller.runJavaScriptReturningResultRaw(
          'myQuery()',
        );

        expect(result, '42');
      });

      test('waits for ready before executing', () async {
        final bundle = await _createBundle(ready: false);
        final future = bundle.controller.runJavaScriptReturningResultRaw(
          'myQuery()',
        );
        expect(bundle.webview.executed, isEmpty);

        bundle.webview.enqueueResult('myQuery()', 42);
        bundle.controller.completeReadyForTesting();

        final result = await future;
        expect(result, 42);
        expect(bundle.webview.executed.any((s) => s.contains('myQuery')), true);
      });

      test('propagates platform exceptions', () async {
        final bundle = await _createBundle();
        bundle.webview.throwOnContains('badQuery');

        await expectLater(
          bundle.controller.runJavaScriptReturningResultRaw('badQuery()'),
          throwsStateError,
        );
      });
    });
  });
}
