# Focus, First Responder, and Keyboard on Platform Views

This guide explains how focus and keyboard input work when embedding Monaco in Flutter via platform views (WKWebView on macOS/iOS, WebView2 on Windows, an iframe on Web), what the package does about it on each platform, and what remains a real platform limitation.

If you only need the short version: use the provided `MonacoEditor` widget. It wires all of the below correctly. If you must render the raw `controller.webViewWidget`, copy the reference wrapper at the end of this guide.

## The Three-Layer Focus Model

When typing into Monaco inside a platform view, three layers of focus must align:

1) Flutter focus tree
    - A `FocusNode` in Flutter must be the primary focus so Flutter routes key events toward the embedded platform view instead of handling them itself.
2) Native focus (first responder / Win32 focus)
    - The native WKWebView (macOS) must be the NSWindow's first responder, or the WebView2 control (Windows) must hold real Win32 keyboard focus, for the OS to deliver key events to the web content at all.
3) DOM focus (Monaco)
    - Inside the web page, Monaco's hidden `textarea.inputarea` (or `.native-edit-context`) must be `document.activeElement`; otherwise typing does not enter the editor.

Layer 2 is the layer Flutter cannot see or drive by itself on desktop, and it is where almost every historical "editor looks focused but typing does nothing" bug lived. `MonacoController.onFocusChanged` reports layer 3 only; it is NOT a native input-readiness guarantee.

## What the package does per platform

### macOS (since 2.2.0)

`flutter_monaco` ships a small native plugin that performs the real first-responder handoff:

- On a user focus intent (see `MonacoFocusIntent` below), the package makes the editor's WKWebView the window's first responder (`window.makeFirstResponder`), the same mechanism that historically made right-click "wake the editor up".
- `MonacoController.hasNativeInputFocus()` reports whether the WKWebView currently is the first responder - the authoritative layer-2 readiness signal.
- `MonacoController.releaseNativeFocus()` hands the first responder back to the Flutter view.
- If the native plugin is unavailable (custom embeddings, tests), the package falls back to the pre-2.2.0 behavior: a full in-page focus replay on user intent. The replay recovers typing but costs a caret double-blink; the native handoff does not.

Background for the curious: neither the Flutter macOS embedder nor `webview_flutter_wkwebview` performs any first-responder management for platform views (verified against `webview_flutter_wkwebview` 3.26.0 - the package contains no responder code at all). A normal left click therefore may not promote the WKWebView to first responder, while AppKit's context-menu machinery does, which is why right-click used to fix typing.

### Windows (since 2.0.0)

Windows focus is solved at the correct layer by the `webview_flutter_windows` package (a maintained WebView2 integration):

- The WebView2 input windows are reparented into the Flutter window tree, so clicking the editor no longer deactivates the host window.
- `MonacoController.requestFocus()` moves real Win32 keyboard focus to WebView2 before focusing Monaco; a pointer-route coordinator returns focus to Flutter when you click Flutter UI, and enforces that a focused Flutter text input takes native focus back.
- Note a WebView2 platform reality: there is no keyboard-injection API, so the browser HWND must genuinely hold Win32 focus for typing to work. "Keyboard belongs to the page after clicking it" is by design and the coordinator manages the round trip.

### Web

The iframe participates in the browser's focus system; the native handoff inside `MonacoController.requestFocus()` is a no-op. Web has TWO platform-specific problems, and both exist because the browser arbitrates input BEFORE Flutter ever sees it:

