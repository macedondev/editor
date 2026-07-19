# Bridge contract map

## Ownership path

1. Public types and controller/document methods in `lib/src/` define the supported Dart API.
2. `lib/src/protocol/` owns envelopes, correlation, handshakes, event ordering, readiness, reload, and pending request settlement.
3. `lib/src/platform/` carries the same serialized channel across native WebViews and Web iframe messaging.
4. `assets/monaco/bridge/core.js` owns registration and dispatch; feature modules own Monaco calls.
5. Tests and fakes prove both Dart contract coverage and real JavaScript semantics.

Do not shortcut this path with a one-platform callback or special decoder.

## Bridge modules

| File | Concern |
| --- | --- |
| `core.js` | envelope, handler registry, response/event plumbing |
| `boot.js` | final boot registration and editor creation |
| `editor-api.js` | editor/document commands and typed payloads |
| `diff-api.js` | diff editor commands |
| `focus.js` | DOM focus coordination |
| `lsp.js` | language client transports and lifecycle |
| `scroll-handoff.js` | wheel/touch boundary events |
| `viewport-fit.js` | mobile viewport behavior |

The generated HTML must reference every module and load `boot.js` last.

## Adding a command

1. Define the Dart method and public value types.
2. Reuse `MonacoProtocol.invoke` and choose an operation id consistent with the existing namespace.
3. Register the exact id in the owning bridge module.
4. Validate required arguments in JavaScript and return a JSON-safe value.
5. Decode the result explicitly in Dart. Reject wrong types with `MonacoProtocolError` naming the operation.
6. Update the fake platform controller so controller-level tests can prove behavior without a WebView.
7. Add the operation to contract fixtures. The bijection test must remain green.
8. Add a Node test when JavaScript behavior is more than a trivial forwarding call.

## Adding an event or capability

Events must carry ordered sequence metadata through the one envelope channel. Add a typed event when the app-facing meaning is stable; preserve unknown events for forward compatibility. Capability strings are additive and available through `MonacoCapabilities.raw`/`supports` even before a typed convenience field exists.

## Errors and lifecycle

Keep these categories distinct: timeout, JavaScript failure, protocol shape/version failure, disposed controller, page reload interruption, and asset/boot failure. Never translate them to `null`, empty text, `false`, or zero.

Test commands before readiness, during reload, after failed boot, and after dispose when the operation can race lifecycle changes.

## Review checklist

- Public API and barrel export intentional
- One command/event id and one envelope channel
- JSON-safe payload and strict result decoder
- Exact fake and fixture coverage
- Real bridge module loaded in generated HTML
- Node semantic coverage for nontrivial JavaScript
- Typed error, timeout, reload, and disposal semantics
- Protocol version decision documented
- Analyzer, Dart tests, and Node tests pass
