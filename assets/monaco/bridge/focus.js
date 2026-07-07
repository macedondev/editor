// flutter_monaco bridge - extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml). Do not reformat the
// ported bodies; see upcoming/v3.md Section 14 (verbatim-port inventory).
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// Focus helpers + the mobile input compatibility block (tap-vs-scroll
// gesture bridges, Android web focus guard, keyboard-visibility baseline,
// compatibility-event suppression). VERBATIM PORT.
window.__FMB.focusHelpers = function (ctx) {
  const { E } = ctx;
                const getEditorNode = () => {
                  const ed = E();
                  if (!ed) return null;
                  return (ed.getDomNode && ed.getDomNode()) ||
                    (ed.getContainerDomNode && ed.getContainerDomNode()) ||
                    null;
                };
                const focusEditorTextAreaNow = () => {
                  try {
                    const ed = E();
                    const node = getEditorNode();
                    if (!ed || !node) return;
                    try { ed.layout && ed.layout(); } catch (_) {}
                    try { ed.focus && ed.focus(); } catch (_) {}
                    try {
                      const ta = node.querySelector('textarea.inputarea');
                      if (ta && document.activeElement !== ta) {
                        ta.focus();
                      }
                    } catch (_) {}
                  } catch (_) {}
                };
  ctx.getEditorNode = getEditorNode;
  ctx.focusEditorTextAreaNow = focusEditorTextAreaNow;
};

