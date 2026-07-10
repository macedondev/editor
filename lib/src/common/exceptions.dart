import 'dart:async';

/// Base type for every failure the Monaco bridge can raise.
///
/// The hierarchy is sealed so callers can switch exhaustively:
///
/// * [MonacoJavaScriptError] - the page reported an error for a command.
/// * [MonacoProtocolError] - the wire contract itself broke (version skew,
///   malformed or wrongly-typed payloads).
/// * [MonacoTimeoutError] - no response arrived in time.
/// * [MonacoDisposedError] - the controller/protocol was used after dispose,
///   or disposed while work was in flight.
/// * [MonacoPageReloadedError] - the page document reloaded while the
///   command was in flight; the command can be retried once the editor
///   recovers (`MonacoController.onPageReloaded`).
///
/// Every read and write on `MonacoController` throws on failure; nothing is
/// silently defaulted.
sealed class MonacoException implements Exception {
  /// Creates an exception with a human-readable [message].
  const MonacoException(this.message, {this.operation});

  /// Human-readable error description.
  final String message;

  /// Bridge operation that failed (e.g. `'document.getText'`), when known.
  final String? operation;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType');
    if (operation != null) buffer.write('($operation)');
    buffer.write(': $message');
    return buffer.toString();
  }
}

/// The JavaScript side reported an error envelope (`ok: false`) for a
/// command, or a boot-fatal lifecycle message.
///
/// Inspect [operation] for the failed bridge method, [message] for the
/// JavaScript-side description, and [stack] when the platform provides one.
final class MonacoJavaScriptError extends MonacoException {
  /// Creates a JavaScript bridge error.
  const MonacoJavaScriptError({
    required String message,
    String? operation,
    this.name,
    this.stack,
    this.details,
  }) : super(message, operation: operation);

  /// Builds an error from the bridge error envelope payload.
  ///
  /// The shape matches what the JavaScript dispatcher produces on `ok:
  /// false`: `{name, message, stack}`. Missing fields fall back to safe
  /// defaults.
  factory MonacoJavaScriptError.fromJson(
    Map<String, dynamic> json, {
    String? operation,
  }) {
    return MonacoJavaScriptError(
      operation: operation,
      name: json['name']?.toString(),
      message: json['message']?.toString() ?? 'Unknown JavaScript bridge error',
      stack: json['stack']?.toString(),
      details: json,
    );
  }

  /// JavaScript error name (e.g. `'Error'`, `'TypeError'`), when available.
  final String? name;

  /// JavaScript stack trace, when the platform provides one.
  final String? stack;

  /// Raw decoded error envelope fields, for callers that need extra context.
  final Object? details;

  @override
  String toString() {
    final buffer = StringBuffer('MonacoJavaScriptError');
    if (operation != null) {
      buffer.write('($operation)');
    }
    buffer.write(': ');
    if (name != null && name!.isNotEmpty && name != 'Error') {
      buffer.write('$name: ');
    }
    buffer.write(message);
    return buffer.toString();
  }
}

/// The wire contract itself broke: protocol version skew between the
/// generated page and the Dart package, or a response whose shape does not
/// match what the command promises (e.g. `document.getText` returning a
/// non-string).
final class MonacoProtocolError extends MonacoException {
  /// Creates a protocol contract error.
  const MonacoProtocolError({required String message, String? operation})
    : super(message, operation: operation);
}

/// A command received no response within its deadline, or the editor did
/// not become ready within `readyTimeout`.
///
/// Also implements [TimeoutException] so pre-existing
/// `on TimeoutException` handlers keep working.
final class MonacoTimeoutError extends MonacoException
    implements TimeoutException {
  /// Creates a timeout error carrying the elapsed [timeout].
  const MonacoTimeoutError({
    required String message,
    required this.timeout,
    String? operation,
  }) : super(message, operation: operation);

  /// The deadline that expired.
  final Duration timeout;

  @override
  Duration? get duration => timeout;
}

/// The protocol or controller was used after `MonacoController.dispose`, or
/// disposed while commands were still in flight.
final class MonacoDisposedError extends MonacoException {
  /// Creates a use-after-dispose error.
  const MonacoDisposedError({required String message, String? operation})
    : super(message, operation: operation);
}

/// The page document reloaded while the command was in flight, so the
/// command can never be answered: every page-side object (models,
/// registrations, pending responses) was discarded with the old document.
///
/// Page reloads happen outside the app's control - the Flutter web engine
/// re-inserted the editor's iframe during platform-view re-composition, a
/// native WebView process recovered, or the page was refreshed. Unlike
/// [MonacoDisposedError] this is transient: the controller re-boots the
/// fresh page automatically and announces recovery through
/// `MonacoController.onPageReloaded`, after which the command can be
/// retried.
final class MonacoPageReloadedError extends MonacoException {
  /// Creates a reload-interrupted-command error.
  const MonacoPageReloadedError({required String message, String? operation})
    : super(message, operation: operation);
}
