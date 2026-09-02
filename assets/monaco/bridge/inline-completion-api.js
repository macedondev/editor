// flutter_monaco bridge - inline completions (ghost text) for AI.
// Mirrors the completion bridge but uses monaco.languages.registerInlineCompletionsProvider.
// Protocol v3: commands `inlineCompletions.register` / `inlineCompletions.unregister`,
// requests `inlineCompletion` via FlutterMonaco.request/respond with cancellation.
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

window.__FMB.inlineCompletions = function (ctx) {
  (function () {
    const registry = Object.create(null);
    let reqSeq = 0;

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

    function mapInlineItems(payload) {
      const rawItems = (payload && payload.items) || [];
      // Dart sends {items: [{insertText, range?, command?}]}. Map to Monaco InlineCompletion.
      return rawItems.map((it) => {
        if (!it || typeof it.insertText !== 'string') return null;
        const item = { insertText: it.insertText };
        const r = toIRange(it.range);
        if (r) item.range = new monaco.Range(r.startLineNumber, r.startColumn, r.endLineNumber, r.endColumn);
        if (it.command && typeof it.command === 'string') {
          item.command = { id: it.command, title: it.command };
        }
        return item;
      }).filter(Boolean);
    }

    function registerProvider(cfg) {
      if (!cfg || !cfg.id) throw new Error('inlineCompletions.register requires id');
      const id = cfg.id;
      const langs = Array.isArray(cfg.languages) ? cfg.languages : [cfg.languages ?? 'plaintext'];

      const provider = {
        provideInlineCompletions: (model, position, context, token) =>
          new Promise((resolve) => {
            const lang = (model.getLanguageId && model.getLanguageId()) || monaco.editor.getModelLanguage(model);
            const pending = window.FlutterMonaco.request('inlineCompletion', {
              providerId: id,
              requestId: id + ':' + (++reqSeq),
              language: lang,
              uri: model.uri ? model.uri.toString() : null,
              position: { lineNumber: position.lineNumber, column: position.column },
              range: context && context.range ? {
                startLineNumber: context.range.startLineNumber,
                startColumn: context.range.startColumn,
                endLineNumber: context.range.endLineNumber,
                endColumn: context.range.endColumn,
              } : null,
              context: {
                triggerKind: context && typeof context.triggerKind === 'number' ? context.triggerKind : 0,
                selectedSuggestionInfo: null,
              },
            });

            let settled = false;
            const doResolve = (value) => {
              if (settled) return;
              settled = true;
              resolve(value);
            };

            token && token.onCancellationRequested && token.onCancellationRequested(() => {
              window.FlutterMonaco.dropRequest(pending.id);
              try { doResolve({ items: [] }); } catch (_) {}
            });

            pending.promise.then(
              (payload) => {
                const items = mapInlineItems(payload);
                // Monaco expects {items: InlineCompletion[], commands?} or {items}
                doResolve({ items: items });
              },
              () => doResolve({ items: [] })
            );
          }),
        // freeInlineCompletions is optional; no-op.
        freeInlineCompletions: (completions) => {},
        handleItemDidShow: (completions, item) => {},
      };

      const existing = registry[id];
      if (existing && existing.disposables) {
        for (const d of existing.disposables) { try { d.dispose(); } catch (_) {} }
      }

      const disposables = langs.map((l) =>
        monaco.languages.registerInlineCompletionsProvider(l, provider)
      );
      registry[id] = { disposables };
      return true;
    }

    function unregisterProvider(id) {
      const entry = registry[id];
      if (entry && entry.disposables) {
        for (const d of entry.disposables) { try { d.dispose(); } catch (_) {} }
      }
      delete registry[id];
      return true;
    }

    window.FlutterMonaco.register('inlineCompletions.register', (p) => registerProvider(p));
    window.FlutterMonaco.register('inlineCompletions.unregister', (p) => unregisterProvider(p.id));

    // For testing: expose registry size
    window.__FMB.inlineCompletions.registry = registry;
  })();
};
