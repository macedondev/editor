// flutter_monaco bridge - boot orchestration. The stats emitter and event
// wiring are ported verbatim from the 2.3.0 generated page; lifecycle and
// event posts ride the protocol v3 envelope (see core.js).
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// Boot orchestration: requires editor.main, wires stats/event emitters,
// runs the bridge installers in the original 2.3.0 execution order, and
// creates the editor.
(function () {
  function _startMonaco() {
      console.log('[Monaco HTML] Attempting to require editor.main...');
      try {
        require(
          ['vs/editor/editor.main'],
          function () {
            console.log('[Monaco] SUCCESS: editor.main.js has loaded. Initializing editor...');

            monaco.editor.onDidCreateEditor(function (editor) {
              window.editor = editor;

              var FMB = window.__FMB || {};
              var ctx = {};
              FMB.core(ctx);
              FMB.focusHelpers(ctx);
              const { E, post, postMessageToFlutter } = ctx;

              // Send live statistics updates
              const sendStats = () => {
                if (!editor.getModel() || !editor.getSelection()) return;
                const model = editor.getModel(), selection = editor.getSelection(), selections = editor.getSelections() || [];
                const position = editor.getPosition();
                postMessageToFlutter({
                  event: 'stats',
                  lineCount: model.getLineCount(),
                  charCount: model.getValueLength(),
                  selLines: selection.isEmpty() ? 0 : (selection.endLineNumber - selection.startLineNumber + 1),
                  selChars: selection.isEmpty() ? 0 : model.getValueInRange(selection).length,
                  caretCount: selections.length,
                  language: model.getLanguageId ? model.getLanguageId() : monaco.editor.getModelLanguage(model),
                  cursorLine: position?.lineNumber,
                  cursorColumn: position?.column,
                });
              };
              editor.onDidChangeModelContent(sendStats);
              editor.onDidChangeCursorSelection(sendStats);
              sendStats();

                E().onDidChangeModelContent(e => post('contentChanged', { isFlush: e.isFlush }));
                E().onDidChangeCursorSelection(e => post('selectionChanged', {
                  selection: e.selection && {
                    startLineNumber: e.selection.startLineNumber,
                    startColumn: e.selection.startColumn,
                    endLineNumber: e.selection.endLineNumber,
                    endColumn: e.selection.endColumn
                  }
                }));
                E().onDidFocusEditorWidget(() => post('focusChanged', { focused: true }));
                E().onDidBlurEditorWidget(() => post('focusChanged', { focused: false }));

              FMB.editorApi(ctx);
              FMB.focusMobile(ctx);
              if (FMB.viewportFit) FMB.viewportFit(ctx);
              FMB.completions(ctx);
              FMB.scrollHandoff(ctx);
              FMB.lsp(ctx);

              window.FlutterMonaco.lifecycle('ready');
              console.log('[Monaco] Editor is ready and the Flutter bridge is installed.');
            });

            monaco.editor.create(document.getElementById('editor-container'), {
              value: '// Monaco Editor is ready',
              language: 'markdown',
              theme: 'vs-dark',
              automaticLayout: true,
              wordWrap: 'on',
              padding: { top: 10 },
              minimap: { enabled: false }
            });
          },
          function (error) {
            console.error('[Monaco] FATAL: require() failed to load editor.main.js. Error:', error);
            if (window.FlutterMonaco) {
              window.FlutterMonaco.lifecycle('fatal', {
                error: {
                  name: 'RequireError',
                  message: 'Failed to load editor.main: ' + error,
                  stack: null,
                },
              });
            }
          }
        );
      } catch (e) {
        console.error('[Monaco] FATAL: A critical error occurred trying to call require(). Error:', e);
        if (window.FlutterMonaco) {
          window.FlutterMonaco.lifecycle('fatal', {
            error: {
              name: 'RequireError',
              message: 'require() call failed: ' + e,
              stack: e && e.stack ? String(e.stack) : null,
            },
          });
        }
      }
  }

  if (window.__FM_PAGE && window.__FM_PAGE.platform === 'web') {
    // Web: loader.js is injected dynamically; wait for it before require().
    var _initMonaco = function () {
      if (!window._monacoLoaderReady) {
        window._initMonacoWhenReady = _initMonaco;
        return;
      }
      _startMonaco();
    };
    _initMonaco();
  } else {
    _startMonaco();
  }
})();
