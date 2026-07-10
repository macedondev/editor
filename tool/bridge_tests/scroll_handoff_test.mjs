// Executes the REAL scroll-handoff.js against a scripted wheel/touch event
// stream and a fake editor with live scroll metrics. These tests pin the
// gesture-ownership contract (boundary lock): a gesture that starts inside
// the editor is absorbed at the scroll edge, and only a physically new
// gesture that starts at the edge acquires the Flutter parent.
//
// Run: node --test tool/bridge_tests/scroll_handoff_test.mjs
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { createPage, dispatch, eventsNamed } from './harness.mjs';

/**
 * Builds an isolated page with scroll-handoff.js installed over a fake
 * editor. Wheel events are dispatched to the module's real listener; events
 * the module does not preventDefault are consumed by the fake editor the way
 * Monaco would (clamped to the scroll range).
 */
function createScrollPage({
  scrollTop = 0,
  scrollHeight = 1000,
  viewportHeight = 300,
  policy,
  touch = false,
} = {}) {
  const page = createPage();
  const { sandbox } = page;

  const listeners = new Map();
  sandbox.addEventListener = (type, fn) => {
    if (!listeners.has(type)) listeners.set(type, new Set());
    listeners.get(type).add(fn);
  };
  sandbox.removeEventListener = (type, fn) => {
    listeners.get(type)?.delete(fn);
  };

  // Deterministic timers: the arbiter's session-end timer never fires unless
  // a test explicitly elapses the quiet period.
  const timers = new Map();
  let timerSeq = 0;
  sandbox.setTimeout = (cb, delay) => {
    timerSeq += 1;
    timers.set(timerSeq, { cb, delay });
    return timerSeq;
  };
  sandbox.clearTimeout = (id) => {
    timers.delete(id);
  };

  // Just the EditorOption ids scroll-handoff.js reads.
  sandbox.monaco = {
    editor: { EditorOption: { lineHeight: 66, scrollbar: 102 } },
  };

  const editorState = {
    scrollTop,
    scrollHeight,
    viewportHeight,
    wheelDisabled: false,
  };
  const selectionHandlers = [];
  const scrollableEl = {
    classList: { contains: (name) => name === 'editor-scrollable' },
  };
  const editorDom = {
    nodeType: 1,
    contains: (el) => Boolean(el && el._insideEditor),
  };
  const editor = {
    getLayoutInfo: () => ({
      height: editorState.viewportHeight,
      width: 500,
    }),
    getScrollTop: () => editorState.scrollTop,
    getScrollLeft: () => 0,
    getScrollHeight: () => editorState.scrollHeight,
    getScrollWidth: () => 500,
    getDomNode: () => editorDom,
    getOption: (id) => {
      if (id === 66) return 20;
      if (id === 102) return { handleMouseWheel: !editorState.wheelDisabled };
      return undefined;
    },
    onDidChangeCursorSelection: (fn) => {
      selectionHandlers.push(fn);
      return { dispose() {} };
    },
  };
  const target = {
    nodeType: 1,
    _insideEditor: true,
    closest: (selector) => {
      if (selector === '.monaco-editor') return editorDom;
      if (selector === '.monaco-scrollable-element') return scrollableEl;
      return null;
    },
  };

  page.load('assets/monaco/bridge/scroll-handoff.js');
  const ctx = {
    E: () => editor,
    post: (name, data) => sandbox.FlutterMonaco.emit(name, data),
  };
  sandbox.__FMB.scrollHandoff(ctx);
  const cfg = { wheel: true, touch };
  if (policy !== undefined) cfg.policy = policy;
  sandbox.flutterMonaco.setScrollHandoff(cfg);

  const maxTop = () =>
    Math.max(0, editorState.scrollHeight - editorState.viewportHeight);

  let clock = 0;
  const dispatchTo = (type, ev) => {
    for (const fn of [...(listeners.get(type) || [])]) fn(ev);
    return ev;
  };
  const makeEvent = (type, { at, gap, cancelable = true, ...rest }) => {
    clock = at !== undefined ? at : clock + (gap !== undefined ? gap : 16);
    return {
      type,
      timeStamp: clock,
      cancelable,
      defaultPrevented: false,
      target,
      prevented: false,
      stopped: false,
      preventDefault() {
        this.defaultPrevented = true;
        this.prevented = true;
      },
      stopPropagation() {
        this.stopped = true;
      },
      ...rest,
    };
  };

  /** Dispatches one wheel event; unblocked events scroll the fake editor. */
  const wheel = ({
    deltaY,
    deltaX = 0,
    at,
    gap,
    momentum,
    ctrlKey = false,
    metaKey = false,
  }) => {
    const ev = makeEvent('wheel', {
      at,
      gap,
      deltaX,
      deltaY,
      deltaMode: 0,
      ctrlKey,
      metaKey,
    });
    if (momentum !== undefined) ev.momentum = momentum;
    dispatchTo('wheel', ev);
    if (!ev.prevented && !ctrlKey && !metaKey && !editorState.wheelDisabled) {
      editorState.scrollTop = Math.min(
        maxTop(),
        Math.max(0, editorState.scrollTop + deltaY),
      );
    }
    return ev;
  };

  const touchPoint = (id, clientY) => ({ identifier: id, clientX: 40, clientY });
  const touchStart = ({ y, id = 1, at, gap }) => {
    editorState._lastTouchY = y;
    return dispatchTo(
      'touchstart',
      makeEvent('touchstart', {
        at,
        gap,
        touches: [touchPoint(id, y)],
        changedTouches: [touchPoint(id, y)],
      }),
    );
  };
  /** One touch move; Monaco-style consumption for unforwarded drags. */
  const touchMove = ({ y, id = 1, at, gap, consume = true }) => {
    const ev = dispatchTo(
      'touchmove',
      makeEvent('touchmove', {
        at,
        gap,
        touches: [touchPoint(id, y)],
        changedTouches: [touchPoint(id, y)],
      }),
    );
    if (consume) {
      const dy = y - (editorState._lastTouchY ?? y);
      editorState.scrollTop = Math.min(
        maxTop(),
        Math.max(0, editorState.scrollTop - dy),
      );
    }
    editorState._lastTouchY = y;
    return ev;
  };
  const touchEnd = ({ id = 1, at, gap } = {}) => {
    editorState._lastTouchY = undefined;
    return dispatchTo(
      'touchend',
      makeEvent('touchend', {
        at,
        gap,
        touches: [],
        changedTouches: [touchPoint(id, 0)],
      }),
    );
  };

  const firePendingTimers = () => {
    const pending = [...timers.values()];
    timers.clear();
    for (const t of pending) t.cb();
  };
  const events = () => eventsNamed(page, 'scrollHandoff').map((m) => m.data);

  return {
    page,
    sandbox,
    editorState,
    selectionHandlers,
    wheel,
    touchStart,
    touchMove,
    touchEnd,
    firePendingTimers,
    events,
  };
}

