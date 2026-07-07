// flutter_monaco bridge - protocol v3 envelope plus shared infrastructure.
// Ported bodies (parent-binding lifecycle) come verbatim from the 2.3.0
// generated page; see upcoming/v3.md Sections 6 and 14.
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// ---------------------------------------------------------------------------
// FlutterMonaco: the single wire protocol between this page and Dart.
//
// Every JS -> Dart message is one JSON envelope:
//   { v: 3, kind: 'lifecycle'|'response'|'event'|'request'|'log', ... }
// Dart -> JS calls arrive exclusively as FlutterMonaco.dispatch({id, method,
// params}) and FlutterMonaco.respond({id, ok, value|error}) scripts. Commands
// are registered into a flat dotted-name registry; synchronous and async
// (promise-returning) commands are indistinguishable to Dart because dispatch
// funnels both through Promise.resolve and always posts exactly one response.
// ---------------------------------------------------------------------------
(function () {
  var PROTOCOL_VERSION = 3;
  var page = window.__FM_PAGE || {};
  var eventSeq = 0;
  var registry = Object.create(null);
  var pendingRequests = Object.create(null);
  var requestSeq = 0;

  var postToFlutter = function (envelope) {
    envelope.v = PROTOCOL_VERSION;
    // Web token stamping: the host page ignores iframe messages without the
    // token it minted for this editor instance (anti-spoofing, issue #10).
    var token = page.token || window.flutterMonacoToken || '';
    if (token) envelope._flutterToken = token;
    var json;
    try {
      json = JSON.stringify(envelope);
    } catch (e) {
      json = JSON.stringify({
        v: PROTOCOL_VERSION,
        kind: 'log',
        level: 'error',
        message: 'Unserializable envelope for kind ' + envelope.kind + ': ' + e,
      });
    }
    if (window.flutterChannel && window.flutterChannel.postMessage) {
      window.flutterChannel.postMessage(json);
    } else {
      console.error('[Monaco] Flutter communication channel is not available.');
    }
  };

  var errorPayload = function (e) {
    return {
      name: e && e.name ? String(e.name) : 'Error',
      message: e && e.message ? String(e.message) : String(e),
      stack: e && e.stack ? String(e.stack) : null,
    };
  };

  window.FlutterMonaco = {
    PROTOCOL_VERSION: PROTOCOL_VERSION,

    /// Registers the implementation of a dotted command name.
    register: function (name, fn) {
      registry[name] = fn;
    },

    /// Dart -> JS command call. Always posts exactly one response for id.
    dispatch: function (call) {
      var id = call && call.id;
      var method = call && call.method;
      var params = (call && call.params) || {};
      var result;
      try {
        var fn = registry[method];
        if (typeof fn !== 'function') {
          throw new Error('Unknown method: ' + method);
        }
        result = Promise.resolve(fn(params));
      } catch (e) {
        result = Promise.reject(e);
      }
      result.then(
        function (value) {
          postToFlutter({
            kind: 'response',
            id: id,
            ok: true,
            undefined: typeof value === 'undefined',
            value: typeof value === 'undefined' ? null : value,
          });
        },
        function (e) {
          console.error('[FlutterMonaco] dispatch failed:', method, e);
          postToFlutter({
            kind: 'response',
            id: id,
            ok: false,
            error: errorPayload(e),
          });
        }
      );
    },

    /// JS -> Dart request (completion provider, custom action run). Returns
    /// a promise that Dart settles via FlutterMonaco.respond.
    request: function (name, data) {
      var id = 'q' + (++requestSeq);
      return new Promise(function (resolve, reject) {
        pendingRequests[id] = { resolve: resolve, reject: reject };
        postToFlutter({ kind: 'request', id: id, name: name, data: data || {} });
      });
    },

    /// Dart's answer to a request. A late respond for a dead id is a no-op.
    respond: function (payload) {
      var pending = pendingRequests[payload && payload.id];
      if (!pending) return;
      delete pendingRequests[payload.id];
      if (payload.ok) {
        pending.resolve(payload.value);
      } else {
        pending.reject(new Error((payload.error && payload.error.message) || 'Request failed'));
      }
    },

    /// Drops a pending request without settling Dart's view of it (used by
    /// cancellation paths that already resolved locally).
    dropRequest: function (id) {
      delete pendingRequests[id];
    },

    /// Editor event. seq is monotonically increasing per page; Dart asserts
    /// monotonicity in debug builds to catch dropped or reordered messages.
    emit: function (name, data) {
      postToFlutter({ kind: 'event', seq: ++eventSeq, name: name, data: data || {} });
    },

    log: function (level, message) {
      postToFlutter({ kind: 'log', level: level, message: String(message) });
    },

    lifecycle: function (name, extra) {
      var envelope = { kind: 'lifecycle', name: name };
      if (extra) {
        for (var key in extra) {
          if (Object.prototype.hasOwnProperty.call(extra, key)) {
            envelope[key] = extra[key];
          }
        }
      }
      postToFlutter(envelope);
    },
  };

  // Evaluate an arbitrary expression in global scope (the Dart
  // evaluateJavaScript escape hatch). Indirect eval keeps globals reachable.
  window.FlutterMonaco.register('page.eval', function (params) {
    return (0, eval)(params.expression);
  });

  // The page shell announces readiness only once EVERY bridge module has
  // registered its commands - boot.js, the last bridge script, calls this.
  // Posting pageReady here at core.js parse time would let Dart dispatch
  // page.boot into a half-parsed page (the later bridge files still travel
  // over HTTP on web) and fail with "Unknown method". The editor itself
  // reports readiness separately (lifecycle 'ready').
  window.FlutterMonaco.announcePageReady = function () {
    window.FlutterMonaco.lifecycle('pageReady', {
      protocolVersion: PROTOCOL_VERSION,
      monacoVersion: page.monacoVersion || null,
      capabilities: ['lsp'],
    });
  };
})();

