import 'dart:async';

import 'package:flutter_monaco/src/types/geometry.dart';
import 'package:flutter_monaco/src/types/inline_edit.dart';

/// Handle for a pending inline AI edit (ghost decoration + CodeLens).
final class PendingInlineEdit {
  PendingInlineEdit.internal({
    required this.id,
    required this.edit,
    required Future<void> Function() accept,
    required Future<void> Function() reject,
    required Future<void> Function() dispose,
  })  : _accept = accept,
        _reject = reject,
        _dispose = dispose;

  final String id;
  final InlineEdit edit;
  final Future<void> Function() _accept;
  final Future<void> Function() _reject;
  final Future<void> Function() _dispose;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future<void> accept() async {
    if (_disposed) return;
    await _accept();
  }

  Future<void> reject() async {
    if (_disposed) return;
    await _reject();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _dispose();
  }
}

/// Controller for creating pending edits.
abstract class InlineEditController {
  Future<PendingInlineEdit> proposeEdit({
    required Range range,
    required String text,
    String? originalText,
  });
  Future<void> acceptAll();
  Future<void> rejectAll();
}
