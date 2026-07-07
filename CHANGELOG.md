# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-07-07

A ground-up rebuild of the package's spine - one wire protocol, a document/editor split, sparse options, typed errors and events - while keeping the battle-tested platform engineering (LSP, focus recovery, mobile web survival kit, scroll handoff, web overlay stack) intact. The README's "Migrating from 2.x to 3.0" section carries the complete symbol-level migration table; the highlights are below.

### Breaking
- **Content and model operations moved to `controller.document`** (a `MonacoDocument` handle): `setValue`/`getValue` become `document.setText()`/`getText()`, `getLineCount`/`getLineContent`/`getLinesContent` become `lineCount()`/`lineAt()`/`getLines(start, end)` (one bridge call for the whole range), `insertText` becomes `insert`, `hasUnsavedChanges()` becomes `isDirty()`, and `setLanguage`/`applyEdits`/`deleteRange`/`replaceRange`/`findMatches`/`replaceMatches`/`markSaved` move over with the same names. Markers are owner-scoped on the document: `setMarkers(markers, owner:)`/`clearMarkers(owner:)`.
- **Multi-model API replaced by documents**: `createModel`/`setModel`/`disposeModel`/`listModels` become `openDocument({text, language, uri})`/`activateDocument(doc)`/`doc.close()`/`listDocuments()`, with `documentByUri(uri)` for lookups.
- **`MonacoController.create` returns immediately on every platform** (it used to block until ready on native); await `controller.whenReady` (renamed from the `onReady` future). The signature is now `create({options, initialText, page, readyTimeout})`: `customCss`/`allowCdnFonts`/`allowedConnectSources` moved into `MonacoPageConfig` passed as `page:`. Likewise on the widget: `MonacoEditor.initialValue` is now `initialText` and the three loose page parameters are `page: MonacoPageConfig(...)`.
- **`MonacoTheme` and `MonacoLanguage` are extension types over `String`** (were enums): `MonacoTheme.vsDark`/`MonacoLanguage.dart` are unchanged textually, `.values` becomes `.builtIn`, `fromId(s)` becomes `MonacoTheme(s)`/`MonacoLanguage(s)`, and custom ids are first-class. `EditorOptions.themeId`/`effectiveThemeId`, `setThemeById`, and `defineThemeFromJson` are deleted: a custom theme is just `MonacoTheme('app-dark')`. `MonacoThemeDefinition.base` is the new `MonacoBaseTheme` enum.
- **`MonacoAction` constants are typed `MonacoAction` values** (were `String`s) and `executeAction` takes `MonacoAction` with named `args`; wrap raw command ids with `MonacoAction(id)`.
- **`EditorOptions` is sparse**: every field is nullable, and `updateOptions(EditorOptions(fontSize: 16))` changes only the font size instead of resetting ~40 options to package defaults. `padding` is `MonacoPadding`, `minimap` is `MonacoMinimapOptions`, `wordWrap`/`lineNumbers` are enums, and structured `scrollbar`/`guides`/`stickyScroll` sub-options plus an `extra` map cover the rest of Monaco's option surface.
- **Errors are typed and loud**: `MonacoJavaScriptException` is now `MonacoJavaScriptError` under a sealed `MonacoException` hierarchy, every read/write throws on bridge failure, and the `defaultValue` fallback parameters on reads are gone (an app can no longer mistake "bridge died" for "empty document").
- **Completions return registrations**: `registerCompletionSource`/`unregisterCompletionSource` become `registerCompletions(...)`/`registerStaticCompletions(...)`, both returning a `MonacoCompletionRegistration` with `dispose()`; `languages` takes `List<MonacoLanguage>`.
- **Decorations are handle-based**: `setDecorations`/`addInlineDecorations`/`addLineDecorations`/`clearDecorations` become `createDecorationSet()` with `set`/`clear`/`dispose` per set.
- **Events are typed**: `onContentChanged` is `Stream<MonacoContentChanged>` (was `Stream<bool>`; `isFlush` is a field), `onFocus`/`onBlur` merge into `onFocusChanged: Stream<bool>`, and `liveStats`/`getStatistics()` become `stats: ValueListenable<MonacoLiveStats>` with plain typed fields (the label records and the `line*1000+column` cursor encoding are gone).
- **Focus API consolidated**: `focus()`/`ensureEditorFocus({attempts, interval, intent})` become `requestFocus({intent})` with the retry loop internalized; `releaseNativeInputFocus()` is renamed `releaseNativeFocus()`.
- **View state is opaque and typed**: `saveViewState(): Map`/`restoreViewState(Map)` become `captureViewState(): MonacoViewState`/`restoreViewState(MonacoViewState)`; persist via `toJson()`.
- **`MonacoAssets` slimmed**: `assetInfo()` returns a typed `MonacoAssetDiagnostics`; `indexHtmlPath`/`assetBaseDir` are internal (use `assetInfo().path`).
- Behavioral changes: reads throw typed exceptions instead of returning defaults; commands issued before ready run FIFO after ready (preserving the old queue's last-write-wins outcome for consecutive `setText` calls); `updateOptions` is sparse; the markdown/vs-dark boot flash is gone (the first painted frame uses the requested options); unknown JS events surface as `MonacoUnknownEvent` instead of a debug print; `EditorOptions.fromJson` parses only the 3.0 `toJson` shape (apps that persisted hand-built 2.x option JSON re-serialize once with 3.0 `toJson`).

### Added
- **Wire protocol v3.** Every command, event, and callback rides a single versioned, request-correlated JSON envelope channel that behaves identically on Android, iOS, macOS, Windows, and Web - no per-platform result decoding anywhere. A two-phase boot (page handshake, then one boot command carrying options/text/language/theme) means the editor is born configured, and `controller.capabilities` exposes the handshake (`protocolVersion`, `monacoVersion`, `lsp`, `diff`).
- **Dart-defined custom editor actions.** `controller.addAction(MonacoActionDescriptor(...), run)` registers an action with typed keybindings (`MonacoKeybinding`/`MonacoKey`, e.g. Cmd/Ctrl+S save hooks), command-palette presence, and optional context-menu placement; the returned `MonacoActionRegistration.dispose()` removes it. The example app's main demo now ships a Cmd/Ctrl+S save hook.
- **Diff editor.** `MonacoDiffEditor` widget and headless `MonacoDiffController` (`setTexts`, `getModifiedText`, `getLineChangeCount`, `updateOptions`, `updateDiffOptions`, `setTheme`, `revealNextChange`/`revealPreviousChange`), configured via `MonacoDiffOptions` (side-by-side or inline, original editability, whitespace handling, `extra` passthrough). New demo: `example/lib/diff_example.dart`.
- **Multi-document editing.** `openDocument` returns URI-pinned `MonacoDocument` handles that can edit their model even while another document is visible; documents keep independent undo stacks and dirty state, and content-change events carry the document URI. The multi-editor example is now a tabbed single-editor, multi-document demo.
- **`MonacoDecorationSet`**: multiple independent decoration owners (e.g. search highlights + lint underlines) that no longer clobber each other.
- **Sealed `MonacoEvent` union** on `controller.events` with typed convenience streams; `MonacoContentChanged` carries structured change ranges (`changes`, capped at 64 KB with `truncated: true` beyond) enabling diff-based sync without full-text pulls; unknown event names surface as `MonacoUnknownEvent`.
- **Sealed `MonacoException` hierarchy**: `MonacoJavaScriptError`, `MonacoProtocolError`, `MonacoTimeoutError` (implements `TimeoutException`, so existing `on TimeoutException` catches keep working), and `MonacoDisposedError`, each carrying the failing operation name.
- **`MonacoPageConfig`**: groups `customCss`, `allowCdnFonts`, and `allowedConnectSources` for `create` and both widgets.
- **`MonacoDefaults`** (the curated `editorOptions` base the widget merges under user options, plus default theme/language) and **`MonacoFontStacks`** (the former `MonacoFont` stacks as `String` constants).
- **`MonacoAssetDiagnostics`**: typed asset cache info (`exists`, `path`, `monacoVersion`, `fileCount`, `totalSizeBytes`/`totalSizeMB`, `generatedHtmlCount`).
- **Brightness-following default theme**: a null `EditorOptions.theme` resolves from the ambient Flutter brightness (dark gets `vs-dark`, light gets `vs`) and re-resolves when the platform switches modes; an explicit theme always wins.
- **Open extension types with dot shorthand**: custom themes (`MonacoTheme('app-dark')`), contributed languages (`MonacoLanguage('mylang')`), and arbitrary command ids (`MonacoAction('my.command')`) are first-class, and Dart 3.10+ shorthands work at call sites (`executeAction(.formatDocument)`, `setTheme(.vsDark)`).
- **`MonacoEditor.onError`**: async command failures the widget itself triggers now surface through this callback (default: `FlutterError.reportError`) instead of being silently debug-printed. `MonacoDiffEditor` has the same hook.

### Changed
- `getEditorState()` now completes in one bridge round trip (was five sequential calls) and finally populates `theme` (was always `null`).
- The LSP subsystem rides protocol v3 internally; its public API is unchanged from 2.3.0 and is pinned by a golden surface test. `LanguageServerConnection`, transports, `LspServerProcess`, and reconnect policies all work exactly as before.
- The bridge JavaScript ships as real asset files (`assets/monaco/bridge/*.js`) instead of a Dart string literal, and the generated HTML is rewritten on every load - a package upgrade can never serve a stale bridge, and the manual cache-bust constant is gone.

### Removed
- The 15 controller convenience action methods (`format`, `find`, `replace`, `toggleWordWrap`, `selectAll`, `undo`, `redo`, `cut`, `copy`, `paste`, `foldAll`, `unfoldAll`, `toggleLineComment`, `indentLines`, `outdentLines`); use `executeAction` with the matching `MonacoAction` constant (`.formatDocument`, `.commentLine`, `.startFindReplaceAction`, ...).
- The marker conveniences `setErrorMarkers`/`setWarningMarkers`/`clearAllMarkers`; build `MarkerData.error(...)`/`MarkerData.warning(...)` lists and clear owners explicitly.
- `MonacoConstants` (see `MonacoDefaults`) and the `MonacoFont` enum (see `MonacoFontStacks`).
- `MonacoAssets.htmlGenerationVersion` and public `generateIndexHtml`: HTML generation is internal and regenerated automatically on every load, so no cache-bust bookkeeping remains.

## [2.3.0] - 2026-07-06

### Added
- **Language Server Protocol support.** `MonacoController.connectLanguageServer` connects the editor to a real language server through Monaco 0.55's built-in LSP client; once connected, completions, hover, go-to-definition, references, rename, formatting, code actions, folding, inlay hints, semantic tokens, and diagnostics come straight from the server with nothing to wire up in Dart. The returned `LanguageServerConnection` exposes `state`/`stateChanges`/`whenClosed`, `disconnect()`, and experimental `sendRequest`/`sendNotification` escape hatches for non-standard server extensions. `disconnectLanguageServer`, `languageServerConnections`, and `languageServerConnection(id)` round out the controller API.
- Three pluggable LSP transports: `LspWebSocketTransport` (server behind a `ws://`/`wss://` endpoint - works on every supported platform), `LspBridgedTransport` (Dart owns the wire; JSON-RPC is relayed through the Flutter bridge - no port, no proxy, no CSP changes), and `LspCustomTransport` (user-registered JavaScript factory on `window.flutterMonacoLspTransports` for worker/iframe/custom setups).
- `LspServerProcess.start(executable, args)` spawns a local stdio language server (e.g. `pyright-langserver --stdio`) on desktop and hands you a fully wired bridged transport, with stderr forwarding, graceful stop (stdin EOF, then SIGTERM, then SIGKILL), and automatic shutdown when the connection or controller is disposed.
- Optional automatic reconnect for WebSocket/custom transports via `LspReconnectPolicy.exponentialBackoff(...)` on `connectLanguageServer`; drops after the connection was open reconnect with backoff and surface each attempt on `stateChanges`.
- `allowedConnectSources` on `MonacoController.create` and the `MonacoEditor` widget: an explicit Content-Security-Policy opt-in for `connect-src` origins. Required for WebSocket language servers (the default policy blocks all `ws://`/`wss://` handshakes); entries that could inject CSP directives are rejected.
- Exported `LspStdioMessageEncoder`/`LspStdioMessageDecoder` (LSP `Content-Length` framing codec) for apps that integrate their own process or socket plumbing with `LspBridgedTransport`.
- New LSP demo in the example app (`example/lib/lsp_example.dart`) covering both the WebSocket and the local stdio-process paths.
- Opt-in **edge scroll handoff** for editors embedded in scrollable pages. With `MonacoEditor(scrollHandoff: MonacoScrollHandoff.edge(...))`, wheel or trackpad scrolling keeps moving Monaco until the editor reaches its scroll edge (or the document has nothing to scroll), then continues into a configured `ScrollController` or the nearest enclosing vertical `Scrollable`; reversing direction hands the wheel back to the editor. Disabled by default: existing apps keep the exact previous scroll-trapping behavior. Ctrl/meta wheel (editor zoom, browser zoom, macOS pinch) and Monaco's own scrollable overlays (suggest list, hover docs, menus, peek editors) are never handed off, and `scrollBeyondLastLine` blank space counts as editor-scrollable. This is edge handoff across the WebView bridge, not native nested scrolling.
- `MonacoScrollHandoff` (with `MonacoScrollHandoffDetails`, `MonacoScrollHandoffMode`, `MonacoScrollHandoffSource`) including an `onHandoff` callback to consume forwarded deltas in app code.
- `MonacoController.onScrollHandoff` (typed stream of unconsumed scroll deltas) and `MonacoController.setScrollHandoffSources(...)` for headless or custom-widget integrations that want the events without `MonacoEditor`'s built-in scrolling.
- An experimental, separately opt-in touch source (`MonacoScrollHandoff.edge(mobileTouch: true)`). Touch forwarding is observation-only (it never blocks Monaco's touch handling, never opens the keyboard, and yields to text selection) and has no native momentum or fling transfer.
- New scroll handoff demo in the example app (`example/lib/scroll_handoff_example.dart`): a scrollable page with short, long, and handoff-disabled editors plus live toggles.

### Changed
- Upgraded the bundled Monaco Editor from 0.54.0 to 0.55.1 (first version to ship `monaco.lsp`). Extracted assets re-extract once on first launch after upgrading. The deprecated `monaco.languages.json/css/html/typescript` namespaces are still aliased by Monaco, and the bridge's JSON diagnostics configuration now prefers the new top-level `monaco.json` namespace, so existing code and raw-JS integrations keep working.
- Removed a stray `debugger;` statement from the bundled Monaco 0.55.1 LSP diagnostics feature (an upstream build artifact) so opening the web inspector while an LSP connection starts no longer pauses the editor.

### Fixed
- Mobile web (#11 hardening): the keyboard viewport-fit no longer engages just because the editor is partially scrolled offscreen. It previously pinned `#editor-container` to the on-screen band whenever the iframe extended past the viewport, so an editor inside a scrollable Flutter page stopped scrolling away with the page (its content "anchored" to the screen), and pinch zoom fought the pin. The pin now activates only while the visual viewport is actually constrained - the soft keyboard shrinking it, or Safari panning it to chase the caret - and never while pinch-zoomed. The keyboard behavior on iOS Safari is unchanged.
- Mobile web: disposing an editor no longer leaks its Monaco instance. The viewport-fit and keyboard-baseline listeners the editor document registers on the host page's `visualViewport`/window survived `dispose()` (removing an iframe fires no `pagehide`), keeping the whole dead editor document - Monaco included - reachable from the host page. Parent-side listeners now self-detach once the frame leaves the DOM, are all detached eagerly on `dispose()`, and the load-retry path no longer leaks the keyboard-baseline listener either.
- Flutter Web: creating multiple editors in the same frame no longer collides. The iframe view id was derived purely from the wall clock (milliseconds), so editors initialized in the same millisecond shared one platform-view id and one message token: every `HtmlElementView` resolved to the first iframe and the remaining editors never became ready (stuck on the loading spinner). View ids now include a per-instance counter, keeping every editor's iframe and bridge messages isolated.

## [2.2.2] - 2026-07-06

### Fixed
- Flutter Web: disabling editor interaction now returns the keyboard to Flutter, not just the pointer. `setInteractionEnabled(false)` (and the `MonacoFocusGuard` route-overlay path that calls it) previously made the iframe pointer-inert and blurred Monaco's textarea, but the parent document's focus stayed ON the iframe element, so every key event kept dispatching inside the iframe: Escape could not close a dialog shown over the editor, Tab could not traverse it, and a button-only alert stayed keyboard-dead until its first click. The interaction toggle now performs the same two-sided handoff as the desktop platforms: blur inside the iframe, then move the parent document's focus onto the editor's own `<flutter-view>` host (multi-view safe, `tabindex` fallback, no scroll jump), so Flutter overlays receive keys immediately. `MonacoController.releaseNativeInputFocus()` performs the same handoff on web instead of being a no-op.

### Docs
- Documented that `MonacoFocusGuard` bridges route overlays only within its own `Navigator`: with nested navigators (for example `showDialog` with its default `useRootNavigator: true` while the editor lives in a nested navigator), the observer on one navigator never notifies a guard subscribed to a route of another. Apps with nested navigators should observe every navigator that can host overlays and drive `setInteractionEnabled` from that (see the focus guide).

## [2.2.1] - 2026-07-06

### Fixed
- Fixed Flutter Web WASM compatibility metadata by moving native-only Monaco asset extraction behind conditional storage helpers. Web builds no longer import `path_provider` through `MonacoAssets`, while native platforms keep the same asset extraction behavior.

## [2.2.0] - 2026-07-05

### Added
- Added a macOS native focus plugin that performs the real NSWindow first-responder handoff between the Flutter view and the editor's WKWebView. Clicking Monaco now restores typing through the same native mechanism that made right-click "wake the editor up", instead of an in-page focus replay. The package registers as a plugin on macOS; run your app's usual build (CocoaPods integration is automatic) after upgrading.
- Added `MonacoController.hasNativeInputFocus()`, the authoritative desktop input-readiness signal: whether the OS currently routes keyboard input to the editor (macOS first responder, Windows WebView2 native focus). Returns `null` where the platform cannot answer. Use it instead of inferring readiness from `onFocus`/`onBlur`, which only report DOM focus.
- Added `MonacoController.releaseNativeInputFocus()` to hand native keyboard focus back to the Flutter view programmatically (mirrors the handoff Windows already had via `webview_flutter_windows`).

### Fixed
- macOS: user clicks on an already-focused editor no longer run the full in-page focus replay (a blur/refocus cycle that double-blinked the caret). When the native handoff verifies or restores first-responder state, the idempotent in-page focus is enough; the replay now runs only as a fallback when the native plugin is unavailable (for example custom embeddings or tests) or the handoff fails, and at most once per recovery instead of once per retry attempt.

## [2.1.1] - 2026-06-21

### Fixed
- Fixed desktop editor input recovery after Flutter text fields or dialogs leave a stale text-input client active before Monaco is focused.

## [2.1.0] - 2026-06-21

### Added
- Added `MonacoFocusIntent` so apps can distinguish direct user-initiated editor focus recovery from background focus maintenance.

### Fixed
- Fixed macOS WKWebView input readiness recovery when Monaco appears focused but typing and paste are ignored.
- Kept background focus nudges cooperative with focused Flutter text inputs, and preserved the Windows WebView2 no-replay behavior for right-clicks and repeated primary clicks.

## [2.0.0] - 2026-06-20

### Changed
- Raised the minimum supported SDK to Dart 3.12 and Flutter 3.44, and moved Windows support to the maintained `webview_flutter_windows` package.

### Fixed
- Windows editor focus now recovers after native-focus loss, avoids replaying focus on right-click or repeated clicks, and no longer steals the keyboard from focused Flutter text inputs.
- Mobile Safari on Flutter Web: touch scrolling inside the editor no longer pans the host page (#11). The generated editor document and the host iframe statically declare `touch-action: none` and `overscroll-behavior: none`, so touches that Monaco does not claim can no longer chain out of the frame.
- Mobile web soft keyboard (#11): while the keyboard constrains the browser's visual viewport, the editor now pins itself to the visible part of its frame and keeps the caret revealed.
- iOS/macOS worker bootstrap: the WKWebView worker shim now emits escaped newline sequences inside JavaScript string literals, so Monaco language workers load instead of falling back to the main thread.

## [1.7.1] - 2026-06-20

### Fixed
- **Flutter Web: Monaco failed to load under path URL strategy (#14).** With `usePathUrlStrategy()` (or any non-root route such as GoRouter `/canvas/:id`), the bundled `vs/` URL was built from the browser route, so `loader.js` 404'd and the editor surfaced "Failed to load Monaco loader.js". Asset URLs now resolve through Flutter's asset manager against the document `<base href>`, independent of the current route - so Monaco loads correctly under deep routes, a sub-path `<base href>`, and a CDN `assetBase`.

## [1.7.0] - 2026-05-19

### Added
- **Themable chrome.** `MonacoEditorTheme` (`InheritedTheme`) styles the built-in loading, error, and status-bar widgets. Composes through `showDialog` and nested overrides; missing values fall back to the surrounding Material theme.
- **Typed custom themes.** `MonacoThemeDefinition` (freezed) registers custom syntax themes via `defineTheme(...)`, `defineThemeFromJson(id, data)`, or `fromMonacoThemeData(id, data)`. Pair with `EditorOptions.themeId`, `setThemeById`, and `getThemeId()` (read live theme id) to switch and persist user choices.
- **Typed bridge errors.** Command methods throw `MonacoJavaScriptException` on failure instead of returning silent defaults. Reads with documented defaults (`getValue`, `getLineCount`, `getLineContent`) still honor them.
- **Reliable macOS background.** New `setHostPageBackgroundColor` recolors Monaco's HTML host page. Widget `backgroundColor` applies to both native and host-page layers.

### Docs
- README: section on migrating from native Flutter code editors covering settings, theme registration, chrome theming, and background colors.

## [1.6.0] - 2026-05-18

### Added
- `MonacoOverlayBoundary` widget and `MonacoScaffold` convenience wrapper for static Flutter overlays (FABs, drawers, persistent bars, custom `Stack` children) that previously had pointer events swallowed by the editor iframe on Web. `MonacoScaffold` auto-protects the standard Scaffold overlay slots (`floatingActionButton`, `drawer`, `endDrawer`, `bottomSheet`, `bottomNavigationBar`, `persistentFooterButtons`); `MonacoOverlayBoundary` is the underlying primitive for arbitrary overlay subtrees.
- `MonacoController.runWithInteractionDisabled(action)` for transient overlays (snackbars, toasts, imperative `Overlay.insert` entries) that are neither route-based nor static enough for `MonacoOverlayBoundary`.
- Internal `MonacoWebInteractionCoordinator` that ref-counts iframe pointer-events so route overlays (`MonacoFocusGuard`) and static overlays compose without fighting.

### Fixed
- Fixed soft keyboard activation for `MonacoEditor` on native Android and iOS by letting the platform view own the tap-to-input gesture path.
- Fixed Android Flutter Web scroll gestures so scrolling focused Monaco content no longer opens the keyboard on release, while preserving intentional keyboard-open scrolling.
- Fixed a Flutter Web first-load race by waiting for iframe attachment and retrying transient Monaco load failures.
- Fixed the example iOS runner build configuration.

### Changed
- Example app switched to `MonacoScaffold`, wired `MonacoRouteObserver` + `MonacoFocusGuard`, and dropped the `pointer_interceptor` dependency.

### Docs
- Rewrote the README "Web: Handling Overlays" section to cover route overlays (`MonacoFocusGuard`), static overlays (`MonacoScaffold` / `MonacoOverlayBoundary`), and transient overlays (`runWithInteractionDisabled`).

## [1.5.0] - 2026-05-16

### Added
- JSON diagnostics support: `MonacoController.setJsonDiagnostics()` enables schema-based validation with inline errors and warnings for JSON content.
- `JsonDiagnosticsOptions` and `JsonDiagnosticsSchema` models for configuring validation rules, severity levels, and schema associations.
- `DiagnosticsSeverity` enum (`error`, `warning`, `ignore`) for controlling diagnostic severity across JSON language features.
- Added `MonacoController.runJavaScript(String script)` as an advanced fire-and-forget JavaScript escape hatch. It waits for the editor to be ready before executing.
- Added `MonacoController.evaluateJavaScript<T>(String expression, {T? defaultValue})` for typed JavaScript evaluation with cross-platform result normalization.
- Added `MonacoController.runJavaScriptReturningResultRaw(String script)` for advanced callers who need the platform-native return value.

### Fixed
- `JsonDiagnosticsSchema.fromJson` now throws when both `uri` and `schemaUri` keys are missing instead of silently falling back to a bogus URI.

### Security
- Documented that JavaScript escape-hatch methods do not sanitize input and that callers should use `jsonEncode` when embedding dynamic values.

## [1.4.0] - 2026-01-25

### Added
- Added `interactionEnabled` to `MonacoEditor` and `MonacoController.setInteractionEnabled`. This allows Flutter Web overlays (dialogs, dropdowns) to receive pointer events when they overlap the Monaco editor.
- Added `autoDisableInteraction` to `MonacoFocusGuard` to automatically toggle editor interaction based on route changes.
- Web: Focus enforcement is now gated by the interaction flag to prevent focus stealing when overlays are active.

### Fixed
- `createModel` now returns a valid URI or throws when Monaco returns invalid data.
- `lineHeight` now behaves as a multiplier in Dart and is converted to pixels for Monaco.
- Completion suggestions now fall back to the default range when item ranges are omitted.
- Font ligatures respect `EditorOptions.fontLigatures`.
- Windows message logging is gated for debug builds to avoid release noise.

## [1.3.0] - 2026-01-24

- Added Web platform support.

## [1.2.1] - 2026-01-08
### Fixed
- Publish workflow now uses GitHub OIDC via the official Dart publish workflow.

## [1.2.0] - 2026-01-08
### Added
- `MonacoAction` registry with comprehensive Monaco 0.54.0 action IDs for type-safe `executeAction` calls.
- Test utilities for platform WebView and controller bootstrapping (`PlatformWebViewController`, `MonacoController.createForTesting`).

### Changed
- Unknown language/theme IDs now default to `markdown` and `vsDark` respectively.
- Controller bootstrapping and WebView initialization now use a unified platform adapter with safer lifecycle handling.

### Fixed
- `executeAction` now tries `editor.getAction(id).run()` first, then falls back to `trigger` for broader action support.
- Asset extraction now reports incomplete copies and resets initialization state after failures.

## [1.1.1] - 2025-11-16
### Changed
- Bundled Monaco Editor updated to **v0.54.0** (latest stable drop from Microsoft). Existing apps automatically pick up the new assets on next launch.

## [1.1.0] - 2025-11-16
### Added
- Full IntelliSense bridge: JavaScript hooks + `MonacoController.registerCompletionSource` / `registerStaticCompletions`.
- Strongly typed completion models (`CompletionItem`, `CompletionList`, `CompletionRequest`, `CompletionItemKind`, `InsertTextRule`).
- README + example updates showing how to source completions from snippets or remote services.

### Fixed
- Export ordering and analyzer fixes to keep the public API clean.

## [1.0.0] - 2025-09-15
- Reliable typing after route/app switches on macOS/Windows - no right‑click needed.
- Optional `MonacoFocusGuard` to auto‑restore focus on resume/route return.
- New guide: doc/focus-and-platform-views.md with best practices and snippets.
- Sensible defaults: word wrap ON, minimap OFF, consistent across APIs.

## [0.1.0] - 2025-08-16

### Initial Release 🎉

#### Features
- **Full Monaco Editor Integration** - Complete VS Code editor experience in Flutter
- **100+ Language Support** - Syntax highlighting for all major programming languages
- **Multiple Themes** - VS Light, VS Dark, High Contrast Black, High Contrast Light
- **Cross-Platform Support** - Works on Android, iOS, macOS, and Windows
- **Type-Safe API** - Comprehensive typed bindings with enums for all configurations
- **Multi-Editor Support** - Run multiple independent editor instances
- **Live Statistics** - Real-time line/character counts and selection information
- **Find & Replace** - Full programmatic find/replace with regex support
- **Decorations & Markers** - Add highlights, errors, warnings to code
- **Event Streams** - Listen to content changes, selection, focus events
- **Versioned Asset Caching** - Efficient one-time asset installation (~30MB)
- **Custom Fonts** - Support for Fira Code, JetBrains Mono, Cascadia Code, and more
- **Editor Actions** - Format, undo, redo, cut, copy, paste, select all
- **Clipboard Operations** - Full clipboard support across platforms
- **Navigation** - Scroll to top/bottom, reveal line, focus management
- **Content Management** - Get/set value, language switching, theme switching
- **Advanced Options** - Word wrap, minimap, line numbers, rulers, bracket colorization

#### Platform Requirements
- **Android**: 5.0+ (API level 21)
- **iOS**: 11.0+
- **macOS**: 10.13+
- **Windows**: 10 version 1809+ with WebView2 Runtime

#### Known Limitations
- Web platform not supported (asset bundling limitations)
- Linux platform not supported (WebKitGTK integration pending)
- Initial startup requires ~1-2 seconds for asset extraction (one-time)
- Each editor instance consumes ~30-100MB memory depending on content

#### Dependencies
- `webview_flutter`: - For mobile and macOS WebView
- `webview_windows`: - For Windows WebView2
- `path_provider`: - For asset caching
- `dart_helper_utils`: - For utility extensions
- `freezed`: - For immutable models

[0.1.0]: https://github.com/omar-hanafy/flutter_monaco/releases/tag/v0.1.0