// ---------------------------------------------------------------------------
// Wheel: boundary lock (policy default = newGestureOnly)
// ---------------------------------------------------------------------------

test('a gesture that starts inside the editor is absorbed at the edge', () => {
  const p = createScrollPage({ scrollTop: 400 }); // maxTop = 700
  const inMotion = [
    p.wheel({ deltaY: 120, at: 0 }),
    p.wheel({ deltaY: 120 }),
    p.wheel({ deltaY: 120 }), // crosses the edge: Monaco clamps, no spill
  ];
  const tail = [
    p.wheel({ deltaY: 120 }),
    p.wheel({ deltaY: 110 }),
    p.wheel({ deltaY: 90 }),
    p.wheel({ deltaY: 40 }),
  ];

  assert.equal(p.editorState.scrollTop, 700);
  for (const ev of inMotion) assert.equal(ev.prevented, false);
  // The wall: every residual event is cancelled and dropped.
  for (const ev of tail) assert.equal(ev.prevented, true);
  assert.deepEqual(p.events(), []);
});

test('a fresh gesture starting at the edge acquires the parent immediately', () => {
  const p = createScrollPage({ scrollTop: 700 });
  const first = p.wheel({ deltaY: 100, at: 1000 });
  const second = p.wheel({ deltaY: 90 });

  assert.equal(first.prevented, true);
  assert.equal(second.prevented, true);
  const posted = p.events();
  assert.equal(posted.length, 2);
  assert.equal(posted[0].phase, 'begin');
  assert.equal(posted[0].source, 'wheel');
  assert.equal(posted[0].deltaY, 100);
  assert.equal(posted[0].momentum, false);
  assert.equal(posted[0].atBottom, true);
  assert.equal(posted[1].phase, 'update');
  assert.equal(posted[1].deltaY, 90);
  assert.ok(posted[0].gestureId >= 1);
  assert.equal(posted[1].gestureId, posted[0].gestureId);
});

