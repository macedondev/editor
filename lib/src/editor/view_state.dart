import 'package:flutter/foundation.dart';

/// An opaque, persistable Monaco view state (cursor, scroll position,
/// folded regions).
///
/// Produced by `MonacoController.captureViewState` and consumed by
/// `restoreViewState`. The payload shape belongs to Monaco and is not part
/// of this package's API contract; treat it as a black box that can be
/// serialized with [toJson] and rebuilt with [MonacoViewState.fromJson].
@immutable
final class MonacoViewState {
  /// Wraps a raw Monaco view-state payload.
  ///
  /// The payload is adopted as-is (a const constructor cannot copy); do not
  /// mutate the map after passing it here. Reads through [toJson] always
  /// return an independent copy, so they can never alias internal state.
  const MonacoViewState.fromJson(this._json);

  final Map<String, Object?> _json;

  /// The raw Monaco payload as an independent deep copy, for persistence.
  Map<String, Object?> toJson() =>
      _deepCopyValue(_json)! as Map<String, Object?>;

  /// Whether the payload carries any state at all.
  bool get isEmpty => _json.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is MonacoViewState && _deepEquals(other._json, _json);

  @override
  int get hashCode => _deepHash(_json);

  @override
  String toString() => 'MonacoViewState(${_json.length} entries)';
}

Object? _deepCopyValue(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): _deepCopyValue(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _deepCopyValue(item)];
  }
  return value;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    // XOR-fold so the hash is order-insensitive, matching map equality.
    var hash = 0;
    for (final entry in value.entries) {
      hash ^= Object.hash(entry.key, _deepHash(entry.value));
    }
    return hash;
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}
