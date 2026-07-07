// flutter_monaco bridge - extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml). Do not reformat the
// ported bodies; see upcoming/v3.md Section 14 (verbatim-port inventory).
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// Mobile web keyboard viewport fit (issue #11). Web-only script: the
// HTML template references this file only on the web platform.
// VERBATIM PORT.
window.__FMB.viewportFit = function (ctx) {
  const { E, isMobileInputPlatform, bindParentListener } = ctx;
                // Mobile web keyboard fit (issue #11): the soft keyboard
                // shrinks only the host page's *visual* viewport. This iframe
                // keeps its layout size, so Monaco keeps rendering lines under
                // the keyboard while Safari pans the host page to chase the
                // hidden caret textarea - the editor's top band leaves the
                // screen and cannot be scrolled back while the keyboard is up.
                // While the parent's visual viewport is constrained, pin
                // #editor-container to the visible intersection of this frame
                // (automaticLayout relayouts Monaco via its ResizeObserver);
                // restore the stylesheet layout once it is unconstrained.
                if (isMobileInputPlatform() && !window.__flutterMonacoViewportFitBound) {
                  try {
                    const fitWindow = window;
                    const fitContainer = document.getElementById('editor-container');
                    const fitFrame = fitWindow.frameElement;
                    const fitParent = fitWindow.parent;
                    if (fitContainer && fitFrame && fitParent && fitParent !== fitWindow && fitParent.visualViewport) {
                      fitWindow.__flutterMonacoViewportFitBound = true;
                      const fitViewport = fitParent.visualViewport;
                      // The pin below exists FOR the constrained-visual-viewport
                      // states only: the soft keyboard shrinking the visual
                      // viewport, or Safari panning it (nonzero offsets) to
                      // chase the caret. A frame that merely extends past the
                      // layout viewport - an editor half-scrolled off inside a
                      // scrollable Flutter page - must keep its stylesheet
                      // layout, or its content would anchor to the screen band
                      // instead of scrolling away with the page. Pinch zoom
                      // also shrinks the visual viewport but pans freely;
                      // pinning would fight the user's zoom, so scale != 1 is
                      // excluded.
                      const isViewportConstrained = () => {
                        const scale = fitViewport.scale || 1;
                        if (Math.abs(scale - 1) > 0.02) return false;
                        if (fitViewport.offsetLeft > 1 || fitViewport.offsetTop > 1) return true;
                        const layoutWidth = fitParent.innerWidth || 0;
                        const layoutHeight = fitParent.innerHeight || 0;
                        // 24px absorbs scrollbar and rounding noise; soft
                        // keyboards and hardware-keyboard accessory bars are
                        // all taller than that.
                        return (
                          (layoutHeight > 0 && layoutHeight - fitViewport.height > 24) ||
                          (layoutWidth > 0 && layoutWidth - fitViewport.width > 24)
                        );
                      };
                      let fitRaf = 0;
                      let fitApplied = false;
                      let fitLast = '';
                      const clearViewportFit = () => {
                        fitLast = '';
                        if (!fitApplied) return;
                        fitApplied = false;
                        fitContainer.style.position = '';
                        fitContainer.style.top = '';
                        fitContainer.style.left = '';
                        fitContainer.style.width = '';
                        fitContainer.style.height = '';
                      };
                      const scheduleViewportFit = () => {
                        if (fitRaf) return;
                        try {
                          fitRaf = fitWindow.requestAnimationFrame(applyViewportFit);
                        } catch (_) {
                          fitRaf = 0;
                        }
                      };
                      const applyViewportFit = () => {
                        fitRaf = 0;
                        let rect = null;
                        try { rect = fitFrame.getBoundingClientRect(); } catch (_) {}
                        if (!rect || rect.width <= 0 || rect.height <= 0) {
                          clearViewportFit();
                          return;
                        }
                        if (!isViewportConstrained()) {
                          clearViewportFit();
                          return;
                        }
                        // Keep tracking while constrained: Flutter can move the
                        // frame (scrolling, route animations) without firing
                        // any parent viewport event.
                        scheduleViewportFit();
                        const viewLeft = fitViewport.offsetLeft;
                        const viewTop = fitViewport.offsetTop;
                        const viewWidth = fitViewport.width || fitParent.innerWidth || rect.width;
                        const viewHeight = fitViewport.height || fitParent.innerHeight || rect.height;
                        const left = Math.max(rect.left, viewLeft);
                        const top = Math.max(rect.top, viewTop);
                        const width = Math.min(rect.right, viewLeft + viewWidth) - left;
                        const height = Math.min(rect.bottom, viewTop + viewHeight) - top;
                        if (width >= rect.width - 1 && height >= rect.height - 1) {
                          // Fully visible above the keyboard: the stylesheet
                          // layout is already correct; the reschedule above
                          // keeps watching while the viewport stays
                          // constrained.
                          clearViewportFit();
                          return;
                        }
                        // Sub-48px intersections are mid-transition slivers;
                        // keep the previous geometry instead of collapsing.
                        if (width < 48 || height < 48) return;
                        const next =
                          Math.round(left - rect.left) + ':' + Math.round(top - rect.top) +
                          ':' + Math.round(width) + ':' + Math.round(height);
                        if (next === fitLast) return;
                        fitLast = next;
                        fitApplied = true;
                        fitContainer.style.position = 'absolute';
                        fitContainer.style.left = Math.round(left - rect.left) + 'px';
                        fitContainer.style.top = Math.round(top - rect.top) + 'px';
                        fitContainer.style.width = Math.round(width) + 'px';
                        fitContainer.style.height = Math.round(height) + 'px';
                        try {
                          const ed = E();
                          if (ed && ed.hasTextFocus && ed.hasTextFocus()) {
                            const pos = ed.getPosition && ed.getPosition();
                            if (pos && ed.revealPosition) ed.revealPosition(pos);
                          }
                        } catch (_) {}
                      };
                      bindParentListener(fitViewport, 'resize', scheduleViewportFit, { passive: true });
                      bindParentListener(fitViewport, 'scroll', scheduleViewportFit, { passive: true });
                      bindParentListener(fitParent, 'resize', scheduleViewportFit, { passive: true });
                      scheduleViewportFit();
                    }
                  } catch (_) {}
                }

};