test('same-direction input shortly after a child tail stays absorbed; a distinct later gesture acquires the parent', () => {
  const p = createScrollPage({ scrollTop: 640 });
  p.wheel({ deltaY: 120, at: 0 }); // child, reaches 700
  p.wheel({ deltaY: 120, at: 16 }); // wall -> locked
  p.wheel({ deltaY: 120, at: 200 }); // 184ms gap: still the same transaction
  p.wheel({ deltaY: 120, at: 400 }); // 200ms gap: still absorbed
  assert.deepEqual(p.events(), []);

  const distinct = p.wheel({ deltaY: 120, at: 700 }); // 300ms of silence
  assert.equal(distinct.prevented, true);
  const posted = p.events();
  assert.equal(posted.length, 1);
  assert.equal(posted[0].phase, 'begin');
});

test('reversal while locked hands the event back to the editor', () => {
  const p = createScrollPage({ scrollTop: 640 });
  p.wheel({ deltaY: 120, at: 0 }); // child -> 700
  p.wheel({ deltaY: 120, at: 16 }); // locked
  const reversal = p.wheel({ deltaY: -120, at: 32 });

  assert.equal(reversal.prevented, false);
  assert.equal(p.editorState.scrollTop, 580);
  assert.deepEqual(p.events(), []);
});

test('a parent session ends after the quiet period', () => {
  const p = createScrollPage({ scrollTop: 700 });
  p.wheel({ deltaY: 100, at: 0 });
  p.firePendingTimers();

  const posted = p.events();
  assert.equal(posted.length, 2);
  assert.equal(posted[1].phase, 'end');
  assert.equal(posted[1].gestureId, posted[0].gestureId);
  assert.equal(posted[1].deltaY, 0);
});

test('parent reversal into consumable content ends the session and scrolls the editor', () => {
  const p = createScrollPage({ scrollTop: 700 });
  p.wheel({ deltaY: 100, at: 0 });
  const reversal = p.wheel({ deltaY: -100, at: 16 });

  assert.equal(reversal.prevented, false);
  assert.equal(p.editorState.scrollTop, 600);
  const posted = p.events();
  assert.equal(posted.length, 2);
  assert.equal(posted[0].phase, 'begin');
  assert.equal(posted[1].phase, 'end');
});

test('momentum metadata: inertia never acquires the parent, direct input after a tail does instantly', () => {
  const p = createScrollPage({ scrollTop: 640 });
  p.wheel({ deltaY: 120, at: 0, momentum: false }); // child -> 700
  p.wheel({ deltaY: 120, at: 16, momentum: true }); // wall inside the tail
  p.wheel({ deltaY: 120, at: 32, momentum: true }); // absorbed
  assert.deepEqual(p.events(), []);

  // Fingers back on the trackpad while the old tail still streams: a direct
  // event is a new physical gesture and may take the parent with no wait.
  const direct = p.wheel({ deltaY: 120, at: 48, momentum: false });
  assert.equal(direct.prevented, true);
  const posted = p.events();
  assert.equal(posted.length, 1);
  assert.equal(posted[0].phase, 'begin');
});

test('an isolated momentum event at the edge is absorbed, never forwarded', () => {
  const p = createScrollPage({ scrollTop: 700 });
  const ev = p.wheel({ deltaY: 80, at: 0, momentum: true });

  assert.equal(ev.prevented, true);
  assert.deepEqual(p.events(), []);
});

test('non-scrollable document: fresh direct gestures go to the parent, isolated momentum does not', () => {
  const p = createScrollPage({ scrollHeight: 200 }); // maxTop = 0
  const direct = p.wheel({ deltaY: 50, at: 0 });
  assert.equal(direct.prevented, true);
  assert.equal(p.events().length, 1);
  assert.equal(p.events()[0].phase, 'begin');

  const q = createScrollPage({ scrollHeight: 200 });
  const inertial = q.wheel({ deltaY: 50, at: 0, momentum: true });
  assert.equal(inertial.prevented, true);
  assert.deepEqual(q.events(), []);
});

test('continuous policy keeps 2.3.0 chaining and the legacy payload shape', () => {
  const p = createScrollPage({ scrollTop: 640, policy: 'continuous' });
  const consumed = p.wheel({ deltaY: 120, at: 0 }); // editor scrolls to 700
  const spill1 = p.wheel({ deltaY: 120, at: 16 });
  const spill2 = p.wheel({ deltaY: 120, at: 32 }); // same-gesture inertia leaks

  assert.equal(consumed.prevented, false);
  assert.equal(spill1.prevented, true);
  assert.equal(spill2.prevented, true);
  const posted = p.events();
  assert.equal(posted.length, 2);
  for (const payload of posted) {
    assert.equal(payload.source, 'wheel');
    assert.equal(payload.deltaY, 120);
    assert.equal('phase' in payload, false);
    assert.equal('gestureId' in payload, false);
    assert.equal('momentum' in payload, false);
  }
});

