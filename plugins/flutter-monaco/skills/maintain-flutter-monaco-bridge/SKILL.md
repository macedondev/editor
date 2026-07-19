---
name: maintain-flutter-monaco-bridge
description: Change or review flutter_monaco's internal Dart-to-JavaScript bridge, command/event envelopes, generated page, platform WebView adapters, or typed public wrappers. Use inside the flutter_monaco package when adding a command, event, capability, bridge module, or protocol behavior. Do not use for ordinary consuming-app integration or arbitrary JavaScript escape-hatch code.
---

# Maintain Flutter Monaco Bridge

Preserve one cross-platform contract from the typed Dart API to real JavaScript bridge assets. Read the current command/event implementation, fixtures, fakes, and tests before editing. Use the read-only `bridge-contract-reviewer` agent for a second pass when available; this skill remains the canonical procedure.

Read [references/bridge-contract.md](references/bridge-contract.md) before changing code.

## Workflow

1. State the public behavior, payload, result, error, and lifecycle semantics before choosing files.
2. Trace the existing path end to end: public Dart API, wire model/codec, `MonacoProtocol`, platform transport, bridge registration, Monaco API, response/event, Dart decoding.
3. Change the smallest owning layers. Avoid platform-specific result decoding or a parallel message channel.
4. Update every contract surface: typed models, fakes, bridge fixtures, structural tests, Node semantic tests, exports/docs, and protocol version only when required.
5. Test failure, disposal, readiness, and page reload behavior, not only the happy command result.
6. Run Dart contract tests and the real bridge JavaScript Node harness.

## Contract rules

- All commands and events use the versioned request-correlated envelope channel.
- Bridge JavaScript lives in `assets/monaco/bridge/*.js`; do not embed it as Dart strings.
- Boot stays last in the generated bridge script order so all handlers exist before boot dispatch.
- Decode and validate untrusted JS shapes at the repository boundary. Throw a typed `MonacoProtocolError` for contract violations.
- Do not return silent defaults for transport, JavaScript, or decoding failures.
- Commands issued before editor readiness retain FIFO semantics through the existing gate.
- Disposal must settle pending work. Page reload must either replay owned state or fail stale work immediately with the typed reload error.
- Unknown forward-compatible events stay observable as `MonacoUnknownEvent`.
- Bump `kMonacoProtocolVersion` only for an incompatible wire contract. A new optional command/capability normally does not require a bump.

## Stop conditions

- If the intended public behavior, request payload, response shape, or failure semantics cannot be established from source and the request, stop and ask for that contract before editing.
- If a change depends on unavailable generated assets or platform infrastructure, report the verified boundary and do not claim cross-platform completion.

## Verification

At minimum run:

```sh
flutter test test/protocol test/assets/bridge_files_test.dart
node --test tool/bridge_tests/*_test.mjs
dart analyze
```

Add focused controller/document/diff/LSP tests for the changed API. Verify every registered bridge command has a contract fixture and every fixture has a registration. Report the complete request and response path, error behavior, reload/disposal behavior, and tests that execute the real JavaScript.
