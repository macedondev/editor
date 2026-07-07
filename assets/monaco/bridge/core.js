// flutter_monaco bridge - extracted verbatim from the 2.3.0 generated page
// (lib/src/core/monaco_assets.dart generateIndexHtml). Do not reformat the
// ported bodies; see upcoming/v3.md Section 14 (verbatim-port inventory).
/* eslint-disable */
'use strict';
window.__FMB = window.__FMB || {};

// Shared bridge infrastructure: editor accessor, mobile detection,
// parent-binding lifecycle, event poster, and the flutterMonacoInvoke /
// flutterMonacoInvokeAsync envelopes.
window.__FMB.core = function (ctx) {
  const { postMessageToFlutter } = ctx;
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
                // Events -> Flutter
                const post = (event, payload) =>
                  postMessageToFlutter({ event, ...payload });

                // Bridge dispatcher with a result envelope.
                //
                // Dart-side _invokeMonacoCommand calls this so that any
                // JavaScript error inside a flutterMonaco helper is captured
                // as a structured failure instead of crossing the WebView
                // boundary as an uncaught exception.
                //
                // Success: { __flutterMonacoEval: true, ok: true, isUndefined, value }
                // Failure: { __flutterMonacoEval: true, ok: false, error: { name, message, stack } }
                window.flutterMonacoInvoke = (method, args) => {
                  try {
                    const api = window.flutterMonaco;
                    const fn = api && api[method];
                    if (typeof fn !== 'function') {
                      throw new Error('Unknown flutterMonaco method: ' + method);
                    }
                    const value = fn.apply(api, Array.isArray(args) ? args : []);
                    return {
                      __flutterMonacoEval: true,
                      ok: true,
                      isUndefined: typeof value === 'undefined',
                      value: typeof value === 'undefined' ? null : value,
                    };
                  } catch (e) {
                    console.error('[flutterMonaco] invoke failed:', method, e);
                    return {
                      __flutterMonacoEval: true,
                      ok: false,
                      error: {
                        name: e && e.name ? String(e.name) : 'Error',
                        message: e && e.message ? String(e.message) : String(e),
                        stack: e && e.stack ? String(e.stack) : null,
                      },
                    };
                  }
                };

                // Async bridge dispatcher.
                //
                // flutterMonacoInvoke returns synchronously, which cannot
                // represent promise-returning helpers (LSP connect must await
                // the initialize handshake). This variant resolves the method
                // (dotted paths reach sub-namespaces like 'lsp.connect'),
                // awaits the result, and reports back over flutterChannel as
                // an 'invokeResult' event that Dart correlates by requestId.
                // This behaves identically on Android, iOS, macOS, Windows,
                // and Web because no platform has to unwrap a JS Promise.
                window.flutterMonacoInvokeAsync = (requestId, method, args) => {
                  const respond = (payload) => {
                    postMessageToFlutter(Object.assign(
                      { event: 'invokeResult', requestId: requestId }, payload));
                  };
                  Promise.resolve()
                    .then(() => {
                      let parent = null;
                      let target = window.flutterMonaco;
                      for (const part of String(method).split('.')) {
                        parent = target;
                        target = target ? target[part] : undefined;
                      }
                      if (typeof target !== 'function') {
                        throw new Error('Unknown flutterMonaco method: ' + method);
                      }
                      return target.apply(parent, Array.isArray(args) ? args : []);
                    })
                    .then((value) => respond({
                      ok: true,
                      isUndefined: typeof value === 'undefined',
                      value: typeof value === 'undefined' ? null : value,
                    }))
                    .catch((e) => {
                      console.error('[flutterMonaco] async invoke failed:', method, e);
                      respond({
                        ok: false,
                        error: {
                          name: e && e.name ? String(e.name) : 'Error',
                          message: e && e.message ? String(e.message) : String(e),
                          stack: e && e.stack ? String(e.stack) : null,
                        },
                      });
                    });
                  return true;
                };
  ctx.E = E;
  ctx.isMobileInputPlatform = isMobileInputPlatform;
  ctx.bindParentListener = bindParentListener;
  ctx.serialize = serialize;
  ctx.post = post;
};
