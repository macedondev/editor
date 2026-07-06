import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/src/lsp/lsp_stdio_framing.dart';
import 'package:flutter_monaco/src/lsp/lsp_transport.dart';

/// Spawns and manages a stdio language server process, exposing it as an
/// [LspBridgedTransport].
///
/// This is the recommended way to run a local language server on desktop:
/// no network port, no proxy, and no Content-Security-Policy changes -
/// JSON-RPC messages are framed onto the process's stdin/stdout and relayed
/// through the Flutter bridge.
///
/// ```dart
/// final server = await LspServerProcess.start(
///   'pyright-langserver', ['--stdio'],
/// );
/// final connection = await controller.connectLanguageServer(
///   id: 'pyright',
///   transport: server.transport,
/// );
/// // ... later:
/// await connection.disconnect(); // stops the process via transport.onClose
/// ```
///
/// ### Lifecycle
///
/// - The server's stdout is decoded with LSP `Content-Length` framing and
///   streamed to the editor; stderr lines go to [onStderr] (default:
///   `debugPrint`).
/// - When the connection is disconnected or the controller is disposed, the
///   transport's `onClose` runs [stop] automatically.
/// - If the process dies on its own, the message stream ends and the
///   connection transitions to `closed`/`failed`; observe
///   `LanguageServerConnection.whenClosed` or [exitCode] to react (e.g.
///   respawn and reconnect).
///
/// ### Platform support
///
/// Desktop (macOS, Windows, Linux hosts running Flutter desktop apps that
/// embed this package's editor on a supported platform). On Android and iOS
/// spawning arbitrary executables is generally impossible; on the web this
/// class is a stub that throws [UnsupportedError].
///
/// **macOS App Sandbox:** a sandboxed app cannot spawn external binaries -
/// `start` fails with `ProcessException: Operation not permitted`. Either
/// disable `com.apple.security.app-sandbox` in your entitlements (fine for
/// apps distributed outside the App Store) or bundle the server inside the
/// app with inherit entitlements.
class LspServerProcess {
  LspServerProcess._(
    this._process, {
    required void Function(String line) onStderr,
  }) {
    // A dead process makes stdin writes fail asynchronously; observing the
    // future keeps that from surfacing as an unhandled async error during
    // hot-reload-heavy dev loops.
    unawaited(_process.stdin.done.then((_) {}, onError: (_) {}));

    _stdoutSubscription = _process.stdout.listen(
      (chunk) {
        try {
          for (final message in _decoder.addBytes(chunk)) {
            if (!_fromServer.isClosed) _fromServer.add(message);
          }
        } catch (error, stackTrace) {
          if (!_fromServer.isClosed) _fromServer.addError(error, stackTrace);
        }
      },
      onDone: () {
        if (!_fromServer.isClosed) _fromServer.close();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_fromServer.isClosed) _fromServer.addError(error, stackTrace);
      },
      cancelOnError: false,
    );

    _stderrSubscription = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onStderr);

    transport = LspBridgedTransport(
      fromServer: _fromServer.stream,
      toServer: _write,
      onClose: () => stop(),
    );
  }

  /// Starts `executable` with [arguments] and wires its stdio for LSP.
  ///
  /// Parameters mirror `Process.start`. Throws a [ProcessException] when the
  /// executable cannot be spawned.
  static Future<LspServerProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    void Function(String line)? onStderr,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
    );
    return LspServerProcess._(
      process,
      onStderr:
          onStderr ?? ((line) => debugPrint('[LSP $executable stderr] $line')),
    );
  }

  final Process _process;
  final LspStdioMessageDecoder _decoder = LspStdioMessageDecoder();
  final StreamController<Map<String, Object?>> _fromServer =
      StreamController<Map<String, Object?>>();
  late final StreamSubscription<List<int>> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  bool _stopped = false;

  /// The transport to pass to `MonacoController.connectLanguageServer`.
  ///
  /// Single-use: one transport connects one editor once. To reconnect after
  /// a crash, start a new [LspServerProcess].
  late final LspBridgedTransport transport;

  /// The underlying process, for advanced integrations.
  Process get process => _process;

  /// The process id.
  int get pid => _process.pid;

  /// Completes with the server's exit code once it terminates.
  Future<int> get exitCode => _process.exitCode;

  /// Whether [stop] has been called.
  bool get isStopped => _stopped;

  void _write(Map<String, Object?> message) {
    if (_stopped) return;
    try {
      _process.stdin.add(LspStdioMessageEncoder.encode(message));
    } catch (error) {
      debugPrint('[LspServerProcess] Failed to write to server stdin: $error');
    }
  }

  /// Stops the language server, escalating gracefully:
  ///
  /// 1. Close stdin (most stdio servers exit on EOF) and wait
  ///    [terminateTimeout].
  /// 2. Send SIGTERM and wait [killTimeout].
  /// 3. Send SIGKILL and wait for exit.
  ///
  /// Returns the process exit code. Safe to call multiple times.
  Future<int> stop({
    Duration terminateTimeout = const Duration(seconds: 3),
    Duration killTimeout = const Duration(seconds: 2),
  }) async {
    if (_stopped) return _process.exitCode;
    _stopped = true;

    try {
      await _process.stdin.close();
    } catch (_) {}

    var code = await _waitForExit(terminateTimeout);
    if (code == null) {
      _process.kill();
      code = await _waitForExit(killTimeout);
    }
    if (code == null) {
      _process.kill(ProcessSignal.sigkill);
      code = await _process.exitCode;
    }

    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    if (!_fromServer.isClosed) {
      unawaited(_fromServer.close());
    }
    return code;
  }

  Future<int?> _waitForExit(Duration timeout) {
    return _process.exitCode
        .then<int?>((code) => code)
        .timeout(timeout, onTimeout: () => null);
  }
}
