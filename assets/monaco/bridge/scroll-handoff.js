// flutter_monaco bridge - extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml). Do not reformat the
// ported bodies; see upcoming/v3.md Section 14 (verbatim-port inventory).
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// Edge scroll handoff module. VERBATIM PORT.
window.__FMB.scrollHandoff = function (ctx) {
  const { E, post } = ctx;
                // Edge scroll handoff (opt-in): forward scroll deltas the
                // editor cannot consume to Flutter, which applies them to a
                // host scrollable. Sources are toggled from Dart through
                // flutterMonaco.setScrollHandoff; while disabled this module
                // installs no DOM listeners and adds no per-event work, so
                // the default editor behavior is untouched.
                (function () {
                  const EDGE_EPSILON = 1;
                  const TOUCH_SLOP = 8;
                  const handoffState = {
                    wheel: false,
                    touch: false,
                    touchGesture: null,
                    touchSelectionWatch: null,
                  };

                  const scrollMetrics = (ed) => {
                    let layout = null;
                    try { layout = ed.getLayoutInfo ? ed.getLayoutInfo() : null; } catch (_) {}
                    const viewportHeight = (layout && layout.height) || 0;
                    const viewportWidth = (layout && layout.width) || 0;
                    const scrollTop = ed.getScrollTop ? ed.getScrollTop() : 0;
                    const scrollLeft = ed.getScrollLeft ? ed.getScrollLeft() : 0;
                    const scrollHeight = ed.getScrollHeight ? ed.getScrollHeight() : 0;
                    const scrollWidth = ed.getScrollWidth ? ed.getScrollWidth() : 0;
                    const maxTop = Math.max(0, scrollHeight - viewportHeight);
                    const maxLeft = Math.max(0, scrollWidth - viewportWidth);
                    return {
                      maxTop: maxTop,
                      viewportHeight: viewportHeight,
                      atTop: scrollTop <= EDGE_EPSILON,
                      atBottom: scrollTop >= maxTop - EDGE_EPSILON,
                      atLeft: scrollLeft <= EDGE_EPSILON,
                      atRight: scrollLeft >= maxLeft - EDGE_EPSILON,
                    };
                  };

                  const editorLineHeight = (ed) => {
                    try {
                      const value = ed.getOption(monaco.editor.EditorOption.lineHeight);
                      if (typeof value === 'number' && value > 0) return value;
                    } catch (_) {}
                    return 20;
                  };

                  const editorWheelDisabled = (ed) => {
                    try {
                      const scrollbar = ed.getOption(monaco.editor.EditorOption.scrollbar);
                      return !!scrollbar && scrollbar.handleMouseWheel === false;
                    } catch (_) {}
                    return false;
                  };

                  // Default deny: only the main editor scroll region hands
                  // off. Monaco-owned overlays (suggest list, hover, find,
                  // menus, peek editors) keep their own wheel handling, and
                  // widgets rendered outside the editor DOM never match.
                  const HANDOFF_BLOCKED_WIDGETS = [
                    '.suggest-widget', '.suggest-details-container',
                    '.monaco-hover', '.parameter-hints-widget',
                    '.find-widget', '.context-view', '.monaco-menu',
                    '.quick-input-widget', '.zone-widget',
                    '.peekview-widget', '.rename-box', '.monaco-inputbox',
                  ].join(', ');
                  const isMainScrollRegion = (ed, target) => {
                    const editorDom = ed.getDomNode ? ed.getDomNode() : null;
                    if (!editorDom) return false;
                    let el = target;
                    if (el && el.nodeType !== 1) el = el.parentElement;
                    if (!el || !el.closest || !editorDom.contains(el)) return false;
                    if (el.closest(HANDOFF_BLOCKED_WIDGETS)) return false;
                    if (el.closest('.monaco-editor') !== editorDom) return false;
                    const scrollable = el.closest('.monaco-scrollable-element');
                    if (scrollable && !scrollable.classList.contains('editor-scrollable')) {
                      return false;
                    }
                    return true;
                  };

                  const postHandoff = (source, deltaX, deltaY, metrics) => {
                    post('scrollHandoff', {
                      source: source,
                      deltaX: deltaX,
                      deltaY: deltaY,
                      atTop: metrics.atTop,
                      atBottom: metrics.atBottom,
                      atLeft: metrics.atLeft,
                      atRight: metrics.atRight,
                    });
                  };

                  const onHandoffWheel = (event) => {
                    try {
                      if (event.defaultPrevented) return;
                      // Zoom owns ctrl/meta wheel: editor mouseWheelZoom,
                      // browser zoom, and macOS pinch (reported as ctrl).
                      if (event.ctrlKey || event.metaKey) return;
                      const ed = E();
                      if (!ed || !isMainScrollRegion(ed, event.target)) return;

                      const metrics = scrollMetrics(ed);
                      let deltaX = event.deltaX || 0;
                      let deltaY = event.deltaY || 0;
                      if (event.deltaMode === 1) {
                        const lineHeight = editorLineHeight(ed);
                        deltaX *= lineHeight;
                        deltaY *= lineHeight;
                      } else if (event.deltaMode === 2) {
                        deltaX *= metrics.viewportHeight;
                        deltaY *= metrics.viewportHeight;
                      }
                      // Vertical handoff only: dominant-horizontal wheel
                      // input stays with the editor.
                      if (deltaY === 0 || Math.abs(deltaY) <= Math.abs(deltaX)) return;

                      const wantsDown = deltaY > 0;
                      const editorCannotConsume =
                        editorWheelDisabled(ed) ||
                        metrics.maxTop <= EDGE_EPSILON ||
                        (wantsDown ? metrics.atBottom : metrics.atTop);
                      if (!editorCannotConsume) return;

                      event.preventDefault();
                      event.stopPropagation();
                      postHandoff('wheel', deltaX, deltaY, metrics);
                    } catch (_) {}
                  };

                  // Touch forwarding is observation-only: passive listeners
                  // that never block, refocus, or select, so Monaco's touch
                  // handling and the mobile focus guards keep working exactly
                  // as before. Worst case is an extra parent scroll, never a
                  // broken editor gesture.
                  const gestureTouch = (event) => {
                    const gesture = handoffState.touchGesture;
                    if (!gesture) return null;
                    const touches = event.changedTouches || [];
                    for (let i = 0; i < touches.length; i++) {
                      if (touches[i].identifier === gesture.id) return touches[i];
                    }
                    return null;
                  };
                  const onHandoffTouchStart = (event) => {
                    try {
                      if (event.touches && event.touches.length > 1) {
                        handoffState.touchGesture = null;
                        return;
                      }
                      const touchPoint = (event.touches && event.touches[0]) ||
                        (event.changedTouches && event.changedTouches[0]);
                      if (!touchPoint) return;
                      const ed = E();
                      if (!ed || !isMainScrollRegion(ed, event.target)) {
                        handoffState.touchGesture = null;
                        return;
                      }
                      handoffState.touchGesture = {
                        id: touchPoint.identifier,
                        startX: touchPoint.clientX,
                        startY: touchPoint.clientY,
                        lastY: touchPoint.clientY,
                        moved: false,
                        cancelled: false,
                      };
                    } catch (_) {}
                  };
                  const onHandoffTouchMove = (event) => {
                    try {
                      const gesture = handoffState.touchGesture;
                      const touchPoint = gestureTouch(event);
                      if (!gesture || !touchPoint || gesture.cancelled) return;
                      const dy = touchPoint.clientY - gesture.lastY;
                      gesture.lastY = touchPoint.clientY;
                      if (!gesture.moved) {
                        const totalX = touchPoint.clientX - gesture.startX;
                        const totalY = touchPoint.clientY - gesture.startY;
                        if ((totalX * totalX + totalY * totalY) <= TOUCH_SLOP * TOUCH_SLOP) {
                          return;
                        }
                        gesture.moved = true;
                      }
                      if (dy === 0) return;
                      const ed = E();
                      if (!ed) return;
                      // A downward finger drag requests scrolling up; express
                      // the intent with wheel-style sign conventions.
                      const deltaY = -dy;
                      const metrics = scrollMetrics(ed);
                      const wantsDown = deltaY > 0;
                      const editorCannotConsume =
                        metrics.maxTop <= EDGE_EPSILON ||
                        (wantsDown ? metrics.atBottom : metrics.atTop);
                      if (!editorCannotConsume) return;
                      postHandoff('touch', 0, deltaY, metrics);
                    } catch (_) {}
                  };
                  const onHandoffTouchEnd = (event) => {
                    try {
                      if (gestureTouch(event)) handoffState.touchGesture = null;
                    } catch (_) {}
                  };

                  const wheelOptions = { capture: true, passive: false };
                  const touchOptions = { capture: true, passive: true };
                  const installScrollHandoffWheel = () => {
                    window.addEventListener('wheel', onHandoffWheel, wheelOptions);
                  };
                  const removeScrollHandoffWheel = () => {
                    window.removeEventListener('wheel', onHandoffWheel, wheelOptions);
                  };
                  const installScrollHandoffTouch = () => {
                    window.addEventListener('touchstart', onHandoffTouchStart, touchOptions);
                    window.addEventListener('touchmove', onHandoffTouchMove, touchOptions);
                    window.addEventListener('touchend', onHandoffTouchEnd, touchOptions);
                    window.addEventListener('touchcancel', onHandoffTouchEnd, touchOptions);
                    try {
                      const ed = E();
                      if (ed && ed.onDidChangeCursorSelection && !handoffState.touchSelectionWatch) {
                        // Text selection wins: a selection change during a
                        // moved gesture stops forwarding for that gesture.
                        handoffState.touchSelectionWatch = ed.onDidChangeCursorSelection(() => {
                          const gesture = handoffState.touchGesture;
                          if (gesture && gesture.moved) gesture.cancelled = true;
                        });
                      }
                    } catch (_) {}
                  };
                  const removeScrollHandoffTouch = () => {
                    window.removeEventListener('touchstart', onHandoffTouchStart, touchOptions);
                    window.removeEventListener('touchmove', onHandoffTouchMove, touchOptions);
                    window.removeEventListener('touchend', onHandoffTouchEnd, touchOptions);
                    window.removeEventListener('touchcancel', onHandoffTouchEnd, touchOptions);
                    const watch = handoffState.touchSelectionWatch;
                    handoffState.touchSelectionWatch = null;
                    if (watch && watch.dispose) {
                      try { watch.dispose(); } catch (_) {}
                    }
                    handoffState.touchGesture = null;
                  };

                  window.flutterMonaco.setScrollHandoff = function (cfg) {
                    const wheel = !!(cfg && cfg.wheel);
                    const touch = !!(cfg && cfg.touch);
                    if (wheel !== handoffState.wheel) {
                      handoffState.wheel = wheel;
                      if (wheel) { installScrollHandoffWheel(); }
                      else { removeScrollHandoffWheel(); }
                    }
                    if (touch !== handoffState.touch) {
                      handoffState.touch = touch;
                      if (touch) { installScrollHandoffTouch(); }
                      else { removeScrollHandoffTouch(); }
                    }
                    return true;
                  };
                })();

                // ---- protocol v3 command registry ----
                window.FlutterMonaco.register('page.setScrollHandoff', (p) =>
                  window.flutterMonaco.setScrollHandoff({ wheel: !!p.wheel, touch: !!p.touch }));
};
