import 'package:flutter_monaco/src/types/geometry.dart';

/// A pending AI edit proposal that has not yet been applied to the model.
///
/// Keeps original range + replacement text plus a stable [id] for accept/reject.
class InlineEdit {
  const InlineEdit({
    required this.id,
    required this.range,
    required this.text,
    this.originalText,
  });

  final String id;
  final Range range;
  final String text;
  final String? originalText;

  factory InlineEdit.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) throw FormatException('InlineEdit missing id');
    final rangeRaw = json['range'];
    if (rangeRaw is! Map) throw FormatException('InlineEdit missing range');
    final text = json['text'];
    if (text is! String) throw FormatException('InlineEdit missing text');
    return InlineEdit(
      id: id,
      range: Range.fromJson(Map<String, dynamic>.from(rangeRaw)),
      text: text,
      originalText: json['originalText'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'range': range.toJson(),
        'text': text,
        if (originalText != null) 'originalText': originalText,
      };
}

/// Status of a pending edit.
enum InlineEditStatus { pending, accepted, rejected }

/// Result of an inline edit operation.
class InlineEditResult {
  const InlineEditResult({required this.id, required this.status});
  final String id;
  final InlineEditStatus status;
}
