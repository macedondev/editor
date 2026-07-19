---
name: integrate-flutter-monaco
description: Integrate flutter_monaco 3.x into a Flutter application, including editor lifecycle, documents, platform setup, focus, overlays, and disposal. Use when adding MonacoEditor or MonacoController, designing an editor screen, or reviewing a new flutter_monaco integration. Do not use for a 2.x migration, LSP-only work, package bridge maintenance, or a bundled Monaco engine upgrade.
---

# Integrate Flutter Monaco

Build the integration against the installed package version and its public API. Read `pubspec.yaml`, `pubspec.lock`, the consuming screen, and the current `flutter_monaco` README before changing code. Never invent a bridge method or copy a 2.x example into a 3.x app.

Read [references/integration-patterns.md](references/integration-patterns.md) before implementation.

## Workflow

1. Confirm the dependency version and target platforms. Flutter Monaco 3.x supports Android 7/API 24+, iOS 13+, macOS 10.15+, Windows, and Web. Linux is unsupported.
2. Choose ownership deliberately:
   - Prefer `MonacoEditor` for a screen that wants widget-owned creation, loading, errors, and disposal.
   - Create a `MonacoController` when the app must prepare, share, or coordinate the controller outside the widget.
3. Define content ownership. Use `initialText` only for boot content. After readiness, content belongs to `controller.document`; multi-file apps should open documents with stable `file:///` URIs.
4. Wire lifecycle in the correct order. `MonacoController.create` returns before the editor is ready. On Web, mount and paint `controller.webViewWidget` before awaiting `whenReady`.
5. Add only the platform behavior the screen needs: focus recovery, route/static overlay protection, scroll handoff, diff editing, or asset precaching.
6. Dispose what the app owns. Never dispose an externally owned controller from a child widget.
7. Validate the smallest supported platform set that proves the design, then run analyzer and tests.

## Invariants

- Use `controller.document.setText`, `getText`, and `setLanguage`; content operations are not controller methods in 3.x.
- Await `controller.whenReady` before treating a self-created controller as live.
- Keep the Web platform view painted under loading UI. `Offstage`, `Visibility(visible: false)`, or inserting the widget only after readiness prevents boot.
- Use sparse `EditorOptions` updates. Do not reconstruct all defaults to change one option.
- Give files stable, unique URIs. Reusing or changing URIs casually breaks model identity, undo state, diagnostics, and LSP features.
- Use `requestFocus`, `releaseNativeFocus`, and `onFocusChanged`. DOM focus and native keyboard readiness are different signals.
- Use `MonacoRouteObserver` plus `MonacoFocusGuard` for route overlays, `MonacoOverlayBoundary` or `MonacoScaffold` for static overlays, and `runWithInteractionDisabled` for transient imperative overlays.
- Prefer the typed API. Use `runJavaScript` only when the public surface cannot express the requirement, and document its CSP and version assumptions.

## Stop conditions

- If the consumer source, resolved flutter_monaco version, or target platforms are unavailable, stop before implementation and request that evidence.
- If controller ownership, document ownership, or required editor behavior cannot be inferred without changing the app's architecture, ask for that decision rather than choosing silently.

## Verification

- Run `dart analyze` with scope appropriate to the app.
- Exercise creation, first paint, text edits, route exit/re-entry, and disposal.
- On Web, verify cold-cache boot and clickable overlays.
- On desktop/mobile targets in scope, verify keyboard input rather than checking only `onFocusChanged`.
- If the screen opens multiple files, verify stable URIs, switching, background edits, undo state, and dirty tracking.

Report the ownership model, lifecycle order, platforms tested, and any untested platform-specific behavior.
