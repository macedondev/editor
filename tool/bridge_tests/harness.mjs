// Node harness that executes the REAL bridge JavaScript against a minimal
// Monaco stub. This is the semantic layer the Dart fakes cannot cover: the
// Dart suite proves what gets dispatched; these tests prove what the bridge
// implementations actually do with it (dirty baselines, per-model events,
// action promises, completion mapping).
//
// Run: node --test tool/bridge_tests/
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import vm from 'node:vm';

const repoRoot = path.resolve(
  path.dirname(url.fileURLToPath(import.meta.url)),
  '..',
  '..',
);

/** Creates an isolated "page" context and loads core.js into it. */
export function createPage() {
  const messages = [];
  const sandbox = {
    console,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    navigator: { userAgent: 'node-bridge-harness' },
    document: {
      getElementById: () => null,
      body: null,
      addEventListener: () => {},
      querySelector: () => null,
    },
    addEventListener: () => {},
    removeEventListener: () => {},
    flutterChannel: {
      postMessage: (json) => messages.push(JSON.parse(json)),
    },
    __FM_PAGE: { platform: 'test', monacoVersion: 'stub', token: '' },
  };
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);

  const load = (relative) =>
    vm.runInContext(
      fs.readFileSync(path.join(repoRoot, relative), 'utf8'),
      sandbox,
      { filename: relative },
    );
  load('assets/monaco/bridge/core.js');
  return { sandbox, messages, load };
}

/** Installs a minimal Monaco stub faithful to the APIs the bridge uses. */
export function installMonacoStub(sandbox) {
  const models = new Map();

  class Uri {
    constructor(value) {
      this._value = String(value);
    }

    toString() {
      return this._value;
    }

    static parse(value) {
      return new Uri(value);
    }
  }

  class Emitter {
    constructor() {
      this.handlers = new Set();
    }

    event = (handler) => {
      this.handlers.add(handler);
      return { dispose: () => this.handlers.delete(handler) };
    };

    fire(event) {
      for (const handler of [...this.handlers]) handler(event);
    }
  }

  let modelSeq = 0;
  function createModel(value, language, uri) {
    const modelUri = uri || Uri.parse(`inmemory://model/${++modelSeq}`);
    const contentEmitter = new Emitter();
    const disposeEmitter = new Emitter();
    const model = {
      uri: modelUri,
      _value: value || '',
      _altId: 1,
      _lang: language || 'plaintext',
      getValue() {
        return this._value;
      },
      setValue(next) {
        this._value = next ?? '';
        this._altId += 1;
        contentEmitter.fire({
          isFlush: true,
          changes: [
            {
              range: {
                startLineNumber: 1,
                startColumn: 1,
                endLineNumber: 1,
                endColumn: 1,
              },
              text: this._value,
            },
          ],
        });
      },
      getAlternativeVersionId() {
        return this._altId;
      },
      getLineCount() {
        return this._value.split('\n').length;
      },
      getLineContent(line) {
        return this._value.split('\n')[line - 1] ?? '';
      },
      getValueLength() {
        return this._value.length;
      },
      getLanguageId() {
        return this._lang;
      },
      getWordUntilPosition() {
        return { word: '', startColumn: 1, endColumn: 1 };
      },
      getWordAtPosition() {
        return null;
      },
      findMatches() {
        return [];
      },
      applyEdits(edits) {
        for (const edit of edits || []) this._value += edit.text || '';
        this._altId += 1;
        contentEmitter.fire({
          isFlush: false,
          changes: (edits || []).map((edit) => ({
            range: edit.range || {
              startLineNumber: 1,
              startColumn: 1,
              endLineNumber: 1,
              endColumn: 1,
            },
            text: edit.text || '',
          })),
        });
      },
      pushEditOperations(_before, edits) {
        this.applyEdits(edits);
        return null;
      },
      onDidChangeContent: contentEmitter.event,
      onWillDispose: disposeEmitter.event,
      dispose() {
        disposeEmitter.fire({});
        models.delete(this.uri.toString());
      },
    };
    models.set(modelUri.toString(), model);
    return model;
  }

  const modelChangeEmitter = new Emitter();
  const editorState = { model: null };
  const editor = {
    getModel: () => editorState.model,
    setModel(model) {
      editorState.model = model;
      modelChangeEmitter.fire({});
    },
    onDidChangeModel: modelChangeEmitter.event,
    getAction: (id) => (sandbox.__testActions || {})[id] || null,
    trigger() {},
    updateOptions() {},
    layout() {},
    focus() {},
    getSelection: () => null,
    getSelections: () => [],
    getPosition: () => null,
    setSelection() {},
    setPosition() {},
    saveViewState: () => ({}),
    restoreViewState() {},
    createDecorationsCollection: () => ({ set() {}, clear() {} }),
    deltaDecorations: () => [],
    addAction(descriptor) {
      (sandbox.__addedActions ??= []).push(descriptor);
      return { dispose() {} };
    },
  };

  sandbox.monaco = {
    Uri,
    Position: class {
      constructor(lineNumber, column) {
        this.lineNumber = lineNumber;
        this.column = column;
      }
    },
    KeyCode: {},
    KeyMod: {},
    editor: {
      createModel,
      getModel: (uri) => models.get(uri.toString()) || null,
      getModels: () => [...models.values()],
      setModelLanguage: (model, lang) => {
        model._lang = lang;
      },
      setModelMarkers() {},
      setTheme() {},
      getTheme: () => 'vs',
      onDidCreateEditor: () => ({ dispose() {} }),
    },
    languages: {
      CompletionItemKind: { Text: 0 },
      CompletionItemInsertTextRule: {},
      registerCompletionItemProvider(language, provider) {
        (sandbox.__completionProviders ??= []).push({ language, provider });
        return { dispose() {} };
      },
    },
  };

  return { models, editor, editorState };
}

/**
 * Boots an editor-mode page the way boot.js does: boot model first, editor
 * attached, then the bridge modules installed over the shared ctx.
 */
export function bootEditorPage() {
  const page = createPage();
  const stub = installMonacoStub(page.sandbox);
  const bootModel = page.sandbox.monaco.editor.createModel(
    'boot text',
    'plaintext',
  );
  stub.editor.setModel(bootModel);
  page.sandbox.editor = stub.editor;

  page.load('assets/monaco/bridge/editor-api.js');
  const ctx = {};
  page.sandbox.__FMB.core(ctx);
  page.sandbox.__FMB.editorApi(ctx);
  page.load('assets/monaco/bridge/diff-api.js');
  const completionsOk = (() => {
    page.sandbox.__FMB.completions(ctx);
    page.sandbox.__FMB.actions(ctx);
    return true;
  })();
  if (!completionsOk) throw new Error('module install failed');
  return { ...page, ...stub, ctx, bootModel };
}

/** Dispatches a protocol command and resolves with its response envelope. */
export async function dispatch(page, method, params) {
  const id = `r${Math.random().toString(36).slice(2)}`;
  page.sandbox.FlutterMonaco.dispatch({ id, method, params: params || {} });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const response = page.messages.find(
      (message) => message.kind === 'response' && message.id === id,
    );
    if (response) return response;
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  throw new Error(`no response for ${method}`);
}

/** All emitted events with the given name. */
export function eventsNamed(page, name) {
  return page.messages.filter(
    (message) => message.kind === 'event' && message.name === name,
  );
}