- Pointer: the browser's DOM hit test picks the target first. Flutter paints into `pointer-events: none` canvases, so over the editor's rect the topmost interactive DOM element is the iframe, and events dispatched inside an iframe never bubble to the parent document. A Flutter widget painted above the editor (a dialog, a menu) is visible but unreachable - Flutter's hit testing never runs. This is handled by the first-party DOM overlay shield (`MonacoScaffold`, `MonacoOverlayBoundary`, `MonacoWebInteractionCoordinator`, `runWithInteractionDisabled`) and by `setInteractionEnabled(false)` for route overlays. See the README section "Web: Handling Overlays".
- Keyboard: web's layer-2 "native focus" is the parent document's focus. While the iframe element is the parent `document.activeElement`, every key event dispatches inside the iframe's document and Flutter receives nothing. `setInteractionEnabled(false)` and `releaseNativeFocus()` therefore perform a two-sided handoff: blur Monaco inside the iframe AND move the parent document's focus onto the editor's `<flutter-view>` host, so overlays get Escape/Tab/typing without needing a first click.

Nested navigators caveat: `MonacoFocusGuard` observes route pushes only within the `Navigator` its route belongs to. `showDialog` defaults to `useRootNavigator: true`, so an app that hosts the editor inside a nested navigator MUST either observe the root navigator too and drive `setInteractionEnabled` itself, or pass `useRootNavigator: false` consistently. An observer attached to one navigator never notifies a guard subscribed to a route of another navigator.

Also note: while Monaco holds document focus on web, app-global key handlers (`HardwareKeyboard` handlers, `Shortcuts` on ancestors) do not fire - keys never leave the iframe. If the app needs global shortcuts to work while typing in the editor, they must be registered as Monaco keybindings and forwarded over the bridge.

### Android / iOS (native mobile)

The WebView takes native focus from the user's tap itself; the package deliberately renders the bare platform view on mobile (a Flutter `Focus`/`Listener` wrapper steals the gesture context and the OS refuses the soft keyboard) and limits programmatic focus to one attempt so the IME lifecycle is not interrupted.

## Focus intent: user vs maintenance

Every focus entry point takes or implies a `MonacoFocusIntent`:

- `MonacoFocusIntent.user` - the user directly interacted with the editor (e.g. a primary pointer-down inside it). The package may release a stale Flutter text-input client (`TextInput.hide` + unfocus), perform the native handoff, and focus Monaco.
- `MonacoFocusIntent.maintenance` (default) - background work (content sync, route/lifecycle recovery, option changes). Maintenance never steals the keyboard: it stands down while a Flutter text input owns focus.

```dart
// A primary click inside the editor area:
await controller.requestFocus(attempts: 1, intent: MonacoFocusIntent.user);

// Background recovery after a route pop or window focus change:
await controller.requestFocus(); // maintenance by default, cooperative
```

`MonacoEditor` already routes pointer-downs this way with the correct button guards (primary button only; right-clicks never nudge focus, so Monaco's context menu is not torn down).

## App-Level Integration (Recommended)

Prefer the drop-in helper for route/lifecycle recovery:

```dart
MonacoFocusGuard(
  controller: controller,
  // optional: supply a RouteObserver to re-focus when returning to this route
  // routeObserver: myRouteObserver,
);
```

Additional hooks that keep focus solid:

1) Reassert focus on window/app activation (desktop): call `requestFocus(attempts: 3)` from your window-focus and `AppLifecycleState.resumed` handlers. Maintenance intent keeps this safe next to dialogs.
2) Reassert focus after route re-entry (`RouteAware.didPopNext`, post-frame).
3) Re-layout after resizes or reveals: `await controller.layout(); await controller.requestFocus();`
4) Multiple editors / tabs: only the visible editor should be allowed to claim the keyboard. Gate your calls, or use `setInteractionEnabled(false)` on hidden editors - all focus paths respect it.
5) Verifying readiness instead of guessing: on desktop, `await controller.hasNativeInputFocus()` tells you whether the editor truly owns native input (null means the platform cannot answer). Prefer it over inferring readiness from `onFocusChanged`.

## Reference wrapper for the raw WebView

If you render `controller.webViewWidget` directly instead of `MonacoEditor`, replicate the package widget's gates - all of them matter:

