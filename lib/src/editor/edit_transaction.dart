// ignore_for_file: public_member_api_docs
import 'dart:async';

import 'package:flutter_monaco/src/types/text.dart';

/// Groups a set of streamed LLM edits into a single undo step.
///
/// Usage:
/// ```dart
/// final tx = controller.beginEditTransaction();
/// await tx.applyEdits([...]);
/// await tx.applyEdits([...]);
/// await tx.commit(); // or abort()
/// ```
final class EditTransaction {
  EditTransaction._(this._apply, this._pushUndoStop, this._popUndoStop);

  /// Internal factory used by [MonacoController].
  factory EditTransaction.internal(
    Future<void> Function(List<EditOperation> edits) apply,
    Future<void> Function() pushUndoStop,
    Future<void> Function() popUndoStop,
  ) =>
      EditTransaction._(apply, pushUndoStop, popUndoStop);

  final Future<void> Function(List<EditOperation> edits) _apply;
  final Future<void> Function() _pushUndoStop;
  final Future<void> Function() _popUndoStop;
  bool _closed = false;
  bool _committed = false;

  /// Apply edits as part of this transaction. They are coalesced and do not
  /// create separate undo stops.
  Future<void> applyEdits(List<EditOperation> edits) async {
    if (_closed) throw StateError('Transaction already closed');
    if (edits.isEmpty) return;
    await _apply(edits);
  }

  /// Commit the transaction - pushes a final undo stop so the whole AI turn is one undo.
  Future<void> commit() async {
    if (_closed) return;
    _closed = true;
    _committed = true;
    await _pushUndoStop();
  }

  /// Abort - rolls back incomplete edits where possible and closes without pushing stop.
  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    // Pop the initial stop if we pushed one at begin.
    try {
      await _popUndoStop();
    } catch (_) {}
  }

  bool get isClosed => _closed;
  bool get isCommitted => _committed;
}