window.__FMB.focusMobile = function (ctx) {
  const { E, isMobileInputPlatform, bindParentListener, getEditorNode, focusEditorTextAreaNow } = ctx;
                if (isMobileInputPlatform()) {
                  try {
                    const node = getEditorNode();
                    if (node && !node.__flutterMonacoMobileFocusBound) {
                      node.__flutterMonacoMobileFocusBound = true;
                      const ownerDocument = node.ownerDocument || document;
                      const ownerWindow = ownerDocument.defaultView || window;
                      const ua = navigator.userAgent || '';
                      const isAndroid = /Android/i.test(ua);
                      const isFlutterWebEmbed = (() => {
                        try {
                          return ownerWindow.parent && ownerWindow.parent !== ownerWindow;
                        } catch (_) {
                          return false;
                        }
                      })();
                      const tapMoveThreshold = 8;
                      const tapTimeThreshold = 650;
                      const compatibilityEventSuppressMs = 1200;
                      let gesture = null;
                      let androidTouchScrollGesture = null;
                      let lastFocusAt = 0;
                      let suppressUntil = 0;
                      let suppressFocusUntil = 0;
                      const supportsPointerEvents = !!ownerWindow.PointerEvent;
                      const usePointerTapBridge = supportsPointerEvents && isAndroid;
                      const useTouchTapBridge = !usePointerTapBridge;
                      const useAndroidWebFocusGuard = usePointerTapBridge && isFlutterWebEmbed;
                      const now = () => Date.now();
                      const eventPoint = (event) => {
                        const touch =
                          event.changedTouches?.[0] || event.touches?.[0];
                        if (touch) {
                          return { x: touch.clientX, y: touch.clientY };
                        }
                        if (typeof event.clientX === 'number') {
                          return { x: event.clientX, y: event.clientY };
                        }
                        return null;
                      };
                      const getScrollSnapshot = () => {
                        try {
                          const ed = E();
                          if (!ed || !ed.getScrollTop || !ed.getScrollLeft) {
                            return { top: 0, left: 0 };
                          }
                          return {
                            top: ed.getScrollTop(),
                            left: ed.getScrollLeft(),
                          };
                        } catch (_) {
                          return { top: 0, left: 0 };
                        }
                      };
                      const hasMovedFromStart = (event) => {
                        if (!gesture) return false;
                        const point = eventPoint(event);
                        if (point) {
                          const dx = point.x - gesture.x;
                          const dy = point.y - gesture.y;
                          if ((dx * dx + dy * dy) > tapMoveThreshold * tapMoveThreshold) {
                            return true;
                          }
                        }
                        const scroll = getScrollSnapshot();
                        return Math.abs(scroll.top - gesture.scrollTop) > 0 ||
                          Math.abs(scroll.left - gesture.scrollLeft) > 0;
                      };
                      const hasTouchScrollMovedFromStart = (event) => {
                        if (!androidTouchScrollGesture) return false;
                        const point = eventPoint(event);
                        if (point) {
                          const dx = point.x - androidTouchScrollGesture.x;
                          const dy = point.y - androidTouchScrollGesture.y;
                          if ((dx * dx + dy * dy) > tapMoveThreshold * tapMoveThreshold) {
                            return true;
                          }
                        }
                        const scroll = getScrollSnapshot();
                        return Math.abs(scroll.top - androidTouchScrollGesture.scrollTop) > 0 ||
                          Math.abs(scroll.left - androidTouchScrollGesture.scrollLeft) > 0;
                      };
                      const blockEvent = (event) => {
                        try {
                          if (event.cancelable && event.preventDefault) {
                            event.preventDefault();
                          }
                        } catch (_) {}
                        try { event.stopImmediatePropagation && event.stopImmediatePropagation(); } catch (_) {}
                        try { event.stopPropagation && event.stopPropagation(); } catch (_) {}
                      };
                      const suppressCompatibilityEvents = () => {
                        suppressUntil = now() + compatibilityEventSuppressMs;
                      };
                      const suppressAndBlock = (event) => {
                        suppressCompatibilityEvents();
                        blockEvent(event);
                      };
                      const shouldBlockSuppressedEvent = () => now() < suppressUntil;
                      const blockSuppressedCompatibilityEvent = (event) => {
                        if (shouldBlockSuppressedEvent()) {
                          blockEvent(event);
                        }
                      };
                      const editorInputSelector =
                        'textarea.inputarea, .native-edit-context';
                      const isEditorInputElement = (element) => {
                        try {
                          return !!(
                            element &&
                            element.matches &&
                            element.matches(editorInputSelector)
                          );
                        } catch (_) {
                          return false;
                        }
                      };
                      const getEditorInputElement = () => {
                        try {
                          const active = ownerDocument.activeElement;
                          if (isEditorInputElement(active)) {
                            return active;
                          }
                          return node.querySelector(editorInputSelector);
                        } catch (_) {
                          return null;
                        }
                      };
                      const shouldSuppressFocus = () => now() < suppressFocusUntil;
                      let maxObservedViewportHeight = 0;
                      const getViewportHeightForKeyboard = () => {
                        const readHeight = (win) => {
                          try {
                            return win?.visualViewport?.height || win?.innerHeight || 0;
                          } catch (_) {
                            return 0;
                          }
                        };
                        let height = readHeight(ownerWindow);
                        try {
                          if (ownerWindow.parent && ownerWindow.parent !== ownerWindow) {
                            height = readHeight(ownerWindow.parent) || height;
                          }
                        } catch (_) {}
                        return height || 0;
                      };
                      const updateViewportKeyboardBaseline = () => {
                        const height = getViewportHeightForKeyboard();
                        if (height > maxObservedViewportHeight) {
                          maxObservedViewportHeight = height;
                        }
                        return height;
                      };
                      const isKeyboardLikelyVisible = () => {
                        const height = updateViewportKeyboardBaseline();
                        const baseline = maxObservedViewportHeight || height;
                        if (!height || !baseline) return false;
                        const hiddenHeight = baseline - height;
                        return hiddenHeight > Math.max(120, baseline * 0.18);
                      };
                      updateViewportKeyboardBaseline();
                      try {
                        ownerWindow.visualViewport?.addEventListener(
                          'resize',
                          updateViewportKeyboardBaseline,
                          { passive: true }
                        );
                      } catch (_) {}
                      try {
                        if (ownerWindow.parent && ownerWindow.parent !== ownerWindow) {
                          bindParentListener(
                            ownerWindow.parent.visualViewport,
                            'resize',
                            updateViewportKeyboardBaseline,
                            { passive: true }
                          );
                        }
                      } catch (_) {}
                      const blurTextAreaIfFocusSuppressed = () => {
                        if (!shouldSuppressFocus()) return;
                        try {
                          const input = getEditorInputElement();
                          if (input && ownerDocument.activeElement === input) {
                            input.blur();
                          }
                        } catch (_) {}
                      };
                      const scheduleSuppressedTextAreaBlur = () => {
                        blurTextAreaIfFocusSuppressed();
                        try { ownerWindow.setTimeout(blurTextAreaIfFocusSuppressed, 0); } catch (_) {}
                        try { ownerWindow.setTimeout(blurTextAreaIfFocusSuppressed, 50); } catch (_) {}
                      };
                      const suppressScrollFocusIfNeeded = () => {
                        if (!useAndroidWebFocusGuard) return;
                        suppressFocusUntil = now() + compatibilityEventSuppressMs;
                        const keyboardVisible = isKeyboardLikelyVisible();
                        if (!keyboardVisible) {
                          scheduleSuppressedTextAreaBlur();
                        }
                      };
                      const guardSuppressedTextAreaFocus = (event) => {
                        if (!useAndroidWebFocusGuard || !shouldSuppressFocus()) return;
                        const target = event?.target;
                        if (isEditorInputElement(target)) {
                          blurTextAreaIfFocusSuppressed();
                          blockEvent(event);
                        }
                      };
                      const beginGesture = (event, id, kind) => {
                        const point = eventPoint(event);
                        if (!point) return;
                        const scroll = getScrollSnapshot();
                        gesture = {
                          id,
                          kind,
                          x: point.x,
                          y: point.y,
                          startedAt: now(),
                          moved: false,
                          cancelled: false,
                          scrollTop: scroll.top,
                          scrollLeft: scroll.left,
                        };
                      };
                      const updateGesture = (event, id, kind) => {
                        if (!gesture || gesture.id !== id || gesture.kind !== kind) return;
                        if (hasMovedFromStart(event)) {
                          gesture.moved = true;
                          if (useAndroidWebFocusGuard) {
                            suppressCompatibilityEvents();
                            suppressScrollFocusIfNeeded();
                          }
                        }
                      };
                      const cancelGesture = (event, id, kind) => {
                        if (!gesture || gesture.id !== id || gesture.kind !== kind) return;
                        gesture.cancelled = true;
                        suppressScrollFocusIfNeeded();
                        suppressAndBlock(event);
                        gesture = null;
                      };
                      const endGesture = (event, id, kind) => {
                        if (!gesture || gesture.id !== id || gesture.kind !== kind) {
                          if (shouldBlockSuppressedEvent()) {
                            blockEvent(event);
                          }
                          return;
                        }
                        updateGesture(event, id, kind);
                        const elapsed = now() - gesture.startedAt;
                        const shouldFocus =
                          !gesture.cancelled &&
                          !gesture.moved &&
                          elapsed <= tapTimeThreshold;
                        gesture = null;
                        if (!shouldFocus) {
                          suppressScrollFocusIfNeeded();
                          suppressAndBlock(event);
                          return;
                        }
                        suppressUntil = 0;
                        suppressFocusUntil = 0;
                        const currentTime = now();
                        if (currentTime - lastFocusAt < 150) return;
                        lastFocusAt = currentTime;
                        focusEditorTextAreaNow();
                      };
                      const pointerId = (event) =>
                        typeof event.pointerId === 'number' ? event.pointerId : 1;
                      const onPointerDown = (event) => {
                        if (!event.isPrimary || event.pointerType !== 'touch') return;
                        beginGesture(event, pointerId(event), 'pointer');
                      };
                      const onPointerMove = (event) => {
                        if (!event.isPrimary || event.pointerType !== 'touch') return;
                        updateGesture(event, pointerId(event), 'pointer');
                      };
                      const onPointerUp = (event) => {
                        if (!event.isPrimary || event.pointerType !== 'touch') return;
                        endGesture(event, pointerId(event), 'pointer');
                      };
                      const onPointerCancel = (event) => {
                        if (!event.isPrimary || event.pointerType !== 'touch') return;
                        cancelGesture(event, pointerId(event), 'pointer');
                      };
                      const firstChangedTouch = (event) => event.changedTouches?.[0] || null;
                      const firstActiveTouch = (event) => event.touches?.[0] || null;
                      const onTouchStart = (event) => {
                        const touch = firstActiveTouch(event) || firstChangedTouch(event);
                        if (!touch) return;
                        beginGesture(event, touch.identifier, 'touch');
                      };
                      const onTouchMove = (event) => {
                        const touch = firstChangedTouch(event) || firstActiveTouch(event);
                        if (!touch) return;
                        updateGesture(event, touch.identifier, 'touch');
                      };
                      const onTouchEnd = (event) => {
                        const touch = firstChangedTouch(event);
                        if (!touch) return;
                        endGesture(event, touch.identifier, 'touch');
                      };
                      const onTouchCancel = (event) => {
                        const touch = firstChangedTouch(event);
                        if (!touch) return;
                        cancelGesture(event, touch.identifier, 'touch');
                      };
                      const beginAndroidTouchScrollGuard = (event) => {
                        if (!useAndroidWebFocusGuard) return;
                        const touch = firstActiveTouch(event) || firstChangedTouch(event);
                        if (!touch) return;
                        const point = eventPoint(event);
                        if (!point) return;
                        const scroll = getScrollSnapshot();
                        androidTouchScrollGesture = {
                          id: touch.identifier,
                          x: point.x,
                          y: point.y,
                          moved: false,
                          scrollTop: scroll.top,
                          scrollLeft: scroll.left,
                        };
                      };
                      const updateAndroidTouchScrollGuard = (event) => {
                        if (!useAndroidWebFocusGuard || !androidTouchScrollGesture) return;
                        if (hasTouchScrollMovedFromStart(event)) {
                          androidTouchScrollGesture.moved = true;
                          suppressCompatibilityEvents();
                          suppressScrollFocusIfNeeded();
                        }
                      };
                      const endAndroidTouchScrollGuard = (event) => {
                        if (!useAndroidWebFocusGuard) return;
                        if (!androidTouchScrollGesture) {
                          if (shouldBlockSuppressedEvent()) {
                            blockEvent(event);
                          }
                          return;
                        }
                        updateAndroidTouchScrollGuard(event);
                        const shouldBlock =
                          androidTouchScrollGesture.moved ||
                          shouldBlockSuppressedEvent();
                        androidTouchScrollGesture = null;
                        if (shouldBlock) {
                          blockEvent(event);
                        }
                      };
                      const cancelAndroidTouchScrollGuard = (event) => {
                        if (!useAndroidWebFocusGuard || !androidTouchScrollGesture) return;
                        suppressCompatibilityEvents();
                        suppressScrollFocusIfNeeded();
                        androidTouchScrollGesture = null;
                        blockEvent(event);
                      };
                      const capturePassiveFalse = { capture: true, passive: false };
                      const capturePassiveTrue = { capture: true, passive: true };
                      const captureOnly = { capture: true };

                      if (usePointerTapBridge) {
                        ownerDocument.addEventListener('pointerdown', onPointerDown, captureOnly);
                        ownerDocument.addEventListener('pointermove', onPointerMove, capturePassiveFalse);
                        ownerDocument.addEventListener('pointerup', onPointerUp, capturePassiveFalse);
                        ownerDocument.addEventListener('pointercancel', onPointerCancel, capturePassiveFalse);
                      }

                      if (useAndroidWebFocusGuard) {
                        ownerDocument.addEventListener('touchstart', beginAndroidTouchScrollGuard, capturePassiveTrue);
                        ownerDocument.addEventListener('touchmove', updateAndroidTouchScrollGuard, capturePassiveFalse);
                        ownerDocument.addEventListener('touchend', endAndroidTouchScrollGuard, capturePassiveFalse);
                        ownerDocument.addEventListener('touchcancel', cancelAndroidTouchScrollGuard, capturePassiveFalse);
                        ownerDocument.addEventListener('focus', guardSuppressedTextAreaFocus, captureOnly);
                        ownerDocument.addEventListener('focusin', guardSuppressedTextAreaFocus, captureOnly);
                      }

                      if (useTouchTapBridge) {
                        ownerDocument.addEventListener('touchstart', onTouchStart, capturePassiveTrue);
                        ownerDocument.addEventListener('touchmove', onTouchMove, capturePassiveFalse);
                        ownerDocument.addEventListener('touchend', onTouchEnd, capturePassiveFalse);
                        ownerDocument.addEventListener('touchcancel', onTouchCancel, capturePassiveFalse);
                      }

                      ownerDocument.addEventListener('mousedown', blockSuppressedCompatibilityEvent, captureOnly);
                      ownerDocument.addEventListener('mouseup', blockSuppressedCompatibilityEvent, captureOnly);
                      ownerDocument.addEventListener('click', blockSuppressedCompatibilityEvent, captureOnly);
                      try {
                        node.style.touchAction = node.style.touchAction || 'manipulation';
                      } catch (_) {}
                    }
                  } catch (_) {}
                }
};
