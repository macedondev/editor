// flutter_monaco bridge - extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml). Do not reformat the
// ported bodies; see upcoming/v3.md Section 14 (verbatim-port inventory).
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// The typed window.flutterMonaco API surface plus the completion
// provider bridge.
window.__FMB.editorApi = function (ctx) {
  const { E, isMobileInputPlatform, getEditorNode, focusEditorTextAreaNow } = ctx;
                // Typed helpers Flutter will call
                const escapeRegExp = (value) =>
                  (value ?? '').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

                // Strict accessors used by the new flutterMonacoInvoke envelope.
                // Helpers that depend on the editor/model should call these so
                // missing-state errors propagate to Dart instead of being
                // silently swallowed.
                const requireEditor = () => {
                  const ed = E();
                  if (!ed) {
                    throw new Error('Monaco editor is not ready.');
                  }
                  return ed;
                };
                const requireModel = () => {
                  const ed = requireEditor();
                  const model = ed.getModel ? ed.getModel() : null;
                  if (!model) {
                    throw new Error('Monaco editor has no active model.');
                  }
                  return model;
                };

                window.flutterMonaco = {

                  // Basic editor operations
                  focus: () => E().focus(),
                  layout: () => { try { E().layout(); } catch (_) {} },
                  // Force focus robustly: wait for visibility, layout, focus editor and hidden textarea
                  forceFocus: (options = {}) => {
                    try {
                      const ed = E();
                      const node = getEditorNode();
                      if (!ed || !node) return;
                      const replayInputFocus =
                        options && options.replayInputFocus === true;

                      if (isMobileInputPlatform()) {
                        focusEditorTextAreaNow();
                        return;
                      }

                      const attempt = () => {
                        const rect = node.getBoundingClientRect();
                        if (!rect.width || !rect.height) {
                          return requestAnimationFrame(attempt);
                        }
                        // Idempotency guard: if the editor's input already owns
                        // focus, return WITHOUT the document.body.focus() handoff
                        // below. That handoff blurs then refocuses, which flickers
                        // the caret and tears down an open context menu. Refocusing
                        // an already-focused editor must be a no-op - this removes
                        // the flicker for EVERY caller, not just guarded pointers.
                        const input = node.querySelector(
                          'textarea.inputarea, .native-edit-context');
                        if (!replayInputFocus && input && document.activeElement === input) {
                          return;
                        }
                        try { window.focus && window.focus(); } catch (_) {}
                        try {
                          if (document.body && !document.body.hasAttribute('tabindex')) {
                            document.body.setAttribute('tabindex', '-1');
                          }
                          document.body?.focus?.();
                        } catch (_) {}
                        try { ed.layout && ed.layout(); } catch (_) {}
                        try { ed.focus && ed.focus(); } catch (_) {}
                        try {
                          const ta = node.querySelector('textarea.inputarea');
                          if (ta && document.activeElement !== ta) {
                            ta.focus({ preventScroll: true });
                            setTimeout(() => {
                              try { ta.focus({ preventScroll: true }); } catch (_) {}
                            }, 16);
                          }
                        } catch (_) {}
                      };
                      setTimeout(() => requestAnimationFrame(attempt), 0);
                    } catch (_) {}
                  },
                  getValue: () => requireEditor().getValue(),
                  setValue: (v) => {
                    requireEditor().setValue(v || '');
                    return true;
                  },
                  defineTheme: (name, data) => {
                    if (!window.monaco || !monaco.editor) {
                      throw new Error('Monaco editor API is not available.');
                    }
                    if (!name || typeof name !== 'string') {
                      throw new Error('Theme name must be a non-empty string.');
                    }
                    monaco.editor.defineTheme(name, data || {});
                    return true;
                  },
                  setHostPageBackground: (color) => {
                    if (!color) {
                      throw new Error('Host page background color is required.');
                    }
                    const value = String(color);
                    document.documentElement.style.backgroundColor = value;
                    document.body.style.backgroundColor = value;
                    const container = document.getElementById('editor-container');
                    if (container) container.style.backgroundColor = value;
                    return true;
                  },
                  setTheme: (theme) => {
                    if (!theme || typeof theme !== 'string') {
                      throw new Error('Theme id must be a non-empty string.');
                    }
                    monaco.editor.setTheme(theme);
                    return true;
                  },
                  getTheme: () => {
                    if (!window.monaco || !monaco.editor ||
                        typeof monaco.editor.getTheme !== 'function') {
                      return null;
                    }
                    const theme = monaco.editor.getTheme();
                    if (!theme) return null;
                    if (typeof theme === 'string') return theme;
                    return theme.themeName || theme.id || null;
                  },
                  setLanguage: (lang) => {
                    monaco.editor.setModelLanguage(requireModel(), lang);
                    return true;
                  },
                  updateOptions: (opts) => {
                    requireEditor().updateOptions(opts);
                    return true;
                  },
                  executeAction: (actionId, args) => {
                    if (!actionId || typeof actionId !== 'string') {
                      throw new Error('Action id must be a non-empty string.');
                    }
                    const ed = requireEditor();
                    const action = ed.getAction ? ed.getAction(actionId) : null;
                    if (action && typeof action.run === 'function') {
                      action.run(args);
                      return true;
                    }
                    ed.trigger('flutter-bridge', actionId, args);
                    return true;
                  },

                  // Selection
                  getSelection: () => {
                    const s = E().getSelection();
                    return s ? {
                      startLineNumber: s.startLineNumber, startColumn: s.startColumn,
                      endLineNumber: s.endLineNumber, endColumn: s.endColumn
                    } : null;
                  },
                  setSelection: (r) => {
                    requireEditor().setSelection(r);
                    return true;
                  },

                  // Cursor
                  getCursorPosition: () => {
                    const p = E().getPosition();
                    return p ? { lineNumber: p.lineNumber, column: p.column } : null;
                  },
                  setCursorPosition: (line, column) => {
                    requireEditor().setPosition({ lineNumber: line, column: column });
                    return true;
                  },

                  // Navigation
                  revealLine: (ln, center) =>
                    center ? E().revealLineInCenter(ln) : E().revealLine(ln),
                  revealRange: (r, center) =>
                    center ? E().revealRangeInCenter(r) : E().revealRange(r),

                  // Line operations
                  getLineCount: () => requireModel().getLineCount(),
                  getLineContent: (ln) => requireModel().getLineContent(ln),
                  
                  // Word lookup
                  getWordAtPosition: (line, column) => {
                    const m = E().getModel();
                    if (!m) return null;
                    const w = m.getWordAtPosition(new monaco.Position(line, column));
                    return w ? w.word : null;
                  },

                  // Edits
                  applyEdits: (edits, opts) => {
                    requireModel().applyEdits(edits || [], opts || {});
                    return true;
                  },

                  // Decorations
                  deltaDecorations: (oldIds, newDecos) =>
                    requireEditor().deltaDecorations(oldIds || [], newDecos || []),

                  // JSON language diagnostics.
                  // Monaco 0.55 moved the language defaults from
                  // monaco.languages.json to the top-level monaco.json and
                  // deprecated the old path; prefer the new namespace and
                  // fall back so a vendored older build keeps working.
                  setJsonDiagnosticsOptions: (diagnostics) => {
                    const jsonApi = (typeof monaco.json !== 'undefined' && monaco.json) ||
                      (monaco.languages && monaco.languages.json);
                    if (!jsonApi || !jsonApi.jsonDefaults) {
                      throw new Error('Monaco JSON language API is not available.');
                    }
                    jsonApi.jsonDefaults.setDiagnosticsOptions(diagnostics);
                    return true;
                  },

                  // Markers (diagnostics)
                  setModelMarkers: (owner, markers) => {
                    monaco.editor.setModelMarkers(requireModel(), owner || 'flutter', markers || []);
                    return true;
                  },

                  // Find & replace (programmatic)
                  findMatches: (q, options, limit) => {
                    const m = E().getModel();
                    if (!m) return [];
                    const isRegex = !!(options && options.isRegex);
                    const matchCase = !!(options && options.matchCase);
                    const wholeWord = !!(options && options.wholeWord);

                    let search = q ?? '';
                    let useRegex = isRegex;
                    if (wholeWord && !isRegex) {
                      search = '\\b' + escapeRegExp(String(q ?? '')) + '\\b';
                      useRegex = true;
                    }

                    const matches = m.findMatches(
                      search,
                      null,                 // searchScope: null = whole model (FIX: was 'false')
                      useRegex,
                      matchCase,
                      null,
                      false,                // captureMatches
                      limit || 9999
                    );
                    return matches.map(mm => ({ range: mm.range, match: m.getValueInRange(mm.range) }));
                  },

                  replaceMatches: (q, repl, options) => {
                    const m = E().getModel();
                    if (!m) return 0;
                    const isRegex = !!(options && options.isRegex);
                    const matchCase = !!(options && options.matchCase);
                    const wholeWord = !!(options && options.wholeWord);

                    let search = q ?? '';
                    let useRegex = isRegex;
                    if (wholeWord && !isRegex) {
                      search = '\\b' + escapeRegExp(String(q ?? '')) + '\\b';
                      useRegex = true;
                    }

                    const matches = m.findMatches(
                      search,
                      null,                 // searchScope: null = whole model (FIX: was 'false')
                      useRegex,
                      matchCase,
                      null,
                      false,                // captureMatches
                      9999
                    );
                    const edits = matches.map(mm => ({ range: mm.range, text: repl }));
                    m.pushEditOperations([], edits, () => null);
                    return edits.length;
                  },

                  // View state
                  saveViewState: () => E().saveViewState(),
                  restoreViewState: (s) => E().restoreViewState(s),

                  // Stats
                  getStatistics: () => {
                    const e = E(), m = e.getModel(), s = e.getSelection();
                    const position = e.getPosition(); // FIX: Define position in this scope
                    const selections = e.getSelections() || [];
                    return {
                      lineCount: m ? m.getLineCount() : 0,
                      charCount: m ? m.getValueLength() : 0,
                      selLines: (s && !s.isEmpty()) ? (s.endLineNumber - s.startLineNumber + 1) : 0, // FIX: Return 0 for empty selection
                      selChars: (m && s && !s.isEmpty()) ? m.getValueInRange(s).length : 0,
                      caretCount: selections.length,
                      language: m ? (m.getLanguageId ? m.getLanguageId() : monaco.editor.getModelLanguage(m)) : undefined,
                      cursorLine: position?.lineNumber,
                      cursorColumn: position?.column,
                    };
                  },
                  
                  // Dirty tracking (per-model baselines keyed by URI)
                  _baselines: new Map(),
                  _markBaseline(model) {
                    const m = model || E().getModel();
                    if (m && m.uri) {
                      this._baselines.set(m.uri.toString(), m.getAlternativeVersionId());
                    }
                  },
                  hasUnsavedChanges: () => {
                    const m = E().getModel();
                    if (!m || !m.uri) return false;
                    const uri = m.uri.toString();
                    if (!window.flutterMonaco._baselines.has(uri)) {
                      window.flutterMonaco._markBaseline(m);
                    }
                    return m.getAlternativeVersionId() !== window.flutterMonaco._baselines.get(uri);
                  },
                  markSaved: () => window.flutterMonaco._markBaseline(),

                  // Models
                  createModel: (value, language, uri) =>
                    monaco.editor.createModel(value || '', language || 'plaintext', 
                      uri ? monaco.Uri.parse(uri) : undefined).uri.toString(),
                  setModel: (uri) => {
                    const m = monaco.editor.getModel(monaco.Uri.parse(uri));
                    if (m) E().setModel(m);
                  },
                  disposeModel: (uri) => {
                    const m = monaco.editor.getModel(monaco.Uri.parse(uri));
                    if (m) m.dispose();
                  },
                  listModels: () => monaco.editor.getModels().map(m => m.uri.toString()),
                };
  ctx.escapeRegExp = escapeRegExp;
  ctx.requireEditor = requireEditor;
  ctx.requireModel = requireModel;
};

