// flutter_monaco bridge - inline AI edits (pending decorations + CodeLens)
// First-class pending-edit abstraction, not permanent decorations.
// /* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

window.__FMB.inlineEdit = function (ctx) {
  const { E, requireModel } = ctx;
  (function () {
    const edits = new Map(); // id -> {range, text, decorations, lensDisposable}
    let nextId = 1;

    function createDecorations(range, text) {
      const editor = E();
      if (!editor) return [];
      // Green insertion deco - uses Monaco's decoration type via deltaDecorations for now.
      // Will be replaced by dedicated inline edit decorations once we expose full theming.
      const deco = {
        range: range,
        options: {
          inlineClassName: 'flutter-monaco-inline-insert',
          beforeContentClassName: 'flutter-monaco-inline-before',
          afterContentClassName: 'flutter-monaco-inline-after',
          glyphMarginClassName: 'flutter-monaco-inline-glyph',
          overviewRuler: { color: 'rgba(0, 255, 0, 0.4)', position: 4 },
        },
      };
      return [deco];
    }

    window.FlutterMonaco.register('inlineEdit.propose', (p) => {
      const id = 'ie' + (nextId++);
      const range = p.range;
      const text = p.text || '';
      // Store pending edit; render as decoration on the active model.
      const model = requireModel();
      const decoIds = [];
      try {
        const editor = E();
        const ids = editor.deltaDecorations([], [{
          range: range,
          options: {
            inlineClassName: 'flutter-monaco-inline-insert',
            isWholeLine: false,
            className: 'flutter-monaco-inline-line',
            overviewRuler: { color: 'rgba(46, 160, 67, 0.6)', position: 4 },
            glyphMarginClassName: 'codicon codicon-sparkle',
            hoverMessage: { value: 'AI suggestion — Accept (Tab) / Reject (Esc)\n\n' + text.slice(0, 200) },
          }
        }]);
        // Keep decoration ids for removal
        edits.set(id, { range, text, originalText: p.originalText || null, decoIds: ids, modelUri: model.uri ? model.uri.toString() : null });
      } catch (e) {
        edits.set(id, { range, text, originalText: p.originalText || null, decoIds: [], modelUri: null });
      }
      // CodeLens would be added here via monaco.languages.registerCodeLensProvider if needed
      return id;
    });

    window.FlutterMonaco.register('inlineEdit.accept', (p) => {
      const entry = edits.get(p.id);
      if (!entry) throw new Error('Unknown inline edit: ' + p.id);
      const model = requireModel();
      // Apply as single edit operation, grouped via pushEditOperations if available
      try {
        if (model.pushEditOperations) {
          model.pushEditOperations([], [{ range: entry.range, text: entry.text }], () => null);
          model.pushStackElement();
        } else {
          model.applyEdits([{ range: entry.range, text: entry.text }]);
        }
      } catch (e) { throw e; }
      // Clean up decorations
      try { E().deltaDecorations(entry.decoIds || [], []); } catch (_) {}
      edits.delete(p.id);
      return true;
    });

    window.FlutterMonaco.register('inlineEdit.reject', (p) => {
      const entry = edits.get(p.id);
      if (!entry) return true;
      try { E().deltaDecorations(entry.decoIds || [], []); } catch (_) {}
      edits.delete(p.id);
      return true;
    });

    window.FlutterMonaco.register('inlineEdit.acceptAll', () => {
      for (const [id, entry] of Array.from(edits.entries())) {
        try {
          const model = requireModel();
          if (model.pushEditOperations) {
            model.pushEditOperations([], [{ range: entry.range, text: entry.text }], () => null);
          } else {
            model.applyEdits([{ range: entry.range, text: entry.text }]);
          }
          try { E().deltaDecorations(entry.decoIds || [], []); } catch (_) {}
        } catch (_) {}
      }
      // Single undo stop for batch
      try { requireModel().pushStackElement(); } catch (_) {}
      edits.clear();
      return true;
    });

    window.FlutterMonaco.register('inlineEdit.rejectAll', () => {
      for (const [id, entry] of Array.from(edits.entries())) {
        try { E().deltaDecorations(entry.decoIds || [], []); } catch (_) {}
      }
      edits.clear();
      return true;
    });

    window.FlutterMonaco.register('inlineEdit.clear', (p) => {
      const entry = edits.get(p.id);
      if (entry) {
        try { E().deltaDecorations(entry.decoIds || [], []); } catch (_) {}
        edits.delete(p.id);
      }
      return true;
    });

    // Edit transaction primitives - exposed for streaming undo grouping
    window.FlutterMonaco.register('document.pushEditOperations', (p) => {
      const model = requireModel();
      const edits = p.edits || [];
      // edits: [{range, text}]
      const ops = edits.map(e => ({ range: e.range, text: e.text, forceMoveMarkers: !!e.forceMoveMarkers }));
      if (model.pushEditOperations) {
        // groupWithPrevious controls whether we pushStackElement before.
        // Caller controls begin/commit via separate commands.
        model.pushEditOperations([], ops, () => null);
      } else {
        model.applyEdits(ops);
      }
      return true;
    });

    window.FlutterMonaco.register('document.pushUndoStop', () => {
      const model = requireModel();
      if (model.pushStackElement) model.pushStackElement();
      else if (model.pushUndoStop) model.pushUndoStop();
      return true;
    });

    window.FlutterMonaco.register('document.popUndoStop', () => {
      const model = requireModel();
      if (model.popStackElement) model.popStackElement();
      return true;
    });

  })();
};
