import Cocoa
import FlutterMacOS
import WebKit

/// Native macOS focus integration for `flutter_monaco`.
///
/// Typing into a WKWebView-hosted Monaco editor needs three layers aligned:
/// Flutter focus, the NSWindow first responder, and DOM focus. Neither the
/// Flutter engine nor `webview_flutter_wkwebview` manages the first-responder
/// layer for platform views (verified against 3.26.0: the package contains no
/// responder code at all), so a left click on the editor can leave the
/// WKWebView visually focused while AppKit still routes key events elsewhere.
/// Historically only a right click recovered it, because AppKit's context-menu
/// machinery promotes the clicked view to first responder as a side effect.
///
/// This plugin closes that gap explicitly over the
/// `flutter_monaco/native_focus` method channel:
///
/// - `focusWebView`: make the editor's WKWebView the window's first responder
///   (the intentional keyboard handoff into the editor).
/// - `hasNativeFocus`: report whether the WKWebView currently is (or
///   contains) the first responder - the real desktop input-readiness signal.
/// - `releaseWebViewFocus`: hand the first responder back to the Flutter
///   view (the handoff out of the editor).
///
/// The Dart caller passes the WebView widget's bounds (Flutter logical
/// coordinates, which equal AppKit points, origin at the Flutter view's
/// top-left) so the right WKWebView is targeted when a window hosts several.
public class FlutterMonacoPlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_monaco/native_focus",
      binaryMessenger: registrar.messenger)
    let instance = FlutterMonacoPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "focusWebView":
      result(focusWebView(rectArguments: call.arguments))
    case "hasNativeFocus":
      result(hasNativeFocus(rectArguments: call.arguments))
    case "releaseWebViewFocus":
      result(releaseWebViewFocus())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Channel methods

  /// Returns "granted", "already-owned", "refused", "not-found", or
  /// "no-window". Only "granted"/"already-owned" mean the editor now owns
  /// native keyboard input; the Dart side treats everything else as a failed
  /// handoff and falls back to the in-page focus replay.
  private func focusWebView(rectArguments: Any?) -> String {
    guard let window = hostWindow() else { return "no-window" }
    guard let webView = resolveWebView(in: window, rectArguments: rectArguments) else {
      return "not-found"
    }
    if isFirstResponder(webView, in: window) {
      return "already-owned"
    }
    return window.makeFirstResponder(webView) ? "granted" : "refused"
  }

  /// Returns true/false when the target WKWebView was located, nil when it
  /// was not (so the Dart side reports "unknown" instead of a false negative).
  private func hasNativeFocus(rectArguments: Any?) -> Any? {
    guard let window = hostWindow() else { return nil }
    guard let webView = resolveWebView(in: window, rectArguments: rectArguments) else {
      return nil
    }
    return isFirstResponder(webView, in: window)
  }

  /// If any WKWebView (or a descendant) is the first responder, hands the
  /// first responder back to the Flutter view. Returns whether a handoff
  /// happened.
  private func releaseWebViewFocus() -> Bool {
    guard let flutterView = registrar.view, let window = flutterView.window else {
      return false
    }
    guard firstResponderIsWebView(in: window) else { return false }
    return window.makeFirstResponder(flutterView)
  }

  // MARK: - Resolution helpers

  private func hostWindow() -> NSWindow? {
    return registrar.view?.window
  }

  /// Finds the WKWebView the Dart rect points at. Preference order:
  /// 1. The smallest WKWebView whose window-space frame contains the rect's
  ///    center (smallest wins so an editor nested inside another web surface
  ///    resolves to the inner view).
  /// 2. If the rect is absent or matches nothing (mid-layout races), the
  ///    window's sole WKWebView, when unambiguous.
  private func resolveWebView(in window: NSWindow, rectArguments: Any?) -> WKWebView? {
    let root: NSView = window.contentView ?? registrar.view ?? NSView()
    var candidates: [WKWebView] = []
    collectWebViews(in: root, into: &candidates)
    if candidates.isEmpty { return nil }

    if let flutterView = registrar.view,
      let dartRect = parseRect(rectArguments) {
      // Dart sends logical points with the origin at the Flutter view's
      // top-left; AppKit views are bottom-left unless flipped.
      let rectInView: CGRect
      if flutterView.isFlipped {
        rectInView = dartRect
      } else {
        rectInView = CGRect(
          x: dartRect.origin.x,
          y: flutterView.bounds.height - dartRect.origin.y - dartRect.height,
          width: dartRect.width,
          height: dartRect.height)
      }
      let rectInWindow = flutterView.convert(rectInView, to: nil)
      let center = CGPoint(x: rectInWindow.midX, y: rectInWindow.midY)

      var best: WKWebView?
      var bestArea = CGFloat.greatestFiniteMagnitude
      for candidate in candidates {
        let frameInWindow = candidate.convert(candidate.bounds, to: nil)
        let area = frameInWindow.width * frameInWindow.height
        if frameInWindow.contains(center), area < bestArea {
          best = candidate
          bestArea = area
        }
      }
      if let best = best { return best }
    }

    return candidates.count == 1 ? candidates[0] : nil
  }

  private func collectWebViews(in root: NSView, into found: inout [WKWebView]) {
    if let webView = root as? WKWebView {
      found.append(webView)
    }
    for subview in root.subviews {
      collectWebViews(in: subview, into: &found)
    }
  }

  private func parseRect(_ arguments: Any?) -> CGRect? {
    guard let map = arguments as? [String: Any],
      let x = (map["x"] as? NSNumber)?.doubleValue,
      let y = (map["y"] as? NSNumber)?.doubleValue,
      let width = (map["width"] as? NSNumber)?.doubleValue,
      let height = (map["height"] as? NSNumber)?.doubleValue,
      width > 0, height > 0
    else { return nil }
    return CGRect(x: x, y: y, width: width, height: height)
  }

  /// Whether [webView] is the window's first responder, directly or via a
  /// descendant view WebKit installed as the concrete responder.
  private func isFirstResponder(_ webView: WKWebView, in window: NSWindow) -> Bool {
    guard let responder = window.firstResponder else { return false }
    if responder === webView { return true }
    var view = responder as? NSView
    while let current = view {
      if current === webView { return true }
      view = current.superview
    }
    return false
  }

  private func firstResponderIsWebView(in window: NSWindow) -> Bool {
    guard let responder = window.firstResponder as? NSView else { return false }
    var view: NSView? = responder
    while let current = view {
      if current is WKWebView { return true }
      view = current.superview
    }
    return false
  }
}
