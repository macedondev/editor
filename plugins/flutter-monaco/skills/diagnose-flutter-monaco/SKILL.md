---
name: diagnose-flutter-monaco
description: Diagnose unknown or cross-layer flutter_monaco failures involving boot, assets, Web mounting, protocol, focus, overlays, page reload, LSP, or scroll handoff. Use when the failing layer is not yet established, an editor is blank or loses input, or a MonacoException crosses boundaries. Route an already-localized LSP transport, CSP, URI, or lifecycle problem to configure-flutter-monaco-lsp. Do not use for a routine integration with no failure.
---

# Diagnose Flutter Monaco

Find the failing layer before proposing a fix. Read the exact package version, platform, exception type/message/operation, lifecycle order, and relevant app code. Treat logs and external reviews as hypotheses.

Read [references/diagnostic-matrix.md](references/diagnostic-matrix.md) and select the narrowest matching path.

## Method

1. Reproduce the smallest failure and record package version, Flutter version, platform, first failure, and whether it survives a route/app lifecycle event.
2. Classify the boundary: assets/page creation, platform view mount, protocol handshake/command, document model, focus, overlay hit testing, LSP, reload recovery, or scroll ownership.
3. Inspect the actual source and tests for that boundary. Do not bypass typed APIs with JavaScript before proving the public API is insufficient.
4. Add one observation that separates competing causes. Examples include `MonacoAssets.assetInfo()`, `controller.capabilities`, `hasNativeInputFocus`, browser CSP output, connection state, or a focused fake-protocol test.
5. If the request authorizes a fix, implement the smallest root-cause correction and add a regression test at the ownership boundary. For a diagnosis-only request, stop after the evidence-backed cause and recommended correction.
6. When code changed, re-run the exact reproduction plus analyzer and relevant tests.

## Guardrails

- A self-created controller on Web must be mounted and painted before `whenReady` can finish. A timeout after conditional mounting is a lifecycle defect, not a slow command.
- `onFocusChanged == true` means Monaco's DOM has focus. It does not prove the native WebView has keyboard input focus.
- Request focus when entering or recovering the editor. Do not replay focus on every click or selection event; that can steal focus and create loops.
- A visible Flutter overlay above a Web iframe is not necessarily clickable. Classify it as route, static, or transient and use the matching package primitive.
- Preserve the first typed `MonacoException`. Do not turn an asset, reload, or protocol error into an empty document/default value.
- On page reload, the controller restores the boot editor and registered completions/actions, but the app must restore extra documents, post-boot configuration, and LSP connections.
- Verify against the installed version. The 2.x focus and content APIs are not valid names in 3.x.

## Output

Report evidence in this order: symptom, failing layer, proof, root cause, fix, regression coverage, and remaining platform uncertainty. If reproduction needs credentials, a device, a server binary, or a missing route, stop at the proven boundary and name the missing input rather than guessing.