window.__FMB.completions = function (ctx) {
  const { postMessageToFlutter } = ctx;
                // Completion bridge: JS stays dumb, Flutter drives the data
                (function () {
                  const completion = {
                    resolvers: Object.create(null),
                    providers: Object.create(null),
                    nextId: 1,
                  };

                  function toIRange(r) {
                    if (!r) return undefined;
                    const sL = r.startLineNumber ?? r.startLine ?? r.from_line ?? r.start ?? 1;
                    const sC = r.startColumn ?? r.startCol ?? r.sc ?? 1;
                    const eL = r.endLineNumber ?? r.endLine ?? r.to_line ?? r.end ?? sL;
                    const eC = r.endColumn ?? r.endCol ?? r.ec ?? sC;
                    return {
                      startLineNumber: sL,
                      startColumn: sC,
                      endLineNumber: eL,
                      endColumn: eC,
                    };
                  }

                  // cfg: { id?: string, languages: string[]|string, triggerCharacters?: string[] }
                  window.flutterMonaco.registerCompletionSource = function (cfg) {
                    const id = cfg?.id || 'flutter_' + completion.nextId++;
                    const langs = Array.isArray(cfg?.languages)
                      ? cfg.languages
                      : [cfg?.languages ?? 'plaintext'];
                    const triggerCharacters = cfg?.triggerCharacters || [];

                    const provider = {
                      triggerCharacters,
                      provideCompletionItems: (model, position, context, token) =>
                        new Promise((resolve) => {
                          const reqId =
                            id + ':' + Date.now() + ':' + Math.random().toString(36).slice(2);
                          const lang =
                            (model.getLanguageId && model.getLanguageId()) ||
                            monaco.editor.getModelLanguage(model);
                          const word = model.getWordUntilPosition(position);
                          const defaultRange = {
                            startLineNumber: position.lineNumber,
                            startColumn: word.startColumn,
                            endLineNumber: position.lineNumber,
                            endColumn: word.endColumn,
                          };
                          completion.resolvers[reqId] = {
                            resolve,
                            defaultRange,
                          };

                          const payload = {
                            event: 'completionRequest',
                            providerId: id,
                            requestId: reqId,
                            language: lang,
                            uri: model.uri?.toString(),
                            position: {
                              lineNumber: position.lineNumber,
                              column: position.column,
                            },
                            defaultRange,
                            lineText: model.getLineContent(position.lineNumber),
                            triggerKind: context?.triggerKind ?? null,
                            triggerCharacter: context?.triggerCharacter ?? null,
                          };
                          postMessageToFlutter(payload);

                          token?.onCancellationRequested?.(() => {
                            delete completion.resolvers[reqId];
                            try {
                              resolve({ suggestions: [] });
                            } catch (_) {}
                          });
                        }),
                    };

                    const disposables = langs.map((l) =>
                      monaco.languages.registerCompletionItemProvider(l, provider),
                    );
                    completion.providers[id] = { disposables };
                    return id;
                  };

                  window.flutterMonaco.unregisterCompletionSource = function (id) {
                    const p = completion.providers[id];
                    if (p?.disposables) {
                      for (const d of p.disposables) {
                        try {
                          d.dispose();
                        } catch (_) {}
                      }
                    }
                    delete completion.providers[id];
                  };

                  // Flutter -> JS: deliver completion results
                  window.flutterMonaco.complete = function (requestId, payload) {
                    const resolver = completion.resolvers[requestId];
                    if (!resolver) return;
                    const resolve = resolver.resolve;
                    const fallbackRange = resolver.defaultRange;
                    try {
                      const items = (payload && payload.suggestions) || [];
                      const defaultRange = payload?.defaultRange || fallbackRange;
                      const mapped = items.map((it) => {
                        let kind = it.kind;
                        if (typeof kind === 'string') {
                          kind = monaco.languages.CompletionItemKind[kind] ??
                            monaco.languages.CompletionItemKind.Text;
                        }
                        let insertTextRules = it.insertTextRules;
                        if (Array.isArray(insertTextRules)) {
                          insertTextRules = insertTextRules.reduce((mask, rule) => {
                            const value = monaco.languages.CompletionItemInsertTextRule[rule];
                            return typeof value === 'number' ? (mask | value) : mask;
                          }, 0);
                        }
                        return {
                          label: it.label,
                          insertText: it.insertText || it.label,
                          kind: kind || monaco.languages.CompletionItemKind.Text,
                          detail: it.detail,
                          documentation: it.documentation,
                          sortText: it.sortText,
                          filterText: it.filterText,
                          commitCharacters: it.commitCharacters,
                          insertTextRules: insertTextRules || undefined,
                          range: toIRange(it.range) || toIRange(defaultRange),
                        };
                      });
                      resolve({
                        suggestions: mapped,
                        incomplete: !!payload?.isIncomplete,
                      });
                    } finally {
                      delete completion.resolvers[requestId];
                    }
                  };
                })();
};
