import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/src/protocol/envelope.dart';

/// Page-level configuration for the generated Monaco host page.
///
/// These settings affect HTML generation, so changing any of them requires
/// recreating the controller (a new page load); they cannot be applied to a
/// live editor.
@immutable
final class MonacoPageConfig {
  /// Creates a page configuration.
  const MonacoPageConfig({
    this.customCss,
    this.allowCdnFonts = false,
    this.allowedConnectSources = const [],
  });

  /// CSS injected into a `<style>` tag in the page head. Use for custom
  /// fonts (`@font-face`), theme overrides, or UI tweaks.
  final String? customCss;

  /// If `true`, relaxes CSP to allow `https:` in `style-src` and `font-src`,
  /// enabling CDN-hosted fonts. **Security note:** this allows network
  /// requests from the editor page.
  final bool allowCdnFonts;

  /// Additional CSP `connect-src` source expressions (e.g.
  /// `wss://lsp.example.com` or `ws://127.0.0.1:3000`). Required for
  /// WebSocket language servers - the default policy of `'self' blob:`
  /// blocks every `ws://`/`wss://` handshake. Entries containing
  /// whitespace, quotes, or `;` throw an [ArgumentError] at page build to
  /// prevent policy injection. **Security note:** every listed origin
  /// becomes reachable from any JavaScript running inside the editor page.
  final List<String> allowedConnectSources;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MonacoPageConfig &&
        other.customCss == customCss &&
        other.allowCdnFonts == allowCdnFonts &&
        listEquals(other.allowedConnectSources, allowedConnectSources);
  }

  @override
  int get hashCode => Object.hash(
    customCss,
    allowCdnFonts,
    Object.hashAll(allowedConnectSources),
  );
}

/// What the loaded Monaco page can do, reported by the protocol handshake.
///
/// Read from `MonacoController.capabilities` after readiness. Lets apps
/// feature-gate instead of erroring mid-flight.
@immutable
final class MonacoCapabilities {
  /// Creates a capability set.
  const MonacoCapabilities({
    required this.monacoVersion,
    required this.protocolVersion,
    required this.lsp,
    required this.diff,
  });

  /// Builds the capability set from a protocol handshake.
  factory MonacoCapabilities.fromHandshake(MonacoHandshake handshake) {
    return MonacoCapabilities(
      monacoVersion: handshake.monacoVersion,
      protocolVersion: handshake.protocolVersion,
      lsp: handshake.capabilities.contains('lsp'),
      diff: handshake.capabilities.contains('diff'),
    );
  }

  /// The Monaco Editor version running in the page.
  final String monacoVersion;

  /// The wire protocol version the page speaks.
  final int protocolVersion;

  /// Whether the page bundles the LSP bridge.
  final bool lsp;

  /// Whether the page supports the diff editor commands.
  final bool diff;

  @override
  String toString() =>
      'MonacoCapabilities(monaco $monacoVersion, protocol v$protocolVersion, '
      'lsp: $lsp, diff: $diff)';
}
