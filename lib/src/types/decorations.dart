import 'package:flutter_monaco/src/types/geometry.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'decorations.freezed.dart';

/// Defines options for applying decorations to text in the editor.
@freezed
sealed class DecorationOptions with _$DecorationOptions {
  /// Creates a decoration with a specified [range] and a map of [options].
  const factory DecorationOptions({
    /// The range to which the decoration should be applied.
    required Range range,

    /// A map of Monaco-specific decoration options.
    @Default({}) Map<String, dynamic> options,
  }) = _DecorationOptions;

  /// A convenience factory for creating a decoration with an inline CSS class.
  factory DecorationOptions.inlineClass({
    required Range range,
    required String className,
    String? hoverMessage,
    Map<String, dynamic>? additionalOptions,
  }) {
    return DecorationOptions(
      range: range,
      options: {
        'inlineClassName': className,
        'hoverMessage': ?hoverMessage,
        ...?additionalOptions,
      },
    );
  }

  /// A convenience factory for creating a decoration in the glyph margin.
  factory DecorationOptions.glyphMargin({
    required Range range,
    required String className,
    String? hoverMessage,
    Map<String, dynamic>? additionalOptions,
  }) {
    return DecorationOptions(
      range: range,
      options: {
        'glyphMarginClassName': className,
        'glyphMarginHoverMessage': ?hoverMessage,
        ...?additionalOptions,
      },
    );
  }

  /// A convenience factory for applying a CSS class to an entire line.
  factory DecorationOptions.line({
    required Range range,
    required String className,
    bool isWholeLine = true,
    Map<String, dynamic>? additionalOptions,
  }) {
    return DecorationOptions(
      range: range,
      options: {
        'className': className,
        'isWholeLine': isWholeLine,
        ...?additionalOptions,
      },
    );
  }

  const DecorationOptions._();

  /// Creates a [DecorationOptions] object from a JSON map.
  ///
  /// Expects a required `range` map; `options` defaults to an empty map when
  /// absent. Throws a [FormatException] if `range` is missing or any present
  /// key has the wrong type.
  factory DecorationOptions.fromJson(Map<String, dynamic> json) {
    return DecorationOptions(
      range: Range.fromJson(_requireMap(json, 'DecorationOptions', 'range')),
      options:
          _optionalMap(json, 'DecorationOptions', 'options') ??
          const <String, dynamic>{},
    );
  }

  /// Converts the decoration options to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'range': range.toJson(),
    'options': options,
  };
}

/// Throws a [FormatException] describing a missing or invalid wire value.
Never _fail(String type, String key, String expected, Object? value) {
  final actual = value == null ? 'missing or null' : '${value.runtimeType}';
  throw FormatException(
    '$type.fromJson: missing/invalid "$key" (expected $expected, was $actual)',
  );
}

/// Reads a required nested JSON object at [key].
Map<String, dynamic> _requireMap(
  Map<String, dynamic> json,
  String type,
  String key,
) {
  final value = json[key];
  if (value is Map) return Map<String, dynamic>.from(value);
  _fail(type, key, 'Map', value);
}

/// Reads an optional nested JSON object at [key]; `null` when absent.
Map<String, dynamic>? _optionalMap(
  Map<String, dynamic> json,
  String type,
  String key,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is Map) return Map<String, dynamic>.from(value);
  _fail(type, key, 'Map', value);
}
