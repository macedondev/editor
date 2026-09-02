import 'dart:async';

import 'package:flutter_monaco/src/types/inline_completion.dart';

/// Callback that provides inline completions (ghost text) for a given request.
typedef InlineCompletionProvider =
    Future<InlineCompletionList> Function(InlineCompletionRequest request);

/// Handle for an inline completion provider registered through
/// `MonacoController.registerInlineCompletions`.
///
/// Call [dispose] to unregister.
final class MonacoInlineCompletionRegistration {
  MonacoInlineCompletionRegistration.internal({
    required this.id,
    required this.disposeHandler,
  });

  final String id;
  final Future<void> Function() disposeHandler;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disposeHandler();
  }
}