```dart
final focusNode = FocusNode(debugLabel: 'MonacoPlatformView');
var monacoReportsFocused = false; // mirror controller.onFocusChanged

bool pointerMayClaimKeyboard(PointerDownEvent event) {
  if (event.kind == PointerDeviceKind.mouse ||
      event.kind == PointerDeviceKind.trackpad) {
    // Never nudge on right/middle click: it tears down Monaco's context
    // menu and double-blinks the caret.
    return event.buttons == kPrimaryMouseButton;
  }
  return true;
}

Widget build(BuildContext context) {
  return Focus(
    focusNode: focusNode,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent) return KeyEventResult.skipRemainingHandlers;
      return KeyEventResult.ignored;
    },
    child: Listener(
      behavior: HitTestBehavior.translucent, // native view still gets the click
      onPointerDown: (event) {
        if (!pointerMayClaimKeyboard(event)) return;
        final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
        // macOS: focus signals can go stale silently; always route user
        // intent (cheap: the native layer verifies first responder).
        // Windows/Linux: skip when both signals are fresh (no replay).
        if (!isMacOS && focusNode.hasFocus && monacoReportsFocused) return;
        focusNode.requestFocus();
        unawaited(controller.requestFocus(
          attempts: 1,
          intent: MonacoFocusIntent.user,
        ));
      },
      child: controller.webViewWidget,
    ),
  );
}
```

## Hit Testing: opaque vs translucent

- `HitTestBehavior.opaque`: your `Listener` claims the click; the native view may not see it. Avoid for platform views.
- `HitTestBehavior.translucent`: your `Listener` observes the click without blocking the native view. Required for the handoff to work.

## Debugging Checklist

- Layer 1 (Flutter): print `FocusManager.instance.primaryFocus` around the editor.
- Layer 2 (native): `await controller.hasNativeInputFocus()` - true means the OS routes keys to the WebView. If typing fails while this is true, the problem is layer 3.
- Layer 3 (DOM): in the WebView's DevTools console, check `document.activeElement` is `textarea.inputarea`.
- If a click does not recover typing, check the click actually reached the editor with a primary button and that no Flutter text input held focus (user intent releases it; maintenance stands down).

## Known Platform Limits (stop chasing these)

- macOS cursor arbitration at platform-view seams: where a Flutter widget (e.g. a splitter divider) sits flush against the WKWebView edge, macOS arbitrates the cursor pixel-by-pixel between Flutter and the native view. Give interactive widgets slop away from the seam; the cursor at the exact seam is OS-owned.
- Windows WebView2 requires real Win32 focus to type (no keyboard-injection or off-screen input API: WebView2Feedback #20/#526/#547). The focus round trip is managed; the requirement itself cannot be removed.
- Flutter Web: pointer and key events inside the iframe's DOM subtree never surface to Flutter's hit testing. A Flutter-painted overlay can never intercept them; only the DOM shield approach works.
- Native mobile soft keyboards must be tied to a real user gesture; programmatic focus cannot conjure the IME reliably. The package's tap-detection heuristics are the available shape.
- Monaco DOM focus signals from `onFocusChanged` can lag or lie about native readiness on desktop. That is why `hasNativeInputFocus()` exists; do not build recovery on DOM signals alone.

## FAQ

- Why did right-click historically "fix" typing on macOS?
    - AppKit promotes a WKWebView to first responder when showing a native context menu. Since 2.2.0 the package performs the same promotion explicitly on primary clicks.
- Do I still need `autofocus`?
    - Useful on first mount; pointer-down user intent plus lifecycle maintenance hooks cover everything after that.
- Should I always call `layout()`?
    - After resizes or when revealing a previously hidden editor; otherwise not needed.

## TL;DR

- Use `MonacoEditor`, or replicate its wrapper exactly (primary-button guard included).
- Route real clicks as `MonacoFocusIntent.user`; leave background recovery as maintenance.
- Trust `hasNativeInputFocus()` over DOM focus signals for desktop readiness.
- Call `requestFocus()` after window/app focus changes and route re-entry; `layout()` + `requestFocus()` after size/visibility changes.
