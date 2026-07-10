// flutter_monaco bridge - the scroll metrics, region filtering, and listener
// plumbing here are extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml); see upcoming/v3.md
// Section 14 (verbatim-port inventory). The gesture-ownership arbitration
// ("boundary lock", 3.4.0) intentionally diverges from the 2.3.0 forwarding
// behavior; the 2.3.0 semantics remain available as the 'continuous' policy.
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// Edge scroll handoff module, extended for diff pages:
// ctx.handoffScope (optional) widens the accepted wheel region to a set of
// editor DOM nodes under one region root, while ctx.E stays the vertical
// scroll master whose metrics gate the handoff. Without a scope the region
// is exactly the single editor.
window.__FMB.scrollHandoff = function (ctx) {
  const { E, post } = ctx;
  const handoffScope = ctx.handoffScope || null;
                // Edge scroll handoff (opt-in): forward scroll intent the
                // editor cannot consume to Flutter, which applies it to a
                // host scrollable. Sources are toggled from Dart through
                // flutterMonaco.setScrollHandoff; while disabled this module
                // installs no DOM listeners and adds no per-event work, so
                // the default editor behavior is untouched.
                //
                // Ownership model (policy 'newGestureOnly', the default):
                // the component that owns a scroll transaction when it
                // begins keeps it until that transaction ends. A gesture
                // that starts while the editor can scroll belongs to the
                // editor; when it reaches the scroll edge, its remaining
                // input - the whole inertial tail included - is absorbed at
                // the wall and never forwarded. Flutter receives only
                // transactions that START at the edge, as begin/update/end
                // sessions keyed by gestureId. Policy 'continuous' keeps
                // the 2.3.0 chaining: any delta the editor cannot consume
                // is forwarded immediately, with the legacy payload shape.
                (function () {
                  const EDGE_EPSILON = 1;
                  const TOUCH_SLOP = 8;
                  // Wheel events carry no transaction boundaries (beyond
                  // the Pointer Events level 4 'momentum' flag where a
                  // browser ships it), so gesture ends fall back to quiet
                  // periods: an editor-owned transaction expires after
                  // WHEEL_NORMAL_IDLE_MS without events; once a transaction
                  // has touched the boundary, the parent can be acquired
                  // only after WHEEL_BOUNDARY_QUIET_MS of silence. The
                  // re-arm window is the conservative one because a false
                  // "same gesture" merely delays host scrolling by about a
                  // quarter second, while a false "new gesture" jerks the
                  // host page - the exact bug this arbiter exists to stop.
                  const WHEEL_NORMAL_IDLE_MS = 120;
                  const WHEEL_BOUNDARY_QUIET_MS = 260;

                  const handoffState = {
                    wheel: false,
                    touch: false,
                    policy: 'newGestureOnly',
                    gestureSeq: 0,
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
                    if (!el || !el.closest) return false;
                    // Diff pages accept both panes under the diff container;
                    // single-editor pages keep the exact 2.3.0 region (the
                    // one editor's DOM).
                    const regionRoot = handoffScope && handoffScope.regionRoot
                      ? handoffScope.regionRoot()
                      : editorDom;
                    if (!regionRoot || !regionRoot.contains(el)) return false;
                    if (el.closest(HANDOFF_BLOCKED_WIDGETS)) return false;
                    const ownerDoms = handoffScope && handoffScope.editorDoms
                      ? handoffScope.editorDoms()
                      : [editorDom];
                    if (ownerDoms.indexOf(el.closest('.monaco-editor')) === -1) {
                      return false;
                    }
                    const scrollable = el.closest('.monaco-scrollable-element');
                    if (scrollable && !scrollable.classList.contains('editor-scrollable')) {
                      return false;
                    }
                    return true;
                  };

                  // Whether the editor itself can scroll in the requested
                  // vertical direction (wheel semantics: wantsDown scrolls
                  // the content down).
                  const canChildConsume = (ed, metrics, wantsDown) =>
                    !editorWheelDisabled(ed) &&
                    metrics.maxTop > EDGE_EPSILON &&
                    (wantsDown ? !metrics.atBottom : !metrics.atTop);

                  const blockLocal = (event) => {
                    if (event.cancelable !== false) event.preventDefault();
                    event.stopPropagation();
                  };

                  // Legacy payload, byte-compatible with 2.3.0: emitted only
                  // under policy 'continuous'.
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

                  // Sessionized payload for policy 'newGestureOnly'. The
                  // Dart driver applies updates only for the gestureId it
                  // saw begin, so stale or superseded deltas can never move
                  // the host.
                  const postSession = (source, phase, gestureId, deltaX, deltaY, metrics, momentum) => {
                    post('scrollHandoff', {
                      source: source,
                      phase: phase,
                      gestureId: gestureId,
                      momentum: !!momentum,
                      deltaX: deltaX,
                      deltaY: deltaY,
                      atTop: metrics.atTop,
                      atBottom: metrics.atBottom,
                      atLeft: metrics.atLeft,
                      atRight: metrics.atRight,
                    });
                  };
                  const NO_METRICS = Object.freeze({
                    atTop: false, atBottom: false, atLeft: false, atRight: false,
                  });

                  // ---- wheel transaction arbiter (policy newGestureOnly) --
                  // States: 'idle' (no transaction), 'child' (the editor
                  // owns it), 'locked' (an editor-owned transaction reached
                  // the wall; residual input is absorbed), 'parent' (it
                  // started at the wall; Flutter owns it, inertia included).
                  const wheelSession = {
                    owner: 'idle',
                    gestureId: 0,
                    direction: 0,
                    lastEventAt: -Infinity,
                    // Survives idle on purpose: the freshest editor-owned
                    // activity, used to keep the sparse end of an inertial
                    // tail from acquiring the parent after a boundary hit.
                    lastChildLikeAt: -Infinity,
                    lastChildLikeDir: 0,
                    sawMomentum: false,
                    lastMetrics: NO_METRICS,
                    endTimer: 0,
                  };

                  const noteChildLike = (now, dir) => {
                    wheelSession.lastChildLikeAt = now;
                    wheelSession.lastChildLikeDir = dir;
                  };

                  const finishWheelSession = (phase) => {
                    if (wheelSession.endTimer) {
                      clearTimeout(wheelSession.endTimer);
                      wheelSession.endTimer = 0;
                    }
                    if (wheelSession.owner === 'parent') {
                      postSession('wheel', phase, wheelSession.gestureId,
                        0, 0, wheelSession.lastMetrics, false);
                    }
                    wheelSession.owner = 'idle';
                    wheelSession.direction = 0;
                    wheelSession.sawMomentum = false;
                  };

                  const scheduleWheelFinish = () => {
                    if (wheelSession.endTimer) clearTimeout(wheelSession.endTimer);
                    const delay = wheelSession.owner === 'child'
                      ? WHEEL_NORMAL_IDLE_MS
                      : WHEEL_BOUNDARY_QUIET_MS;
                    wheelSession.endTimer = setTimeout(function () {
                      wheelSession.endTimer = 0;
                      finishWheelSession('end');
                    }, delay);
                  };

                  const arbitrateWheel = (event, ed, metrics, deltaX, deltaY) => {
                    const now = event.timeStamp;
                    const dir = deltaY > 0 ? 1 : -1;
                    const consumable = canChildConsume(ed, metrics, dir > 0);
                    const momentumKnown = 'momentum' in event;
                    const isMomentum = momentumKnown && event.momentum === true;
                    // With momentum metadata, the first direct event after
                    // an inertial tail is a new physical gesture even when
                    // it arrives with no time gap (fingers back on the pad).
                    const directAfterMomentum =
                      momentumKnown && wheelSession.sawMomentum && !isMomentum;
                    const sessionGapMs = wheelSession.owner === 'child'
                      ? WHEEL_NORMAL_IDLE_MS
                      : WHEEL_BOUNDARY_QUIET_MS;
                    const fresh =
                      wheelSession.owner === 'idle' ||
                      now - wheelSession.lastEventAt > sessionGapMs ||
                      directAfterMomentum;
                    wheelSession.lastEventAt = now;
                    wheelSession.lastMetrics = metrics;

                    if (fresh) {
                      finishWheelSession('end');
                      handoffState.gestureSeq += 1;
                      wheelSession.gestureId = handoffState.gestureSeq;
                      wheelSession.direction = dir;
                      wheelSession.sawMomentum = isMomentum;
                      if (consumable) {
                        // The editor can scroll: this transaction belongs to
                        // it. Monaco receives the event untouched (that
                        // includes a momentum tail resuming after a lull).
                        wheelSession.owner = 'child';
                        noteChildLike(now, dir);
                        scheduleWheelFinish();
                        return;
                      }
                      const recentlyChildLike =
                        !directAfterMomentum &&
                        dir === wheelSession.lastChildLikeDir &&
                        now - wheelSession.lastChildLikeAt < WHEEL_BOUNDARY_QUIET_MS;
                      if (isMomentum || recentlyChildLike) {
                        // Leftover kinetic energy: a tagged momentum event,
                        // or the detached tail of recent editor-owned
                        // activity in the same direction. Absorb it at the
                        // wall; it may never acquire the parent.
                        wheelSession.owner = 'locked';
                        noteChildLike(now, dir);
                        blockLocal(event);
                        scheduleWheelFinish();
                        return;
                      }
                      // A genuinely new gesture starting at the edge: the
                      // parent owns it until it ends or reverses back into
                      // the editor, its inertia included.
                      wheelSession.owner = 'parent';
                      blockLocal(event);
                      postSession('wheel', 'begin', wheelSession.gestureId,
                        deltaX, deltaY, metrics, isMomentum);
                      scheduleWheelFinish();
                      return;
                    }

                    // Continuing the active transaction.
                    wheelSession.sawMomentum = wheelSession.sawMomentum || isMomentum;
                    switch (wheelSession.owner) {
                      case 'child':
                        if (consumable) {
                          wheelSession.direction = dir;
                          noteChildLike(now, dir);
                          scheduleWheelFinish();
                          return; // Monaco consumes it, reversals included.
                        }
                        // The transaction began in the editor and just hit
                        // the wall: everything it has left is absorbed.
                        wheelSession.owner = 'locked';
                        wheelSession.direction = dir;
                        noteChildLike(now, dir);
                        blockLocal(event);
                        scheduleWheelFinish();
                        return;
                      case 'locked':
                        if (consumable) {
                          // Deliberate reversal back into content: the
                          // editor takes the transaction again.
                          wheelSession.owner = 'child';
                          wheelSession.direction = dir;
                          noteChildLike(now, dir);
                          scheduleWheelFinish();
                          return;
                        }
                        noteChildLike(now, dir);
                        blockLocal(event);
                        scheduleWheelFinish();
                        return;
                      case 'parent':
                        if (dir !== wheelSession.direction && consumable) {
                          // Reversal back into the editor never leaks: close
                          // the parent session, Monaco consumes this event.
                          finishWheelSession('end');
                          wheelSession.owner = 'child';
                          wheelSession.direction = dir;
                          wheelSession.sawMomentum = isMomentum;
                          noteChildLike(now, dir);
                          scheduleWheelFinish();
                          return;
                        }
                        wheelSession.direction = dir;
                        blockLocal(event);
                        postSession('wheel', 'update', wheelSession.gestureId,
                          deltaX, deltaY, metrics, isMomentum);
                        scheduleWheelFinish();
                        return;
                      default:
                        return;
                    }
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

                      if (handoffState.policy === 'continuous') {
                        // 2.3.0 chaining: forward whatever the editor cannot
                        // consume, immediately and unsessionized.
                        if (canChildConsume(ed, metrics, deltaY > 0)) return;
                        blockLocal(event);
                        postHandoff('wheel', deltaX, deltaY, metrics);
                        return;
                      }
                      arbitrateWheel(event, ed, metrics, deltaX, deltaY);
                    } catch (_) {}
                  };

                  // Touch forwarding is observation-only: passive listeners
                  // that never block, refocus, or select, so Monaco's touch
                  // handling and the mobile focus guards keep working exactly
                  // as before. Worst case is an extra parent scroll, never a
                  // broken editor gesture. Under policy 'newGestureOnly' the
                  // owner is decided once per touch gesture (its boundaries
                  // are explicit): a drag that starts over scrollable editor
                  // content is the editor's for its whole lifetime and is
                  // contained at the wall; only a drag that starts at an
                  // outward edge is forwarded, as one session.
                  const gestureTouch = (event) => {
                    const gesture = handoffState.touchGesture;
                    if (!gesture) return null;
                    const touches = event.changedTouches || [];
                    for (let i = 0; i < touches.length; i++) {
                      if (touches[i].identifier === gesture.id) return touches[i];
                    }
                    return null;
                  };
                  const finishTouchSession = (gesture, phase) => {
                    if (!gesture || gesture.owner !== 'parent' ||
                        !gesture.began || gesture.sessionClosed) {
                      return;
                    }
                    gesture.sessionClosed = true;
                    postSession('touch', phase, gesture.gestureId,
                      0, 0, gesture.lastMetrics || NO_METRICS, false);
                  };
                  const onHandoffTouchStart = (event) => {
                    try {
                      if (event.touches && event.touches.length > 1) {
                        finishTouchSession(handoffState.touchGesture, 'cancel');
                        handoffState.touchGesture = null;
                        return;
                      }
                      const touchPoint = (event.touches && event.touches[0]) ||
                        (event.changedTouches && event.changedTouches[0]);
                      if (!touchPoint) return;
                      const ed = E();
                      if (!ed || !isMainScrollRegion(ed, event.target)) {
                        finishTouchSession(handoffState.touchGesture, 'cancel');
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
                        // Ownership (policy newGestureOnly) is decided at
                        // the first vertical movement past the slop.
                        owner: null,
                        gestureId: 0,
                        began: false,
                        sessionClosed: false,
                        lastMetrics: null,
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

                      if (handoffState.policy === 'continuous') {
                        // 2.3.0 behavior: forward the moves the editor
                        // cannot consume, regardless of gesture history.
                        if (!editorCannotConsume) return;
                        postHandoff('touch', 0, deltaY, metrics);
                        return;
                      }

                      if (gesture.owner === null) {
                        // Direct-manipulation gestures never migrate between
                        // scrollables mid-flight: whoever can consume the
                        // first movement owns the whole drag.
                        gesture.owner = editorCannotConsume ? 'parent' : 'child';
                      }
                      // Containment: an editor-owned drag reaching the wall
                      // is absorbed (Monaco simply stops), never forwarded.
                      if (gesture.owner === 'child') return;
                      // Parent-owned: forward only what the editor cannot
                      // consume. This listener is passive, so a consumable
                      // reversal is Monaco's to apply; forwarding it too
                      // would scroll both surfaces at once.
                      if (!editorCannotConsume) return;
                      gesture.lastMetrics = metrics;
                      if (!gesture.began) {
                        gesture.began = true;
                        handoffState.gestureSeq += 1;
                        gesture.gestureId = handoffState.gestureSeq;
                        postSession('touch', 'begin', gesture.gestureId,
                          0, deltaY, metrics, false);
                        return;
                      }
                      postSession('touch', 'update', gesture.gestureId,
                        0, deltaY, metrics, false);
                    } catch (_) {}
                  };
                  const onHandoffTouchEnd = (event) => {
                    try {
                      if (gestureTouch(event)) {
                        finishTouchSession(handoffState.touchGesture, 'end');
                        handoffState.touchGesture = null;
                      }
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
                        // moved gesture stops forwarding for that gesture
                        // (and cancels its parent-owned session, so pending
                        // deltas are dropped host-side).
                        handoffState.touchSelectionWatch = ed.onDidChangeCursorSelection(() => {
                          const gesture = handoffState.touchGesture;
                          if (gesture && gesture.moved && !gesture.cancelled) {
                            gesture.cancelled = true;
                            finishTouchSession(gesture, 'cancel');
                          }
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
                    finishTouchSession(handoffState.touchGesture, 'cancel');
                    handoffState.touchGesture = null;
                  };

                  // Diff pages never run core.js, so the legacy namespace
                  // object may not exist yet.
                  window.flutterMonaco = window.flutterMonaco || {};
                  window.flutterMonaco.setScrollHandoff = function (cfg) {
                    const wheel = !!(cfg && cfg.wheel);
                    const touch = !!(cfg && cfg.touch);
                    if (cfg && typeof cfg.policy === 'string') {
                      // Only an explicit policy changes it; unknown names
                      // fall back to the default so a newer Dart side can
                      // never strand the page on 'continuous'.
                      const policy = cfg.policy === 'continuous'
                        ? 'continuous'
                        : 'newGestureOnly';
                      if (policy !== handoffState.policy) {
                        handoffState.policy = policy;
                        // Open sessions do not survive a semantics change.
                        finishWheelSession('cancel');
                        finishTouchSession(handoffState.touchGesture, 'cancel');
                        handoffState.touchGesture = null;
                      }
                    }
                    if (wheel !== handoffState.wheel) {
                      handoffState.wheel = wheel;
                      if (wheel) { installScrollHandoffWheel(); }
                      else {
                        removeScrollHandoffWheel();
                        finishWheelSession('cancel');
                      }
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
                  window.flutterMonaco.setScrollHandoff({
                    wheel: !!p.wheel,
                    touch: !!p.touch,
                    policy: typeof p.policy === 'string' ? p.policy : undefined,
                  }));
};
