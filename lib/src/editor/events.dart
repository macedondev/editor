import 'package:flutter/foundation.dart';
import 'package:flutter_monaco/src/protocol/envelope.dart';
import 'package:flutter_monaco/src/types/geometry.dart';
import 'package:flutter_monaco/src/types/scroll_handoff.dart';
import 'package:flutter_monaco/src/types/text.dart';

/// A decoded editor event from the `MonacoController.events` stream.
///
/// The union is sealed for exhaustive switching; events this package
/// version does not know surface as [MonacoUnknownEvent] (never dropped,
/// never thrown) so apps stay forward-compatible with newer pages.
sealed class MonacoEvent {
  const MonacoEvent();

  /// Decodes a wire event into the typed union.
  ///
  /// Malformed payloads for KNOWN event names degrade to
  /// [MonacoUnknownEvent] rather than throwing: an event stream must
  /// survive a bad payload (there is no caller to catch per-event parse
  /// errors).
  static MonacoEvent fromProtocolEvent(ProtocolEvent event) {
    final data = event.data;
    try {
      switch (event.name) {
        case 'contentChanged':
          final rawChanges = data['changes'];
          return MonacoContentChanged(
            documentUri: data['uri'] is String
                ? Uri.tryParse(data['uri']! as String)
                : null,
            isFlush: data['isFlush'] == true,
            changes: rawChanges is List
                ? rawChanges
                      .whereType<Map>()
                      .map(
                        (c) => MonacoTextChange.fromJson(
                          Map<String, dynamic>.from(c),
                        ),
                      )
                      .toList()
                : null,
            truncated: data['truncated'] == true,
            versionId: data['versionId'] is int
                ? data['versionId'] as int
                : (data['versionId'] is num
                    ? (data['versionId'] as num).toInt()
                    : null),
            isUndoing: data['isUndoing'] == true,
            isRedoing: data['isRedoing'] == true,
          );
        case 'selectionChanged':
          final selection = data['selection'];
          return MonacoSelectionChanged(
            selection: selection is Map
                ? Range.fromJson(Map<String, dynamic>.from(selection))
                : null,
          );
        case 'focusChanged':
          return MonacoFocusChanged(focused: data['focused'] == true);
        case 'scrollHandoff':
          final details = MonacoScrollHandoffDetails.tryParse(
            Map<String, dynamic>.from(data),
          );
          if (details != null) {
            return MonacoScrollHandoffEvent(details: details);
          }
      }
    } catch (e) {
      debugPrint('[MonacoEvent] Failed to decode "${event.name}": $e');
    }
    return MonacoUnknownEvent(name: event.name, data: data);
  }
}

/// The document content changed.
final class MonacoContentChanged extends MonacoEvent {
  /// Creates a content-changed event.
  const MonacoContentChanged({
    required this.isFlush,
    required this.truncated,
    this.documentUri,
    this.changes,
    this.versionId,
    this.isUndoing = false,
    this.isRedoing = false,
  });

  /// URI of the changed document, when the model carries one.
  final Uri? documentUri;

  /// Whether the change replaced the whole document (e.g. `setText`).
  final bool isFlush;

  /// The individual text deltas, oldest first. `null` when [truncated].
  final List<MonacoTextChange>? changes;

  /// `true` when [changes] was omitted because the event was too large to
  /// ship (over 64 KiB of inserted text, or more than 1000 individual
  /// changes); pull the full text instead.
  final bool truncated;

  /// Monotonic model version (alternative version id) when available.
  final int? versionId;

  /// Whether this change is part of an undo.
  final bool isUndoing;

  /// Whether this change is part of a redo.
  final bool isRedoing;
}

/// The primary selection changed.
final class MonacoSelectionChanged extends MonacoEvent {
  /// Creates a selection-changed event.
  const MonacoSelectionChanged({this.selection});

  /// The new primary selection, or `null` when there is none.
  final Range? selection;
}

/// Monaco DOM focus was gained or lost.
final class MonacoFocusChanged extends MonacoEvent {
  /// Creates a focus-changed event.
  const MonacoFocusChanged({required this.focused});

  /// Whether the editor now has DOM focus.
  final bool focused;
}

/// The editor could not consume a scroll delta (edge scroll handoff).
final class MonacoScrollHandoffEvent extends MonacoEvent {
  /// Creates a scroll-handoff event.
  const MonacoScrollHandoffEvent({required this.details});

  /// The unconsumed scroll delta and its source.
  final MonacoScrollHandoffDetails details;
}

/// An event this package version does not know.
final class MonacoUnknownEvent extends MonacoEvent {
  /// Creates an unknown event.
  const MonacoUnknownEvent({required this.name, required this.data});

  /// The wire event name.
  final String name;

  /// The raw event payload.
  final Map<String, Object?> data;
}
