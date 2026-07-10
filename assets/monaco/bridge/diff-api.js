// flutter_monaco bridge - diff editor commands (protocol v3, Phase 11).
// The diff.* registry only comes alive when page.boot arrives with
// mode: 'diff'; a single-editor page never registers these commands.
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

window.__FMB.diffApi = function (ctx) {
  var FM = window.FlutterMonaco;
  var state = { editor: null, language: 'plaintext' };
  ctx.diffState = state;

  function requireDiff() {
    if (!state.editor) {
      throw new Error('Diff editor not booted (page.boot mode "diff").');
    }
    return state.editor;
  }

  FM.register('diff.setTexts', function (p) {
    var models = requireDiff().getModel();
    models.original.setValue(typeof p.original === 'string' ? p.original : '');
    models.modified.setValue(typeof p.modified === 'string' ? p.modified : '');
    if (p.language) {
      state.language = p.language;
      monaco.editor.setModelLanguage(models.original, p.language);
      monaco.editor.setModelLanguage(models.modified, p.language);
    }
    return true;
  });

  // Accepts both IDiffEditorOptions and plain editor options; a `theme` key
  // is routed to the global monaco.editor.setTheme (themes are not
  // per-editor in Monaco).
  FM.register('diff.updateOptions', function (p) {
    var editor = requireDiff();
    var options = Object.assign({}, (p && p.options) || {});
    if (typeof options.theme === 'string') {
      monaco.editor.setTheme(options.theme);
      delete options.theme;
    }
    editor.updateOptions(options);
    return true;
  });

  FM.register('diff.revealNextChange', function () {
    var editor = requireDiff();
    if (typeof editor.goToDiff === 'function') {
      editor.goToDiff('next');
    } else if (typeof editor.accessibleDiffViewerNext === 'function') {
      editor.accessibleDiffViewerNext();
    }
    return true;
  });

  FM.register('diff.revealPreviousChange', function () {
    var editor = requireDiff();
    if (typeof editor.goToDiff === 'function') {
      editor.goToDiff('previous');
    } else if (typeof editor.accessibleDiffViewerPrev === 'function') {
      editor.accessibleDiffViewerPrev();
    }
    return true;
  });

  FM.register('diff.getState', function () {
    var editor = requireDiff();
    var models = editor.getModel();
    var finish = function () {
      var changes = editor.getLineChanges();
      return {
        originalText: models.original.getValue(),
        modifiedText: models.modified.getValue(),
        // null = the diff has not been computed (still pending after the
        // grace window); 0 is a real "no changes" result. The two must be
        // distinguishable ("typed and loud" contract).
        lineChangeCount: changes === null ? null : changes.length,
        language: state.language,
      };
    };
    if (editor.getLineChanges() === null &&
        typeof editor.waitForDiff === 'function') {
      // Monaco >=0.38 computes the diff lazily through observables;
      // waitForDiff observes (and thereby forces) the computation, which
      // may otherwise never run for a throttled/offscreen view. Race a
      // timeout so a pathological model can never hang the bridge -
      // callers then see lineChangeCount null.
      return Promise.race([
        editor.waitForDiff(),
        new Promise(function (resolve) { setTimeout(resolve, 3000); }),
      ]).then(finish);
    }
    return finish();
  });

  // Called by boot.js when page.boot carries mode 'diff'. Creates the diff
  // editor with two fresh models; single-editor emitters are skipped by
  // design - only a stats-lite feed (line/char count of the modified side)
  // is wired.
  ctx.bootDiff = function (params) {
    var options = Object.assign({}, params.options || {});
    delete options.value;
    if (options.automaticLayout === undefined) {
      options.automaticLayout = true;
    }
    Object.assign(options, params.diffOptions || {});
    monaco.editor.setTheme(params.theme || 'vs');

    var language = params.language || 'plaintext';
    state.language = language;
    var editor = monaco.editor.createDiffEditor(
      document.getElementById('editor-container'),
      options
    );
    var original = monaco.editor.createModel(
      typeof params.original === 'string' ? params.original : '',
      language
    );
    var modified = monaco.editor.createModel(
      typeof params.modified === 'string' ? params.modified : '',
      language
    );
    editor.setModel({ original: original, modified: modified });
    state.editor = editor;
    window.diffEditor = editor;

    var sendStats = function () {
      FM.emit('stats', {
        lineCount: modified.getLineCount(),
        charCount: modified.getValueLength(),
        selLines: 0,
        selChars: 0,
        caretCount: 1,
        language: state.language,
      });
    };
    modified.onDidChangeContent(sendStats);
    sendStats();
  };
};
