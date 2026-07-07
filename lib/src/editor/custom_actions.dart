import 'dart:async';

import 'package:flutter_monaco/src/options/action.dart';

/// Handle for a Dart-defined editor action registered through
/// `MonacoController.addAction`.
///
/// Call [dispose] to remove the action (and its keybindings and context
/// menu entry) from the editor. Disposing more than once is a no-op.
final class MonacoActionRegistration {
  /// Internal constructor; obtain instances from
  /// `MonacoController.addAction`.
  MonacoActionRegistration.internal({
    required this.id,
    required this._unregister,
  });

  /// The action id; also runnable via `MonacoController.executeAction`.
  final MonacoAction id;

  final Future<void> Function() _unregister;
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Removes the action from the editor. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _unregister();
  }
}
