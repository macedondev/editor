import 'package:flutter_monaco/src/types/geometry.dart';

/// A single inline completion (ghost text) candidate.
///
/// Maps to `monaco.languages.InlineCompletion`:
/// `{ insertText: string, range?: IRange }`.
/// `range` when omitted defaults to the provider's
/// word-at-position range on the JS side.
class InlineCompletionItem {
  const InlineCompletionItem({
    required this.insertText,
    this.range,
    this.command,
  });

  /// Text to preview as ghost text. May contain newlines.
  final String insertText;

  /// Range to replace when accepted. `null` means use default word range.
  final Range? range;

  /// Optional command id to run after acceptance (rare).
  final String? command;

  factory InlineCompletionItem.fromJson(Map<String, dynamic> json) {
    final insertText = json['insertText'];
    if (insertText is! String) {
      throw FormatException(
        'InlineCompletionItem.fromJson: missing/invalid "insertText" (expected String, was ${insertText.runtimeType})',
      );
    }
    Range? range;
    final rawRange = json['range'];
    if (rawRange != null) {
      if (rawRange is Map) {
        range = Range.fromJson(Map<String, dynamic>.from(rawRange));
      } else {
        throw FormatException(
          'InlineCompletionItem.fromJson: invalid "range" (expected Map, was ${rawRange.runtimeType})',
        );
      }
    }
    final command = json['command'];
    if (command != null && command is! String) {
      throw FormatException(
        'InlineCompletionItem.fromJson: invalid "command" (expected String, was ${command.runtimeType})',
      );
    }
    return InlineCompletionItem(
      insertText: insertText,
      range: range,
      command: command as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'insertText': insertText,
        if (range != null) 'range': range!.toJson(),
        if (command != null) 'command': command,
      };

  @override
  String toString() => 'InlineCompletionItem(insertText: $insertText, range: $range)';

  @override
  bool operator ==(Object other) =>
      other is InlineCompletionItem &&
      other.insertText == insertText &&
      other.range == range &&
      other.command == command;

  @override
  int get hashCode => Object.hash(insertText, range, command);
}

/// A list of inline completion candidates returned by a provider.
class InlineCompletionList {
  const InlineCompletionList({required this.items});

  final List<InlineCompletionItem> items;

  factory InlineCompletionList.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    if (raw is! List) {
      throw FormatException(
        'InlineCompletionList.fromJson: missing/invalid "items" (expected List, was ${raw.runtimeType})',
      );
    }
    return InlineCompletionList(
      items: [
        for (final e in raw)
          InlineCompletionItem.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'items': [for (final i in items) i.toJson()],
      };

  static const empty = InlineCompletionList(items: []);
}

/// Trigger kind for inline completions, mirrors Monaco's InlineCompletionTriggerKind.
enum InlineCompletionTriggerKind {
  automatic(0),
  explicit(1);

  const InlineCompletionTriggerKind(this.value);
  final int value;

  static InlineCompletionTriggerKind fromValue(int v) =>
      v == 1 ? explicit : automatic;
}

/// Context passed with inline completion requests.
class InlineCompletionContext {
  const InlineCompletionContext({required this.triggerKind});

  final InlineCompletionTriggerKind triggerKind;

  factory InlineCompletionContext.fromJson(Map<String, dynamic> json) {
    final raw = json['triggerKind'];
    final kind = raw is int ? InlineCompletionTriggerKind.fromValue(raw) : InlineCompletionTriggerKind.automatic;
    return InlineCompletionContext(triggerKind: kind);
  }

  Map<String, dynamic> toJson() => {'triggerKind': triggerKind.value};
}

/// Request sent to Dart when Monaco asks for inline completions.
class InlineCompletionRequest {
  const InlineCompletionRequest({
    required this.providerId,
    required this.requestId,
    required this.language,
    this.uri,
    required this.position,
    this.range,
    required this.context,
  });

  final String providerId;
  final String requestId;
  final String language;
  final Uri? uri;
  final Position position;
  final Range? range;
  final InlineCompletionContext context;

  factory InlineCompletionRequest.fromJson(Map<String, dynamic> json) {
    String req(String k) {
      final v = json[k];
      if (v is String) return v;
      throw FormatException('InlineCompletionRequest.fromJson: missing "$k"');
    }

    final posRaw = json['position'];
    if (posRaw is! Map) {
      throw FormatException('InlineCompletionRequest: missing position');
    }
    final ctxRaw = json['context'];
    return InlineCompletionRequest(
      providerId: req('providerId'),
      requestId: req('requestId'),
      language: req('language'),
      uri: json['uri'] is String ? Uri.tryParse(json['uri'] as String) : null,
      position: Position.fromJson(Map<String, dynamic>.from(posRaw)),
      range: json['range'] is Map
          ? Range.fromJson(Map<String, dynamic>.from(json['range'] as Map))
          : null,
      context: ctxRaw is Map
          ? InlineCompletionContext.fromJson(Map<String, dynamic>.from(ctxRaw))
          : const InlineCompletionContext(triggerKind: InlineCompletionTriggerKind.automatic),
    );
  }

  Map<String, dynamic> toJson() => {
        'providerId': providerId,
        'requestId': requestId,
        'language': language,
        if (uri != null) 'uri': uri.toString(),
        'position': position.toJson(),
        if (range != null) 'range': range!.toJson(),
        'context': context.toJson(),
      };
}
