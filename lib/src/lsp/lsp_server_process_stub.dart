import 'package:flutter_monaco/src/lsp/lsp_transport.dart';

const String _webError =
    'LspServerProcess requires dart:io and is not available on the web. '
    'Connect to a language server with LspWebSocketTransport (remember the '
    'allowedConnectSources CSP opt-in) or provide an in-page transport with '
    'LspCustomTransport instead.';

/// Web stub for the stdio language-server process helper.
///
/// Every member throws [UnsupportedError]; see the `dart:io` implementation
/// for real documentation.
class LspServerProcess {
  LspServerProcess._();

  /// Always throws [UnsupportedError] on the web.
  static Future<LspServerProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    void Function(String line)? onStderr,
  }) {
    throw UnsupportedError(_webError);
  }

  /// Unavailable on the web.
  LspBridgedTransport get transport => throw UnsupportedError(_webError);

  /// Unavailable on the web.
  int get pid => throw UnsupportedError(_webError);

  /// Unavailable on the web.
  Future<int> get exitCode => throw UnsupportedError(_webError);

  /// Unavailable on the web.
  bool get isStopped => throw UnsupportedError(_webError);

  /// Unavailable on the web.
  Future<int> stop({
    Duration terminateTimeout = const Duration(seconds: 3),
    Duration killTimeout = const Duration(seconds: 2),
  }) {
    throw UnsupportedError(_webError);
  }
}
