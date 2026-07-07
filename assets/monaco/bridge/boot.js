// flutter_monaco bridge - extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml). Do not reformat the
// ported bodies; see upcoming/v3.md Section 14 (verbatim-port inventory).
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

            function postMessageToFlutter(message) {
              if (window.flutterMonacoPostMessage) {
                window.flutterMonacoPostMessage(message);
                return;
              }
              if (typeof message !== 'string') {
                message = JSON.stringify(message);
              }
              if (window.flutterChannel && window.flutterChannel.postMessage) {
                window.flutterChannel.postMessage(message);
              } else {
                console.error('[Monaco] Flutter communication channel is not available.');
              }
            }

            monaco.editor.onDidCreateEditor(function (editor) {
              window.editor = editor;

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

              var FMB = window.__FMB || {};
              var ctx = { postMessageToFlutter: postMessageToFlutter };
              FMB.core(ctx);
              FMB.focusHelpers(ctx);
              const { E, post } = ctx;

                E().onDidChangeModelContent(e => post('contentChanged', { isFlush: e.isFlush }));
                E().onDidChangeCursorSelection(e => post('selectionChanged', {
                  selection: e.selection && {
                    startLineNumber: e.selection.startLineNumber,
                    startColumn: e.selection.startColumn,
                    endLineNumber: e.selection.endLineNumber,
                    endColumn: e.selection.endColumn
                  }
                }));
                E().onDidFocusEditorWidget(() => post('focus', {}));
                E().onDidBlurEditorWidget(() => post('blur', {}));

              FMB.editorApi(ctx);
              FMB.focusMobile(ctx);
              if (FMB.viewportFit) FMB.viewportFit(ctx);
              FMB.completions(ctx);
              FMB.scrollHandoff(ctx);
              FMB.lsp(ctx);

              postMessageToFlutter({ event: 'onEditorReady' });
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
            if (window.flutterMonacoPostMessage) window.flutterMonacoPostMessage({ event: 'error', message: 'Failed to load editor.main: ' + error });
          }
        );
      } catch (e) {
        console.error('[Monaco] FATAL: A critical error occurred trying to call require(). Error:', e);
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
