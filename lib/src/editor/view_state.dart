import 'package:flutter/foundation.dart';

/// An opaque, persistable Monaco view state (cursor, scroll position,
/// folded regions).
///
/// Produced by `MonacoController.saveViewState` and consumed by
/// `restoreViewState`. The payload shape belongs to Monaco and is not part
/// of this package's API contract; treat it as a black box that can be
/// serialized with [toJson] and rebuilt with [MonacoViewState.fromJson].
@immutable
final class MonacoViewState {
  /// Wraps a raw Monaco view-state payload.
  const MonacoViewState.fromJson(this._json);

  final Map<String, Object?> _json;

  /// The raw Monaco payload, for persistence.
  Map<String, Object?> toJson() => _json;

  /// Whether the payload carries any state at all.
  bool get isEmpty => _json.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MonacoViewState && mapEquals(other._json, _json);

  @override
  int get hashCode =>
      Object.hashAll(_json.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'MonacoViewState(${_json.length} entries)';
}