// Shared bridge infrastructure: editor accessor, mobile detection,
// parent-binding lifecycle, and the event poster (post -> FlutterMonaco.emit).
window.__FMB.core = function (ctx) {
                const E = () => window.editor;
                const isMobileInputPlatform = () => {
                  const ua = navigator.userAgent || '';
                  return /Android|iPhone|iPad|iPod/i.test(ua) ||
                    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
                };
                // Listeners this document registers on PARENT window objects
                // (the Flutter host page) outlive it when the host removes
                // the iframe element: removal discards the browsing context
                // WITHOUT firing pagehide, so the parent-side EventTarget
                // keeps the handler - and the handler roots this whole
                // document plus its Monaco instance - indefinitely. Every
                // parent-side registration therefore goes through this
                // helper: the wrapper drops itself on the first event after
                // the frame leaves the parent DOM, pagehide detaches
                // everything on in-place navigation (the load-retry path),
                // and the Dart controller calls
                // __flutterMonacoDetachParentBindings from dispose() so
                // cleanup does not wait for the next parent viewport event.
                const parentBindings = [];
                const bindParentListener = (target, type, handler, options) => {
                  if (!target) return;
                  const unbind = () => {
                    try { target.removeEventListener(type, wrapped, options); } catch (_) {}
                  };
                  const wrapped = (event) => {
                    const frame = window.frameElement;
                    if (!frame || !frame.isConnected) {
                      unbind();
                      return;
                    }
                    handler(event);
                  };
                  try {
                    target.addEventListener(type, wrapped, options);
                    parentBindings.push(unbind);
                  } catch (_) {}
                };
                window.__flutterMonacoDetachParentBindings = () => {
                  while (parentBindings.length) {
                    const unbind = parentBindings.pop();
                    try { unbind(); } catch (_) {}
                  }
                };
                window.addEventListener('pagehide', window.__flutterMonacoDetachParentBindings, { once: true });
                const serialize = (obj) => JSON.stringify(obj);

                // Legacy-shaped poster: ported modules call
                // postMessageToFlutter({ event, ...payload }) / post(event,
                // payload); both now ride the v3 event envelope so their
                // bodies stay verbatim while the wire is uniform.
                const postMessageToFlutter = (message) => {
                  if (message && typeof message === 'object' &&
                      typeof message.event === 'string') {
                    const data = Object.assign({}, message);
                    delete data.event;
                    window.FlutterMonaco.emit(message.event, data);
                    return;
                  }
                  window.FlutterMonaco.log(
                    'info',
                    typeof message === 'string' ? message : JSON.stringify(message));
                };
                // Events -> Flutter
                const post = (event, payload) =>
                  postMessageToFlutter({ event, ...payload });

  ctx.E = E;
  ctx.isMobileInputPlatform = isMobileInputPlatform;
  ctx.bindParentListener = bindParentListener;
  ctx.serialize = serialize;
  ctx.post = post;
  ctx.postMessageToFlutter = postMessageToFlutter;
};