test('the policy also arrives through the page.setScrollHandoff command', async () => {
  const p = createScrollPage({ scrollTop: 640 });
  await dispatch(p.page, 'page.setScrollHandoff', {
    wheel: true,
    touch: false,
    policy: 'continuous',
  });
  p.wheel({ deltaY: 120, at: 0 }); // child consumes to the edge
  p.wheel({ deltaY: 120, at: 16 }); // continuous: spills immediately

  const posted = p.events();
  assert.equal(posted.length, 1);
  assert.equal('phase' in posted[0], false);
});

test('disabling the wheel source mid-parent-session cancels it', () => {
  const p = createScrollPage({ scrollTop: 700 });
  p.wheel({ deltaY: 100, at: 0 });
  p.sandbox.flutterMonaco.setScrollHandoff({ wheel: false });

  const posted = p.events();
  assert.equal(posted.length, 2);
  assert.equal(posted[1].phase, 'cancel');
  assert.equal(posted[1].gestureId, posted[0].gestureId);

  const after = p.wheel({ deltaY: 100, at: 16 });
  assert.equal(after.prevented, false);
  assert.equal(p.events().length, 2);
});

test('ctrl/meta wheel input is never arbitrated', () => {
  const p = createScrollPage({ scrollTop: 700 });
  const zoom = p.wheel({ deltaY: 100, at: 0, ctrlKey: true });

  assert.equal(zoom.prevented, false);
  assert.deepEqual(p.events(), []);
});

// ---------------------------------------------------------------------------
// Touch ownership (policy default = newGestureOnly)
// ---------------------------------------------------------------------------

test('touch: a drag that starts over scrollable content never forwards, even past the edge', () => {
  const p = createScrollPage({ scrollTop: 600, touch: true });
  p.touchStart({ y: 300, at: 0 });
  p.touchMove({ y: 280, at: 16 }); // slop exceeded, editor scrolls (owner: child)
  p.touchMove({ y: 200, at: 32 }); // editor reaches 700
  p.touchMove({ y: 120, at: 48 }); // at the wall: absorbed, not forwarded
  p.touchMove({ y: 60, at: 64 });
  p.touchEnd({ at: 80 });

  assert.equal(p.editorState.scrollTop, 700);
  assert.deepEqual(p.events(), []);
});

test('touch: a drag that starts at the edge is parent-owned for its whole lifetime', () => {
  const p = createScrollPage({ scrollTop: 700, touch: true });
  p.touchStart({ y: 300, at: 0 });
  p.touchMove({ y: 280, at: 16, consume: false }); // outward at the edge
  p.touchMove({ y: 240, at: 32, consume: false });
  p.touchEnd({ at: 48 });

  const posted = p.events();
  assert.equal(posted.length, 3);
  assert.equal(posted[0].phase, 'begin');
  assert.equal(posted[0].source, 'touch');
  assert.equal(posted[0].deltaY, 20);
  assert.equal(posted[1].phase, 'update');
  assert.equal(posted[1].deltaY, 40);
  assert.equal(posted[2].phase, 'end');
  assert.equal(
    new Set(posted.map((payload) => payload.gestureId)).size,
    1,
  );
});

test('touch: a selection change cancels a parent-owned drag', () => {
  const p = createScrollPage({ scrollTop: 700, touch: true });
  p.touchStart({ y: 300, at: 0 });
  p.touchMove({ y: 280, at: 16, consume: false });
  for (const fn of p.selectionHandlers) fn();
  p.touchMove({ y: 240, at: 32, consume: false });
  p.touchEnd({ at: 48 });

  const posted = p.events();
  assert.equal(posted.length, 2);
  assert.equal(posted[0].phase, 'begin');
  assert.equal(posted[1].phase, 'cancel');
});

test('touch: continuous policy keeps the per-move legacy behavior', () => {
  const p = createScrollPage({
    scrollTop: 600,
    touch: true,
    policy: 'continuous',
  });
  p.touchStart({ y: 300, at: 0 });
  p.touchMove({ y: 280, at: 16 }); // consumable: not forwarded
  p.touchMove({ y: 180, at: 32 }); // editor clamps at 700
  p.touchMove({ y: 100, at: 48 }); // at the edge: legacy spill
  p.touchEnd({ at: 64 });

  const posted = p.events();
  assert.equal(posted.length, 1);
  assert.equal(posted[0].source, 'touch');
  assert.equal(posted[0].deltaY, 80);
  assert.equal('phase' in posted[0], false);
});
